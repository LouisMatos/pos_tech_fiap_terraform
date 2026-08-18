variable "github_org" {
  description = "Organizacao/usuario dono dos repos no GitHub"
  type        = string
}

variable "repos" {
  description = "Mapa nome-do-repo => permissoes IAM necessarias para o workflow (lista de policy ARNs gerenciadas ou inline - aqui usamos policy ARNs gerenciadas por simplicidade)"
  type = map(object({
    policy_arns = list(string)
  }))
}
