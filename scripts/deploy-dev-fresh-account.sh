#!/usr/bin/env bash
# Bootstrap + deploy do ambiente dev numa conta AWS nova, gastando o mínimo.
#
# Roda os 3 repos Terraform em sequência, sempre com state LOCAL (dev nunca
# usa o backend S3 compartilhado — esse é só pra hom/prod). Pré-requisito:
# as PRs de segurança/outputs (#17, #18 em pos_tech_fiap_terraform) precisam
# estar merged em develop antes de rodar isso, senão a infra sobe com o
# security group aberto pro mundo e/ou os outputs não existem.
#
# Uso:
#   ./scripts/deploy-dev-fresh-account.sh [teto_mensal_usd]
#
# Exemplo:
#   ./scripts/deploy-dev-fresh-account.sh 50

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_REPO="$(cd "${SCRIPT_DIR}/.." && pwd)"
DB_REPO="$(cd "${TERRAFORM_REPO}/../pos_tech_fiap_db" && pwd)"
LAMBDA_TF_REPO="$(cd "${TERRAFORM_REPO}/../pos_tech_fiap_lambda_terraform" && pwd)"

BUDGET_LIMIT="${1:-50}"
OUTPUTS_FILE="${SCRIPT_DIR}/outputs-dev.json"
NOTIFICATION_EMAIL="${AWS_BUDGET_EMAIL:-}"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
warn() { printf '\n\033[1;33m!! %s\033[0m\n' "$1"; }
die() { printf '\n\033[1;31mERRO: %s\033[0m\n' "$1" >&2; exit 1; }

# --- 1. Preflight -----------------------------------------------------------
log "Preflight: verificando AWS CLI e credenciais"

command -v aws >/dev/null 2>&1 || die "aws cli não encontrado. Instale antes de continuar."
command -v terraform >/dev/null 2>&1 || die "terraform não encontrado. Instale antes de continuar."
command -v jq >/dev/null 2>&1 || die "jq não encontrado (usado pra consolidar outputs). Instale antes de continuar."

CALLER_IDENTITY="$(aws sts get-caller-identity --output json)" || die "Credenciais AWS inválidas ou não configuradas. Rode 'aws configure' primeiro."
ACCOUNT_ID="$(echo "${CALLER_IDENTITY}" | jq -r '.Account')"
CALLER_ARN="$(echo "${CALLER_IDENTITY}" | jq -r '.Arn')"

echo "Account ID : ${ACCOUNT_ID}"
echo "Caller     : ${CALLER_ARN}"
echo ""
read -r -p "Confirma que essa é a conta AWS NOVA de teste que você quer usar? [y/N] " CONFIRM
[[ "${CONFIRM}" == "y" || "${CONFIRM}" == "Y" ]] || die "Abortado pelo usuário."

# --- 2. AWS Budget com alerta -------------------------------------------------
log "Criando AWS Budget (guardrail de custo, teto \$${BUDGET_LIMIT}/mês)"

if [ -z "${NOTIFICATION_EMAIL}" ]; then
  read -r -p "E-mail pra receber alerta de orçamento: " NOTIFICATION_EMAIL
fi

BUDGET_NAME="jlapp-dev-budget"

if aws budgets describe-budget --account-id "${ACCOUNT_ID}" --budget-name "${BUDGET_NAME}" >/dev/null 2>&1; then
  echo "Budget '${BUDGET_NAME}' já existe, pulando criação."
else
  aws budgets create-budget \
    --account-id "${ACCOUNT_ID}" \
    --budget "$(jq -n --arg limit "${BUDGET_LIMIT}" '{
      BudgetName: "jlapp-dev-budget",
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
    || warn "Falha ao criar budget — continue manualmente pelo console se necessário."
  echo "Budget criado: alerta em 80% e 100% de \$${BUDGET_LIMIT}/mês pra ${NOTIFICATION_EMAIL}"
fi

# --- 3. Deploy pos_tech_fiap_terraform ---------------------------------------
log "Deploy: pos_tech_fiap_terraform (VPC, EKS, RDS, DocumentDB, MQ, ECR, IRSA)"

cd "${TERRAFORM_REPO}"
terraform init -input=false
terraform apply -var-file=envs/dev.tfvars -auto-approve
terraform output -json > "${SCRIPT_DIR}/.terraform-outputs.json"

# --- 4. Deploy pos_tech_fiap_db ----------------------------------------------
log "Deploy: pos_tech_fiap_db (DynamoDB Customers)"

cd "${DB_REPO}"
terraform init -input=false
terraform apply -var-file=envs/dev.tfvars -auto-approve
terraform output -json > "${SCRIPT_DIR}/.db-outputs.json"

# --- 5. Deploy pos_tech_fiap_lambda_terraform --------------------------------
log "Deploy: pos_tech_fiap_lambda_terraform (Lambda JWT/Cliente, API Gateway)"

cd "${LAMBDA_TF_REPO}"
terraform init -input=false
terraform apply -var-file=envs/dev.tfvars -auto-approve
terraform output -json > "${SCRIPT_DIR}/.lambda-outputs.json"

# --- 6. Consolidar outputs ----------------------------------------------------
log "Consolidando outputs em ${OUTPUTS_FILE}"

jq -s '{
  terraform: .[0],
  db: .[1],
  lambda_terraform: .[2]
}' \
  "${SCRIPT_DIR}/.terraform-outputs.json" \
  "${SCRIPT_DIR}/.db-outputs.json" \
  "${SCRIPT_DIR}/.lambda-outputs.json" \
  > "${OUTPUTS_FILE}"

rm -f "${SCRIPT_DIR}/.terraform-outputs.json" "${SCRIPT_DIR}/.db-outputs.json" "${SCRIPT_DIR}/.lambda-outputs.json"

# --- 7. Comandos gh secret set prontos ----------------------------------------
log "Comandos pra wire CI depois (copie/cole o que precisar, não executados automaticamente)"

IRSA_PEDIDO="$(jq -r '.terraform.irsa_pedido_role_arn.value // empty' "${OUTPUTS_FILE}")"
IRSA_PAGAMENTO="$(jq -r '.terraform.irsa_pagamento_role_arn.value // empty' "${OUTPUTS_FILE}")"
IRSA_PRODUCAO="$(jq -r '.terraform.irsa_producao_role_arn.value // empty' "${OUTPUTS_FILE}")"

cat <<EOF

# --- pos_tech_fiap_pedido ---
gh secret set AWS_ACCOUNT_ID --body "${ACCOUNT_ID}" --repo LouisMatos/pos_tech_fiap_pedido
gh secret set AWS_REGION --body "us-east-1" --repo LouisMatos/pos_tech_fiap_pedido
gh secret set PEDIDO_IRSA_ROLE_ARN --body "${IRSA_PEDIDO}" --repo LouisMatos/pos_tech_fiap_pedido

# --- pos_tech_fiap_pagamento ---
gh secret set AWS_ACCOUNT_ID --body "${ACCOUNT_ID}" --repo LouisMatos/pos_tech_fiap_pagamento
gh secret set AWS_REGION --body "us-east-1" --repo LouisMatos/pos_tech_fiap_pagamento
gh secret set PAGAMENTO_IRSA_ROLE_ARN --body "${IRSA_PAGAMENTO}" --repo LouisMatos/pos_tech_fiap_pagamento

# --- pos_tech_fiap_producao ---
gh secret set AWS_ACCOUNT_ID --body "${ACCOUNT_ID}" --repo LouisMatos/pos_tech_fiap_producao
gh secret set AWS_REGION --body "us-east-1" --repo LouisMatos/pos_tech_fiap_producao
gh secret set PRODUCAO_IRSA_ROLE_ARN --body "${IRSA_PRODUCAO}" --repo LouisMatos/pos_tech_fiap_producao

EOF

# --- 8. Resumo final -----------------------------------------------------------
log "Deploy concluído"

cat <<EOF
Outputs consolidados em: ${OUTPUTS_FILE}

Recursos criados:
  - VPC + subnets + NAT (instance, cost-optimized)
  - EKS cluster (jlapp-cluster-dev) + node group (t3.small x1)
  - RDS Postgres (pedido) + RDS MySQL (producao) — db.t4g.micro
  - DocumentDB (pagamento) — db.t4g.medium
  - Amazon MQ (RabbitMQ compartilhado) — mq.t3.micro
  - DynamoDB (Customers-dev)
  - Lambda (JWT/Cliente) + API Gateway
  - ECR repositories + IRSA roles + GitHub OIDC provider

Estimativa de custo mensal: ~\$95-110/mês
  (EKS control plane ~\$73 fixo + node ~\$15 + RDS/DocDB/MQ/NAT ~\$25-30
   com as otimizações aplicadas — ver documentação HTML pro detalhamento
   completo por recurso)

Budget configurado: \$${BUDGET_LIMIT}/mês com alerta em 80%/100%

IMPORTANTE: quando terminar de testar, rode:
  ./scripts/destroy-dev-fresh-account.sh
pra não deixar recursos cobrando.
EOF
