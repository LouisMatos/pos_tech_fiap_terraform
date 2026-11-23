variable "service_name" {
  description = "Nome do servico (pedido, pagamento, producao) - usado para nomear a role e o service account esperado"
  type        = string
}

variable "namespace" {
  type    = string
  default = "default"
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider_url" {
  description = "URL do issuer OIDC do cluster, sem o https://"
  type        = string
}

variable "secret_arns" {
  description = "ARNs dos secrets do Secrets Manager que este servico pode ler (DB, MQ)"
  type        = list(string)
}

# Policy IAM exige ao menos um Resource: sem secrets (ex.: pagamento no dev, sem
# DocumentDB nem Amazon MQ) a policy nao e criada. Bool conhecido no plan, porque
# o tamanho de secret_arns pode ser desconhecido ate o apply.
variable "enable_secrets_access" {
  type    = bool
  default = true
}
