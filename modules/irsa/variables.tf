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
