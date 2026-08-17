# Backend local por padrão (gratis). Para hom/prod, sobrescrever em tempo de init:
#   terraform init -backend-config=envs/hom-backend.hcl
#   terraform init -backend-config=envs/prod-backend.hcl
# Terraform nao aceita variaveis dentro do bloco backend, entao a selecao de
# ambiente acontece via flag -backend-config, nao por logica condicional aqui.
terraform {
  backend "local" {
    path = "state/terraform.tfstate"
  }
}
