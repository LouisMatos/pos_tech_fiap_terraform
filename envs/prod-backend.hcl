# terraform init -backend-config=envs/prod-backend.hcl
bucket         = "postechfiap-tfstate-<account-id>"
key            = "pos_tech_fiap_terraform/prod/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "postechfiap-tfstate-lock"
encrypt        = true
