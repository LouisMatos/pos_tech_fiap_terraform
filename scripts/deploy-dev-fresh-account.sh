#!/usr/bin/env bash
# Sobe a INFRA do ambiente dev numa conta AWS nova, gastando o mínimo.
# Os serviços (pedido, pagamento, producao) sobem depois, com
# scripts/deploy-services-dev.sh.
#
# Etapas: preflight -> budget -> ECR -> build da imagem da Lambda ->
# applies em paralelo (terraform, db, lambda_terraform) -> kubeconfig ->
# Helm do AWS Load Balancer Controller + k8s-bootstrap -> outputs -> gh secrets.
# State LOCAL nos 3 repos (dev nunca usa o backend S3 de hom/prod).
#
# Uso:
#   ./scripts/deploy-dev-fresh-account.sh [--yes] [teto_mensal_usd]
#
# Variáveis de ambiente:
#   AWS_BUDGET_EMAIL  e-mail do alerta de orçamento (senão o script pergunta)
#   LAMBDA_ARCH       arquitetura da Lambda e da imagem (arm64 | x86_64), default arm64
#   IMAGE_PLATFORM    plataforma das imagens dos serviços, default linux/arm64
#                     (precisa casar com node_ami_type de envs/dev.tfvars)

set -euo pipefail

# A região default da máquina pode ser sa-east-1; toda a infra é us-east-1.
export AWS_DEFAULT_REGION=us-east-1
REGION="${AWS_DEFAULT_REGION}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_REPO="$(cd "${SCRIPT_DIR}/.." && pwd)"
DB_REPO="$(cd "${TERRAFORM_REPO}/../pos_tech_fiap_db" && pwd)"
LAMBDA_TF_REPO="$(cd "${TERRAFORM_REPO}/../pos_tech_fiap_lambda_terraform" && pwd)"
LAMBDA_REPO="$(cd "${TERRAFORM_REPO}/../pos_tech_fiap_lambda" && pwd)"

TFVARS="${TERRAFORM_REPO}/envs/dev.tfvars"
LOG_DIR="${SCRIPT_DIR}/logs"
OUTPUTS_FILE="${SCRIPT_DIR}/outputs-dev.json"
LBC_CHART_VERSION="1.13.0" # app v2.13.0; o chart embute as CRDs (não aplicar CRDs à mão)
LAMBDA_ARCH="${LAMBDA_ARCH:-arm64}"
IMAGE_PLATFORM="${IMAGE_PLATFORM:-linux/arm64}"
NOTIFICATION_EMAIL="${AWS_BUDGET_EMAIL:-}"

ASSUME_YES=0
BUDGET_LIMIT=50
for arg in "$@"; do
  case "${arg}" in
    --yes) ASSUME_YES=1 ;;
    *) BUDGET_LIMIT="${arg}" ;;
  esac
done

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
warn() { printf '\n\033[1;33m!! %s\033[0m\n' "$1"; }
die() { printf '\n\033[1;31mERRO: %s\033[0m\n' "$1" >&2; exit 1; }

# Valor de uma variável simples (string, número ou bool) do envs/dev.tfvars.
# Ignora comentário no fim da linha. Vazio se a variável não existir.
tfvar() {
  grep -E "^[[:space:]]*$1[[:space:]]*=" "${TFVARS}" | head -n 1 \
    | sed -E 's/^[^=]*=[[:space:]]*"?([^"#[:space:]]*).*/\1/' || true
}

# Se qualquer coisa falhar depois daqui, mostra o que já subiu (e pode estar
# cobrando) em vez de só abortar.
on_error() {
  local exit_code=$?
  warn "Deploy falhou (exit code ${exit_code})."
  echo "Recursos já criados continuam ativos e podem estar cobrando:"
  for repo_dir in "${TERRAFORM_REPO}" "${DB_REPO}" "${LAMBDA_TF_REPO}"; do
    if [ -d "${repo_dir}/.terraform" ]; then
      echo ""
      echo "--- $(basename "${repo_dir}") ---"
      (cd "${repo_dir}" && terraform state list 2>/dev/null) || echo "(sem state ainda)"
    fi
  done
  echo ""
  echo "Corrija o problema e rode o script de novo (é idempotente, retoma do"
  echo "state local) ou rode ./scripts/destroy-dev-fresh-account.sh."
}
trap on_error ERR

# --- 1. Preflight -----------------------------------------------------------
log "Preflight: verificando AWS CLI, credenciais e dependências"

for tool in aws terraform jq helm kubectl docker; do
  command -v "${tool}" >/dev/null 2>&1 || die "${tool} não encontrado. Instale antes de continuar."
done
docker buildx version >/dev/null 2>&1 || die "docker buildx não encontrado (necessário pro build das imagens)."

CALLER_IDENTITY="$(aws sts get-caller-identity --output json)" || die "Credenciais AWS inválidas ou não configuradas. Rode 'aws configure' primeiro."
ACCOUNT_ID="$(echo "${CALLER_IDENTITY}" | jq -r '.Account')"
CALLER_ARN="$(echo "${CALLER_IDENTITY}" | jq -r '.Arn')"
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "Account ID : ${ACCOUNT_ID}"
echo "Caller     : ${CALLER_ARN}"
echo "Região     : ${REGION}"
echo "Lambda     : ${LAMBDA_ARCH}   Imagens dos serviços: ${IMAGE_PLATFORM}"
echo ""
warn "Contas AWS novas às vezes entram num 'Free Plan' restrito que bloqueia"
echo "DocumentDB (só libera Aurora PostgreSQL). enable_documentdb=false em"
echo "envs/dev.tfvars contorna isso usando MongoDB em StatefulSet."
echo ""

if [ "${ASSUME_YES}" -eq 1 ]; then
  echo "[--yes] Confirma que essa é a conta AWS NOVA de teste que você quer usar? -> assumido sim"
else
  read -r -p "Confirma que essa é a conta AWS NOVA de teste que você quer usar? [y/N] " CONFIRM
  [[ "${CONFIRM}" == "y" || "${CONFIRM}" == "Y" ]] || die "Abortado pelo usuário."
fi

# A plataforma das imagens precisa casar com a AMI dos nodes (exec format error).
NODE_AMI_TYPE="$(tfvar node_ami_type)"
case "${NODE_AMI_TYPE}" in
  *ARM*) [ "${IMAGE_PLATFORM}" = "linux/arm64" ] || die "node_ami_type=${NODE_AMI_TYPE} é arm64, mas IMAGE_PLATFORM=${IMAGE_PLATFORM}." ;;
  "") ;;
  *) [ "${IMAGE_PLATFORM}" = "linux/amd64" ] || die "node_ami_type=${NODE_AMI_TYPE} é x86_64, mas IMAGE_PLATFORM=${IMAGE_PLATFORM}." ;;
esac

# --- 1.5 Checar versão do EKS ANTES de criar qualquer recurso pago ----------
log "Checando se o k8s_version configurado está em standard support"

K8S_VERSION="$(tfvar k8s_version)"
EKS_VERSIONS_TMP="$(mktemp)"

if aws eks describe-cluster-versions --output json >"${EKS_VERSIONS_TMP}" 2>/dev/null; then
  STATUS="$(jq -r --arg v "${K8S_VERSION}" '.clusterVersions[]? | select(.clusterVersion == $v) | .versionStatus' "${EKS_VERSIONS_TMP}")"
  rm -f "${EKS_VERSIONS_TMP}"
  if [ "${STATUS}" != "STANDARD_SUPPORT" ]; then
    die "k8s_version=${K8S_VERSION} (envs/dev.tfvars) não está em standard support (status: '${STATUS:-não encontrado}'). Rode 'aws eks describe-cluster-versions --output table', escolha uma versão STANDARD_SUPPORT e atualize o tfvars. Versão fora disso entra em extended support: +\$0.60/h/cluster (~+\$438/mês)."
  fi
  echo "k8s_version=${K8S_VERSION}: OK (standard support)."
else
  rm -f "${EKS_VERSIONS_TMP}"
  warn "Não deu pra checar automaticamente (aws-cli sem 'describe-cluster-versions' ou sem permissão)."
  echo "k8s_version atual: ${K8S_VERSION}. Confirme que está STANDARD_SUPPORT (extended support: +\$0.60/h/cluster)."
  if [ "${ASSUME_YES}" -ne 1 ]; then
    read -r -p "Já conferiu e está OK? [y/N] " K8S_CONFIRM
    [[ "${K8S_CONFIRM}" == "y" || "${K8S_CONFIRM}" == "Y" ]] || die "Abortado: confirme a versão do EKS antes de rodar."
  fi
fi

# --- 1.6 Checar tipo de instância/engine do Amazon MQ (só se enable_mq=true) -
ENABLE_MQ="$(tfvar enable_mq)"
ENABLE_MQ="${ENABLE_MQ:-true}" # default da variável Terraform é true
if [ "${ENABLE_MQ}" = "true" ]; then
  log "Checando se mq_instance_type é válido pra engine RabbitMQ"

  MQ_INSTANCE_TYPE="$(tfvar mq_instance_type)"
  MQ_ENGINE_VERSION="$(grep -A2 'variable "engine_version"' "${TERRAFORM_REPO}/modules/mq/variables.tf" | grep default | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/')"
  MQ_OPTIONS_TMP="$(mktemp)"

  if aws mq describe-broker-instance-options --engine-type RABBITMQ --output json >"${MQ_OPTIONS_TMP}" 2>/dev/null; then
    VALID="$(jq -r --arg t "${MQ_INSTANCE_TYPE}" --arg v "${MQ_ENGINE_VERSION}" \
      '.BrokerInstanceOptions[]? | select(.HostInstanceType == $t) | .SupportedEngineVersions[]? | select(. == $v)' \
      "${MQ_OPTIONS_TMP}")"
    if [ -z "${VALID}" ]; then
      warn "mq_instance_type=${MQ_INSTANCE_TYPE} não suporta engine RabbitMQ ${MQ_ENGINE_VERSION} nesta conta/região."
      jq -r '.BrokerInstanceOptions[]? | "\(.HostInstanceType): \(.SupportedEngineVersions | join(", "))"' "${MQ_OPTIONS_TMP}"
      rm -f "${MQ_OPTIONS_TMP}"
      die "Atualize mq_instance_type em envs/dev.tfvars (ou engine_version em modules/mq/variables.tf) pra uma combinação da lista acima."
    fi
    rm -f "${MQ_OPTIONS_TMP}"
    echo "mq_instance_type=${MQ_INSTANCE_TYPE} + engine ${MQ_ENGINE_VERSION}: OK."
  else
    rm -f "${MQ_OPTIONS_TMP}"
    warn "Não deu pra checar automaticamente (aws-cli sem 'describe-broker-instance-options' ou sem permissão)."
    if [ "${ASSUME_YES}" -ne 1 ]; then
      read -r -p "Já conferiu que mq_instance_type=${MQ_INSTANCE_TYPE} é válido pra engine ${MQ_ENGINE_VERSION}? [y/N] " MQ_CONFIRM
      [[ "${MQ_CONFIRM}" == "y" || "${MQ_CONFIRM}" == "Y" ]] || die "Abortado: confirme o tipo de instância do MQ antes de rodar."
    fi
  fi
else
  log "enable_mq=${ENABLE_MQ}: RabbitMQ roda em StatefulSet no cluster, pulando checagem do Amazon MQ"
fi

# --- 2. AWS Budget com alerta -------------------------------------------------
log "AWS Budget (guardrail de custo, teto \$${BUDGET_LIMIT}/mês)"

BUDGET_NAME="jlapp-dev-budget"

if aws budgets describe-budget --account-id "${ACCOUNT_ID}" --budget-name "${BUDGET_NAME}" >/dev/null 2>&1; then
  echo "Budget '${BUDGET_NAME}' já existe, pulando criação."
else
  if [ -z "${NOTIFICATION_EMAIL}" ] && [ "${ASSUME_YES}" -ne 1 ]; then
    read -r -p "E-mail pra receber alerta de orçamento: " NOTIFICATION_EMAIL
  fi
  if [ -z "${NOTIFICATION_EMAIL}" ]; then
    warn "Sem e-mail (defina AWS_BUDGET_EMAIL): budget NÃO criado."
  else
    aws budgets create-budget \
      --account-id "${ACCOUNT_ID}" \
      --budget "$(jq -n --arg name "${BUDGET_NAME}" --arg limit "${BUDGET_LIMIT}" '{
        BudgetName: $name,
        BudgetLimit: { Amount: $limit, Unit: "USD" },
        TimeUnit: "MONTHLY",
        BudgetType: "COST"
      }')" \
      --notifications-with-subscribers "$(jq -n --arg email "${NOTIFICATION_EMAIL}" '[
        {
          Notification: { NotificationType: "ACTUAL", ComparisonOperator: "GREATER_THAN", Threshold: 80, ThresholdType: "PERCENTAGE" },
          Subscribers: [{ SubscriptionType: "EMAIL", Address: $email }]
        },
        {
          Notification: { NotificationType: "ACTUAL", ComparisonOperator: "GREATER_THAN", Threshold: 100, ThresholdType: "PERCENTAGE" },
          Subscribers: [{ SubscriptionType: "EMAIL", Address: $email }]
        }
      ]')" \
      || warn "Falha ao criar budget: continue manualmente pelo console se necessário."
    echo "Budget: alerta em 80% e 100% de \$${BUDGET_LIMIT}/mês pra ${NOTIFICATION_EMAIL}"
  fi
fi

# --- 3. ECR primeiro (a Lambda precisa da imagem antes do apply) --------------
log "Deploy: criando ECR (pré-requisito da Lambda) antes dos applies em paralelo"

cd "${TERRAFORM_REPO}"
terraform init -input=false
# Só na 1ª execução: -target falha se o state tiver moves pendentes
# ("Moved resource instances excluded by targeting"), e numa reexecução o
# ECR já existe e o apply completo abaixo cuida dele.
if aws ecr describe-repositories --region "${REGION}" --repository-names jlapp-lambda >/dev/null 2>&1; then
  echo "ECR jlapp-lambda já existe: pulando apply com -target."
else
  terraform apply -input=false -auto-approve -var-file=envs/dev.tfvars -target=module.ecr
fi

# --- 3.1 Build + push da imagem da Lambda --------------------------------------
# O CreateFunction falha com "Source image ... does not exist" se o repo estiver
# vazio. --provenance=false --sbom=false é obrigatório: o Lambda rejeita o
# manifest list/attestation que o buildx gera por padrão.
log "Imagem da Lambda (${LAMBDA_ARCH}) -> ${ECR_REGISTRY}/jlapp-lambda:latest"

aws ecr get-login-password --region "${REGION}" \
  | docker login --username AWS --password-stdin "${ECR_REGISTRY}"

# ECR é IMMUTABLE: se :latest já existe (reexecução), não dá pra repushar.
if aws ecr describe-images --region "${REGION}" --repository-name jlapp-lambda \
  --image-ids imageTag=latest >/dev/null 2>&1; then
  echo "jlapp-lambda:latest já existe no ECR, pulando build (repo IMMUTABLE)."
else
  docker buildx build \
    --platform "linux/${LAMBDA_ARCH/x86_64/amd64}" \
    --provenance=false --sbom=false \
    -t "${ECR_REGISTRY}/jlapp-lambda:latest" \
    --push "${LAMBDA_REPO}"
fi

# --- 4. Applies em paralelo ----------------------------------------------------
log "Deploy em paralelo: pos_tech_fiap_terraform (VPC, EKS, RDS, IRSA) + pos_tech_fiap_db (DynamoDB) + pos_tech_fiap_lambda_terraform (Lambda, API Gateway)"

mkdir -p "${LOG_DIR}"

run_apply() {
  local name="$1" dir="$2"
  shift 2
  local rc=0
  (cd "${dir}" \
    && terraform init -input=false \
    && terraform apply -input=false -auto-approve -var-file=envs/dev.tfvars "$@") \
    >"${LOG_DIR}/${name}.log" 2>&1 || rc=$?
  echo "${rc}" >"${LOG_DIR}/${name}.rc"
}

run_apply terraform "${TERRAFORM_REPO}" &
PID_TF=$!
run_apply db "${DB_REPO}" &
PID_DB=$!
# lambda_arch: variável declarada pela T05 em pos_tech_fiap_lambda_terraform.
run_apply lambda "${LAMBDA_TF_REPO}" -var "lambda_arch=${LAMBDA_ARCH}" &
PID_LAMBDA=$!

wait "${PID_TF}" "${PID_DB}" "${PID_LAMBDA}" || true

APPLY_FAILED=0
for name in terraform db lambda; do
  rc="$(cat "${LOG_DIR}/${name}.rc")"
  if [ "${rc}" != "0" ]; then
    APPLY_FAILED=1
    warn "apply '${name}' falhou (rc=${rc}). Últimas linhas de ${LOG_DIR}/${name}.log:"
    tail -n 25 "${LOG_DIR}/${name}.log"
  fi
done
[ "${APPLY_FAILED}" -eq 0 ] || die "Pelo menos um apply falhou (logs em ${LOG_DIR}/)."
echo "Os 3 applies terminaram OK. Logs completos em ${LOG_DIR}/"

# --- 5. Outputs (precisa do cluster e da VPC pro Helm) --------------------------
tf_output() { (cd "$1" && terraform output -json); }

TF_OUT="$(tf_output "${TERRAFORM_REPO}")"
DB_OUT="$(tf_output "${DB_REPO}")"
LAMBDA_OUT="$(tf_output "${LAMBDA_TF_REPO}")"

CLUSTER_NAME="$(echo "${TF_OUT}" | jq -r '.eks_cluster_name.value')"
VPC_ID="$(echo "${TF_OUT}" | jq -r '.vpc_id.value')"
[ -n "${CLUSTER_NAME}" ] && [ "${CLUSTER_NAME}" != "null" ] || die "Output eks_cluster_name ausente."
[ -n "${VPC_ID}" ] && [ "${VPC_ID}" != "null" ] || die "Output vpc_id ausente."

# --- 6. kubeconfig + AWS Load Balancer Controller + bootstrap -------------------
log "Instalando AWS Load Balancer Controller + bootstrap do cluster"

aws eks update-kubeconfig --region "${REGION}" --name "${CLUSTER_NAME}"

# Sem 'kubectl apply' de CRDs: o chart as instala (SSA) e um apply prévio gera
# "Apply failed with N conflicts". O helm é o único dono delas.
helm repo add eks https://aws.github.io/eks-charts --force-update
helm repo update eks
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --version "${LBC_CHART_VERSION}" \
  --namespace kube-system \
  --set clusterName="${CLUSTER_NAME}" \
  --set region="${REGION}" \
  --set vpcId="${VPC_ID}" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --wait --timeout 5m

# Só os arquivos do topo (StorageClass gp3 + IngressClass). O k8s-bootstrap/dev/
# (RabbitMQ) é aplicado pelo deploy-services-dev.sh, depois que o secret existe.
kubectl apply -f "${TERRAFORM_REPO}/k8s-bootstrap/"
kubectl label namespace default elbv2.k8s.aws/pod-readiness-gate-inject=enabled --overwrite
echo "LBC instalado e cluster com bootstrap (StorageClass gp3 + IngressClass alb-jlapp)."

# --- 7. Consolidar outputs ------------------------------------------------------
log "Consolidando outputs em ${OUTPUTS_FILE}"

jq -n --argjson t "${TF_OUT}" --argjson d "${DB_OUT}" --argjson l "${LAMBDA_OUT}" \
  '{terraform: $t, db: $d, lambda_terraform: $l}' >"${OUTPUTS_FILE}"

# --- 8. Secrets do GitHub Actions -------------------------------------------------
IRSA_PEDIDO="$(jq -r '.terraform.irsa_pedido_role_arn.value // empty' "${OUTPUTS_FILE}")"
IRSA_PAGAMENTO="$(jq -r '.terraform.irsa_pagamento_role_arn.value // empty' "${OUTPUTS_FILE}")"
IRSA_PRODUCAO="$(jq -r '.terraform.irsa_producao_role_arn.value // empty' "${OUTPUTS_FILE}")"

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  log "Configurando secrets do GitHub Actions (gh autenticado)"
  for pair in "pedido:PEDIDO:${IRSA_PEDIDO}" "pagamento:PAGAMENTO:${IRSA_PAGAMENTO}" "producao:PRODUCAO:${IRSA_PRODUCAO}"; do
    svc="${pair%%:*}"
    rest="${pair#*:}"
    upper="${rest%%:*}"
    arn="${rest#*:}"
    repo="LouisMatos/pos_tech_fiap_${svc}"
    set -x
    gh secret set AWS_ACCOUNT_ID --body "${ACCOUNT_ID}" --repo "${repo}"
    gh secret set AWS_REGION --body "${REGION}" --repo "${repo}"
    gh secret set "${upper}_IRSA_ROLE_ARN" --body "${arn}" --repo "${repo}"
    { set +x; } 2>/dev/null
  done
else
  warn "gh ausente ou não autenticado: configure os secrets na mão (AWS_ACCOUNT_ID, AWS_REGION, <SVC>_IRSA_ROLE_ARN) nos 3 repos de serviço."
fi

# --- 9. Resumo final -----------------------------------------------------------
log "Deploy da infra concluído"

cat <<EOF
Outputs consolidados em: ${OUTPUTS_FILE}

Recursos criados (conforme envs/dev.tfvars):
  - VPC + subnets + NAT instance, S3 gateway endpoint
  - EKS (${CLUSTER_NAME}) + node group (tipo, AMI e AZ em envs/dev.tfvars)
  - RDS Postgres (pedido) + RDS MySQL (producao), db.t4g.micro
  - DynamoDB (Customers-dev) + Lambda (JWT/Cliente, ${LAMBDA_ARCH}) + API Gateway
  - ECR + IRSA + GitHub OIDC + EKS access entries + add-ons gerenciados
  - AWS Load Balancer Controller (Helm ${LBC_CHART_VERSION}) + StorageClass gp3 + IngressClass alb-jlapp
  - Sem Amazon MQ e sem DocumentDB no dev: RabbitMQ e MongoDB rodam no cluster.

Custo estimado (E, on-demand us-east-1, não medido): ~US\$158/mês, ~US\$5,3/dia
  (T00, ver .prd-implementacoes/2026-11-22-infra-dev-enxuta/PROGRESSO.md).
  O control plane do EKS (~US\$73/mês) é o maior item e é fixo.
  Valor real: Cost Explorer depois de 24 h.

Budget: \$${BUDGET_LIMIT}/mês com alerta em 80%/100%

Próximo passo: ./scripts/deploy-services-dev.sh
IMPORTANTE: quando terminar de testar, rode:
  ./scripts/destroy-dev-fresh-account.sh
pra não deixar recursos cobrando.
EOF
