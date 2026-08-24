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

# Se qualquer coisa falhar depois daqui, mostra o que já subiu (e pode estar
# cobrando) em vez de só abortar silenciosamente — evita ficar sem saber o
# que ficou pra trás numa falha no meio do deploy.
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
  echo "Corrija o problema e rode o script de novo — é idempotente, retoma do"
  echo "state local sem recriar o que já subiu. Ou rode"
  echo "./destroy-dev-fresh-account.sh se não for tentar de novo agora."
}
trap on_error ERR

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
warn "Contas AWS novas às vezes entram num 'Free Plan' restrito que bloqueia"
echo "DocumentDB (só libera Aurora PostgreSQL). Se o apply falhar com"
echo "FreeTierRestrictionError, é isso — resolve no Console AWS → Billing,"
echo "não é bug de código. Terraform continua o resto normalmente."
echo ""
read -r -p "Confirma que essa é a conta AWS NOVA de teste que você quer usar? [y/N] " CONFIRM
[[ "${CONFIRM}" == "y" || "${CONFIRM}" == "Y" ]] || die "Abortado pelo usuário."

# --- 1.5 Checar versão do EKS ANTES de criar qualquer recurso pago ----------
log "Checando se o k8s_version configurado está em standard support"

K8S_VERSION="$(grep -E '^\s*k8s_version' "${TERRAFORM_REPO}/envs/dev.tfvars" | sed -E 's/.*=\s*"([^"]+)".*/\1/')"
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
  echo "Rode manualmente: aws eks describe-cluster-versions --output table"
  echo "k8s_version atual: ${K8S_VERSION} — confirme que está STANDARD_SUPPORT antes de continuar."
  echo "Fora disso entra em extended support: +\$0.60/h/cluster (~+\$438/mês)."
  read -r -p "Já conferiu e está OK? [y/N] " K8S_CONFIRM
  [[ "${K8S_CONFIRM}" == "y" || "${K8S_CONFIRM}" == "Y" ]] || die "Abortado — confirme a versão do EKS antes de rodar."
fi

# --- 1.6 Checar tipo de instância/engine do Amazon MQ ANTES de aplicar ------
log "Checando se mq_instance_type é válido pra engine RabbitMQ"

MQ_INSTANCE_TYPE="$(grep -E '^\s*mq_instance_type' "${TERRAFORM_REPO}/envs/dev.tfvars" | sed -E 's/.*=\s*"([^"]+)".*/\1/')"
MQ_ENGINE_VERSION="$(grep -A2 'variable "engine_version"' "${TERRAFORM_REPO}/modules/mq/variables.tf" | grep default | sed -E 's/.*=\s*"([^"]+)".*/\1/')"
MQ_OPTIONS_TMP="$(mktemp)"

if aws mq describe-broker-instance-options --engine-type RABBITMQ --output json >"${MQ_OPTIONS_TMP}" 2>/dev/null; then
  VALID="$(jq -r --arg t "${MQ_INSTANCE_TYPE}" --arg v "${MQ_ENGINE_VERSION}" \
    '.BrokerInstanceOptions[]? | select(.HostInstanceType == $t) | .SupportedEngineVersions[]? | select(. == $v)' \
    "${MQ_OPTIONS_TMP}")"
  if [ -z "${VALID}" ]; then
    warn "mq_instance_type=${MQ_INSTANCE_TYPE} não suporta engine RabbitMQ ${MQ_ENGINE_VERSION} nesta conta/região."
    echo "Combinações válidas de HostInstanceType x SupportedEngineVersions pra RABBITMQ:"
    jq -r '.BrokerInstanceOptions[]? | "\(.HostInstanceType): \(.SupportedEngineVersions | join(", "))"' "${MQ_OPTIONS_TMP}"
    rm -f "${MQ_OPTIONS_TMP}"
    die "Atualize mq_instance_type em envs/dev.tfvars (ou engine_version em modules/mq/variables.tf) pra uma combinação da lista acima antes de continuar."
  fi
  rm -f "${MQ_OPTIONS_TMP}"
  echo "mq_instance_type=${MQ_INSTANCE_TYPE} + engine ${MQ_ENGINE_VERSION}: OK."
else
  rm -f "${MQ_OPTIONS_TMP}"
  warn "Não deu pra checar automaticamente (aws-cli sem 'describe-broker-instance-options' ou sem permissão)."
  echo "Rode manualmente: aws mq describe-broker-instance-options --engine-type RABBITMQ"
  read -r -p "Já conferiu que mq_instance_type=${MQ_INSTANCE_TYPE} é válido pra engine ${MQ_ENGINE_VERSION}? [y/N] " MQ_CONFIRM
  [[ "${MQ_CONFIRM}" == "y" || "${MQ_CONFIRM}" == "Y" ]] || die "Abortado — confirme o tipo de instância do MQ antes de rodar."
fi

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

Estimativa de custo mensal: ~\$140-160/mês (primeiros 12 meses, free tier
  aplicado onde elegível — EKS control plane ~\$73 fixo é o maior item,
  sem free tier possível. Ver documentação HTML pro detalhamento completo
  por recurso e o que muda depois que o free tier expira.)

Budget configurado: \$${BUDGET_LIMIT}/mês com alerta em 80%/100%

IMPORTANTE: quando terminar de testar, rode:
  ./scripts/destroy-dev-fresh-account.sh
pra não deixar recursos cobrando.
EOF
