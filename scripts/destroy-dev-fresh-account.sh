#!/usr/bin/env bash
# Destrói o ambiente dev criado por deploy-dev-fresh-account.sh e
# deploy-services-dev.sh, sem deixar órfão. Ordem:
#   Ingress + LBC (o ALB sai antes da VPC) -> esvazia o ECR ->
#   lambda_terraform -> db -> terraform -> log group da Lambda.
# Essencial rodar depois de testar, pra não deixar recursos cobrando.
#
# Uso:
#   ./scripts/destroy-dev-fresh-account.sh
#   echo destroy | ./scripts/destroy-dev-fresh-account.sh   # sem prompt

set -euo pipefail

# A região default da máquina pode ser sa-east-1; toda a infra é us-east-1.
export AWS_DEFAULT_REGION=us-east-1
REGION="${AWS_DEFAULT_REGION}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_REPO="$(cd "${SCRIPT_DIR}/.." && pwd)"
DB_REPO="$(cd "${TERRAFORM_REPO}/../pos_tech_fiap_db" && pwd)"
LAMBDA_TF_REPO="$(cd "${TERRAFORM_REPO}/../pos_tech_fiap_lambda_terraform" && pwd)"

CLUSTER_NAME="jlapp-cluster-dev"
BUDGET_NAME="jlapp-dev-budget"
LAMBDA_LOG_GROUP="/aws/lambda/jlapp-lambda-cliente-dev"
ECR_REPOS="jlapp-pedido jlapp-pagamento jlapp-producao jlapp-lambda"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
warn() { printf '\n\033[1;33m!! %s\033[0m\n' "$1"; }
die() { printf '\n\033[1;31mERRO: %s\033[0m\n' "$1" >&2; exit 1; }

command -v aws >/dev/null 2>&1 || die "aws cli não encontrado."
command -v terraform >/dev/null 2>&1 || die "terraform não encontrado."
command -v jq >/dev/null 2>&1 || die "jq não encontrado."

CALLER_IDENTITY="$(aws sts get-caller-identity --output json)" || die "Credenciais AWS inválidas."
ACCOUNT_ID="$(echo "${CALLER_IDENTITY}" | jq -r '.Account')"

echo "Account ID: ${ACCOUNT_ID}"
echo ""
echo "Isso vai DESTRUIR todos os recursos dev criados nos 3 repos Terraform"
echo "(VPC, EKS, RDS, DynamoDB, Lambda, ECR, IAM roles)."
echo "O budget ${BUDGET_NAME} é mantido (alerta por e-mail)."
echo ""
read -r -p "Digite 'destroy' pra confirmar: " CONFIRM
[[ "${CONFIRM}" == "destroy" ]] || die "Abortado: texto de confirmação não bateu."

# --- 1. Ingress + AWS Load Balancer Controller -------------------------------
# O ALB é criado pelo LBC, fora do Terraform. Se o cluster e a VPC forem
# destruídos antes, o ALB e os security groups ficam órfãos e travam a VPC.
log "Removendo Ingress e AWS Load Balancer Controller (o ALB tem que sair antes da VPC)"

if command -v kubectl >/dev/null 2>&1 && command -v helm >/dev/null 2>&1 \
  && aws eks update-kubeconfig --region "${REGION}" --name "${CLUSTER_NAME}" >/dev/null 2>&1; then
  kubectl delete ingress --all -n default --wait=true --timeout=300s \
    || warn "Falha ao remover os Ingress (cluster inacessível?). Confira o ALB no console depois."
  helm uninstall aws-load-balancer-controller -n kube-system \
    || warn "helm uninstall falhou ou o release não existe."
  # PVCs (Mongo, gp3) viram volumes EBS que o CSI só apaga com o cluster vivo;
  # sem isso o volume fica órfão depois do destroy.
  kubectl delete statefulset --all -n default --wait=true --timeout=300s \
    || warn "Falha ao remover os StatefulSets."
  kubectl delete pvc --all -n default --wait=true --timeout=300s \
    || warn "Falha ao remover os PVCs: confira volumes EBS órfãos depois."
else
  warn "Cluster ${CLUSTER_NAME} inacessível (ou kubectl/helm ausentes): pulando Ingress e LBC."
fi

# --- 2. Esvaziar o ECR -------------------------------------------------------
# Rede de segurança: o módulo ECR tem force_delete=true, mas state antigo não.
log "Esvaziando os repositórios ECR"

for repo in ${ECR_REPOS}; do
  ids="$(aws ecr list-images --region "${REGION}" --repository-name "${repo}" \
    --query 'imageIds[*]' --output json 2>/dev/null || echo '[]')"
  if [ -z "${ids}" ] || [ "${ids}" = "[]" ]; then
    echo "${repo}: vazio ou inexistente."
  else
    aws ecr batch-delete-image --region "${REGION}" --repository-name "${repo}" \
      --image-ids "${ids}" >/dev/null
    echo "${repo}: imagens removidas."
  fi
done

# --- 3. Destroy pos_tech_fiap_lambda_terraform -------------------------------
log "Destroy: pos_tech_fiap_lambda_terraform"
cd "${LAMBDA_TF_REPO}"
terraform init -input=false -reconfigure
terraform destroy -var-file=envs/dev.tfvars -auto-approve

# --- 4. Destroy pos_tech_fiap_db ---------------------------------------------
log "Destroy: pos_tech_fiap_db"
cd "${DB_REPO}"
terraform init -input=false -reconfigure
terraform destroy -var-file=envs/dev.tfvars -auto-approve

# --- 5. Destroy pos_tech_fiap_terraform --------------------------------------
log "Destroy: pos_tech_fiap_terraform"
cd "${TERRAFORM_REPO}"
terraform init -input=false -reconfigure
terraform destroy -var-file=envs/dev.tfvars -auto-approve

# --- 6. Órfãos fora do Terraform ----------------------------------------------
log "Removendo log group da Lambda"

# A Lambda cria o log group na 1ª invocação; sem log group no Terraform ele sobra.
aws logs delete-log-group --region "${REGION}" --log-group-name "${LAMBDA_LOG_GROUP}" 2>/dev/null \
  || echo "Log group ${LAMBDA_LOG_GROUP} não existe, ok."

# --- 7. Limpeza local -----------------------------------------------------------
rm -f "${SCRIPT_DIR}/outputs-dev.json"

log "Destroy concluído: todos os recursos dev foram removidos."
echo "Confira o Cost Explorer nas próximas 24 h pra confirmar que não sobrou nada"
echo "cobrando (EIPs órfãos, snapshots, etc)."
