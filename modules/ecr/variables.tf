variable "repository_names" {
  description = "Lista de nomes de repositorio ECR a criar, um por servico"
  type        = list(string)
  default     = ["jlapp-pedido", "jlapp-pagamento", "jlapp-producao", "jlapp-lambda"]
}

variable "untagged_expire_days" {
  type    = number
  default = 7
}

variable "keep_last_tagged" {
  type    = number
  default = 10
}
