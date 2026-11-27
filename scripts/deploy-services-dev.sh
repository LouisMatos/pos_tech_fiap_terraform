#!/usr/bin/env bash
# Sobe os 3 serviços (pedido, pagamento, producao) no EKS dev, sem depender do CI.
# Pré-requisito: scripts/deploy-dev-fresh-account.sh terminou (cluster, RDS, LBC,
# scripts/outputs-dev.json).
#
# Etapas: build/push das imagens -> secrets k8s -> RabbitMQ -> overlay dev de cada
# serviço (cópia temporária, o repo não é alterado) -> rollout -> ALB -> smoke.
#
# Uso:
#   ./scripts/deploy-services-dev.sh
#
# Variáveis de ambiente:
#   IMAGE_PLATFORM  plataforma das imagens, default linux/arm64 (casar com node_ami_type)

set -euo pipefail

# A região default da máquina pode ser sa-east-1; toda a infra é us-east-1.
export AWS_DEFAULT_REGION=us-east-1
REGION="${AWS_DEFAULT_REGION}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_REPO="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORKSPACE="$(cd "${TERRAFORM_REPO}/.." && pwd)"
OUTPUTS_FILE="${SCRIPT_DIR}/outputs-dev.json"
IMAGE_PLATFORM="${IMAGE_PLATFORM:-linux/arm64}"
ENVIRONMENT=dev
NAMESPACE=default
SERVICES="pedido pagamento producao"

# CPF válido de teste (dígitos verificadores corretos) pro POST /jwt.
SMOKE_CPF="52998224725"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
warn() { printf '\n\033[1;33m!! %s\033[0m\n' "$1"; }
die() { printf '\n\033[1;31mERRO: %s\033[0m\n' "$1" >&2; exit 1; }

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT

# --- 1. Preflight -----------------------------------------------------------
log "Preflight"

for tool in aws kubectl docker jq openssl curl git; do
  command -v "${tool}" >/dev/null 2>&1 || die "${tool} não encontrado."
done
[ -f "${OUTPUTS_FILE}" ] || die "${OUTPUTS_FILE} não existe. Rode scripts/deploy-dev-fresh-account.sh primeiro."

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)" || die "Credenciais AWS inválidas."
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
CLUSTER_NAME="$(jq -r '.terraform.eks_cluster_name.value' "${OUTPUTS_FILE}")"
API_URL="$(jq -r '.lambda_terraform.main_url.value // empty' "${OUTPUTS_FILE}")"

aws eks update-kubeconfig --region "${REGION}" --name "${CLUSTER_NAME}" >/dev/null
echo "Conta ${ACCOUNT_ID}, cluster ${CLUSTER_NAME}, plataforma ${IMAGE_PLATFORM}"

# --- 2. Build e push das imagens --------------------------------------------
log "Build e push das imagens (${IMAGE_PLATFORM})"

aws ecr get-login-password --region "${REGION}" \
  | docker login --username AWS --password-stdin "${ECR_REGISTRY}"

for svc in ${SERVICES}; do
  repo="${WORKSPACE}/pos_tech_fiap_${svc}"
  [ -d "${repo}" ] || die "Repo ${repo} não encontrado."

  # Tag sha-<sha>. O ECR é IMMUTABLE: working tree sujo ganha sufixo -d<ts>,
  # senão a tag colide com a imagem já publicada do mesmo commit.
  tag="sha-$(git -C "${repo}" rev-parse --short HEAD)"
  if [ -n "$(git -C "${repo}" status --porcelain)" ]; then
    tag="${tag}-d$(date +%Y%m%d%H%M%S)"
  fi
  echo "${tag}" >"${TMP_ROOT}/${svc}.tag"

  if aws ecr describe-images --region "${REGION}" --repository-name "jlapp-${svc}" \
    --image-ids "imageTag=${tag}" >/dev/null 2>&1; then
    echo "jlapp-${svc}:${tag} já existe no ECR, pulando build."
  else
    docker buildx build --platform "${IMAGE_PLATFORM}" \
      -t "${ECR_REGISTRY}/jlapp-${svc}:${tag}" --push "${repo}"
  fi
done

# --- 3. Secrets k8s -----------------------------------------------------------
log "Secrets k8s"

# create + apply: idempotente (create sozinho falha se o secret já existe).
apply_secret() { # nome, args de 'kubectl create secret generic'...
  local name="$1"
  shift
  kubectl create secret generic "${name}" -n "${NAMESPACE}" "$@" --dry-run=client -o yaml \
    | kubectl apply -f -
}

# Valor de uma chave de secret existente; vazio se o secret não existe.
secret_value() { # nome, chave
  kubectl get secret "$1" -n "${NAMESPACE}" -o "jsonpath={.data.$2}" 2>/dev/null | base64 -d 2>/dev/null || true
}

# Bancos (RDS): credenciais vêm do Secrets Manager criado pelo Terraform.
db_secret() { # serviço, esquema jdbc
  local svc="$1" scheme="$2" json
  json="$(aws secretsmanager get-secret-value --region "${REGION}" \
    --secret-id "jlapp-cluster-${ENVIRONMENT}-${svc}-db-credentials" \
    --query SecretString --output text)"
  apply_secret "${svc}-db-secret" \
    --from-literal=url="jdbc:${scheme}://$(echo "${json}" | jq -r .host):$(echo "${json}" | jq -r .port)/$(echo "${json}" | jq -r .dbname)" \
    --from-literal=username="$(echo "${json}" | jq -r .username)" \
    --from-literal=password="$(echo "${json}" | jq -r .password)"
}
db_secret pedido postgresql
db_secret producao mysql

# RabbitMQ: senha gerada uma vez e reaproveitada (o broker já inicializou com ela).
MQ_USER="jlapp"
MQ_PASS="$(secret_value rabbitmq-credentials password)"
[ -n "${MQ_PASS}" ] || MQ_PASS="$(openssl rand -hex 16)"
apply_secret rabbitmq-credentials --from-literal=username="${MQ_USER}" --from-literal=password="${MQ_PASS}"
apply_secret shared-mq-secret \
  --from-literal=host=rabbitmq --from-literal=port=5672 \
  --from-literal=username="${MQ_USER}" --from-literal=password="${MQ_PASS}"

# MongoDB do pagamento (StatefulSet do overlay dev): mesma regra, não regerar a senha.
MONGO_USER="root"
MONGO_PASS="$(secret_value mongo-creds password)"
[ -n "${MONGO_PASS}" ] || MONGO_PASS="$(openssl rand -hex 16)"
apply_secret mongo-creds --from-literal=username="${MONGO_USER}" --from-literal=password="${MONGO_PASS}"
apply_secret pagamento-db-secret \
  --from-literal=uri="mongodb://${MONGO_USER}:${MONGO_PASS}@mongodb-0.mongodb.${NAMESPACE}.svc.cluster.local:27017/jlapp-pagamento?authSource=admin"

# --- 4. RabbitMQ ---------------------------------------------------------------
log "RabbitMQ (StatefulSet)"

kubectl apply -n "${NAMESPACE}" -f "${TERRAFORM_REPO}/k8s-bootstrap/dev/rabbitmq.yaml"
kubectl rollout status statefulset/rabbitmq -n "${NAMESPACE}" --timeout=300s

# --- 5. Serviços -----------------------------------------------------------------
for svc in ${SERVICES}; do
  log "Deploy: ${svc}"

  repo="${WORKSPACE}/pos_tech_fiap_${svc}"
  tag="$(cat "${TMP_ROOT}/${svc}.tag")"
  role_arn="$(jq -r --arg k "irsa_${svc}_role_arn" '.terraform[$k].value' "${OUTPUTS_FILE}")"
  [ -n "${role_arn}" ] && [ "${role_arn}" != "null" ] || die "Output irsa_${svc}_role_arn ausente em ${OUTPUTS_FILE}."

  # Copia k8s/ inteiro (o overlay referencia ../../base) e edita só a cópia.
  work="${TMP_ROOT}/${svc}"
  mkdir -p "${work}"
  cp -R "${repo}/k8s" "${work}/k8s"
  overlay="${work}/k8s/overlays/${ENVIRONMENT}"

  sed "s#REPLACE_IRSA_ROLE_ARN#${role_arn}#" "${overlay}/service-account-patch.yaml" >"${overlay}/service-account-patch.yaml.new"
  mv "${overlay}/service-account-patch.yaml.new" "${overlay}/service-account-patch.yaml"

  cat >>"${overlay}/kustomization.yaml" <<EOF

images:
  - name: jlapp-${svc}
    newName: ${ECR_REGISTRY}/jlapp-${svc}
    newTag: ${tag}
EOF

  kubectl apply -k "${overlay}"
done

# Aplica os 3 antes de esperar: com maxSurge 0 e nodes no limite de memória, o
# rollout de um serviço só cabe depois que os outros liberam o request antigo.
for svc in ${SERVICES}; do
  kubectl rollout status "deployment/jlapp-${svc}-deployment" -n "${NAMESPACE}" --timeout=300s
done

# --- 6. Hostname do ALB (polling) --------------------------------------------------
# Não usar 'kubectl wait' em condition do Ingress: o LBC 2.13 não seta a condição
# Programmed e o wait trava. O sinal confiável é o hostname em .status.loadBalancer.
log "Aguardando o hostname do ALB (até 10 min)"

ALB_HOST=""
for _ in $(seq 1 60); do
  ALB_HOST="$(kubectl get ingress jlapp-pedido-ingress -n "${NAMESPACE}" \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  [ -n "${ALB_HOST}" ] && break
  sleep 10
done
[ -n "${ALB_HOST}" ] || die "ALB sem hostname após 10 min (veja: kubectl describe ingress jlapp-pedido-ingress; logs do aws-load-balancer-controller)."
echo "ALB: http://${ALB_HOST}"

# --- 7. Smoke ----------------------------------------------------------------------
log "Smoke test"

# O DNS e o registro dos targets demoram um pouco depois do hostname aparecer:
# tenta por até ~5 min.
smoke() { # método, url, [corpo json]
  local method="$1" url="$2" body="${3:-}" code=000
  for _ in $(seq 1 30); do
    if [ -n "${body}" ]; then
      code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 -X "${method}" \
        -H 'Content-Type: application/json' -d "${body}" "${url}" || true)"
    else
      code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 -X "${method}" "${url}" || true)"
    fi
    [ "${code}" = "200" ] && break
    sleep 10
  done
  echo "${method} ${url} -> HTTP ${code}"
  [ "${code}" = "200" ]
}

SMOKE_FAILED=0
smoke GET "http://${ALB_HOST}/api/v1/produtos" || SMOKE_FAILED=1
# producao não tem GET sem parâmetro (só /api/v1/producao/{numero_pedido}): a
# readiness dele já foi checada no rollout e no healthcheck do ALB; o fluxo
# pedido -> pagamento -> producao é validado no G3.
if [ -n "${API_URL}" ]; then
  smoke POST "${API_URL}/jwt" "{\"cpf\":\"${SMOKE_CPF}\"}" || SMOKE_FAILED=1
else
  warn "main_url do API Gateway ausente em ${OUTPUTS_FILE}: smoke do /jwt pulado."
  SMOKE_FAILED=1
fi

log "Deploy dos serviços concluído (smoke rc=${SMOKE_FAILED})"
echo "ALB        : http://${ALB_HOST}"
echo "API Gateway: ${API_URL:-UNKNOWN}"
echo "Imagens    : $(for svc in ${SERVICES}; do printf '%s:%s ' "${svc}" "$(cat "${TMP_ROOT}/${svc}.tag")"; done)"
echo "Quando terminar: ./scripts/destroy-dev-fresh-account.sh"
exit "${SMOKE_FAILED}"
