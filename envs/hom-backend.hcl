# terraform init -backend-config=envs/hom-backend.hcl
# Bucket/tabela criados pelo bootstrap/ (aplicado manualmente uma unica vez).
bucket         = "postechfiap-tfstate-<account-id>"
key            = "pos_tech_fiap_terraform/hom/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "postechfiap-tfstate-lock"
encrypt        = true
