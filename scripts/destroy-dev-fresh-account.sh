#!/usr/bin/env bash
# Destrói o ambiente dev criado por deploy-dev-fresh-account.sh, em ordem
# reversa (lambda_terraform → db → terraform). Essencial rodar depois de
# testar, pra não deixar recursos cobrando na conta.
#
# Uso:
#   ./scripts/destroy-dev-fresh-account.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_REPO="$(cd "${SCRIPT_DIR}/.." && pwd)"
DB_REPO="$(cd "${TERRAFORM_REPO}/../pos_tech_fiap_db" && pwd)"
LAMBDA_TF_REPO="$(cd "${TERRAFORM_REPO}/../pos_tech_fiap_lambda_terraform" && pwd)"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
die() { printf '\n\033[1;31mERRO: %s\033[0m\n' "$1" >&2; exit 1; }

command -v aws >/dev/null 2>&1 || die "aws cli não encontrado."
command -v terraform >/dev/null 2>&1 || die "terraform não encontrado."

CALLER_IDENTITY="$(aws sts get-caller-identity --output json)" || die "Credenciais AWS inválidas."
ACCOUNT_ID="$(echo "${CALLER_IDENTITY}" | python3 -c "import json,sys; print(json.load(sys.stdin)['Account'])")"

echo "Account ID: ${ACCOUNT_ID}"
echo ""
echo "Isso vai DESTRUIR todos os recursos dev criados nos 3 repos Terraform"
echo "(VPC, EKS, RDS, DocumentDB, MQ, DynamoDB, Lambda, ECR, IAM roles)."
echo ""
read -r -p "Digite 'destroy' pra confirmar: " CONFIRM
[[ "${CONFIRM}" == "destroy" ]] || die "Abortado — texto de confirmação não bateu."

# --- 1. Destroy pos_tech_fiap_lambda_terraform -------------------------------
log "Destroy: pos_tech_fiap_lambda_terraform"
cd "${LAMBDA_TF_REPO}"
terraform init -input=false -reconfigure
terraform destroy -var-file=envs/dev.tfvars -auto-approve

# --- 2. Destroy pos_tech_fiap_db --------------------------------------------
log "Destroy: pos_tech_fiap_db"
cd "${DB_REPO}"
terraform init -input=false -reconfigure
terraform destroy -var-file=envs/dev.tfvars -auto-approve

# --- 3. Destroy pos_tech_fiap_terraform --------------------------------------
log "Destroy: pos_tech_fiap_terraform"
cd "${TERRAFORM_REPO}"
terraform init -input=false -reconfigure
terraform destroy -var-file=envs/dev.tfvars -auto-approve

# --- 4. Limpeza local ----------------------------------------------------------
rm -f "${SCRIPT_DIR}/outputs-dev.json"

log "Destroy concluído — todos os recursos dev foram removidos."
echo "Confira o console AWS Cost Explorer nas próximas 24h pra confirmar que"
echo "não sobrou nada cobrando (EIPs órfãos, snapshots, etc)."
