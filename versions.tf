# Pin do provider AWS - sem isso, terraform init -upgrade pode trazer
# mudanca de comportamento sem aviso (foi o que aconteceu com o default
# de compute_config/EKS Auto Mode entre versoes do provider).
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
