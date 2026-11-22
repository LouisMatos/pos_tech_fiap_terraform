variable "cluster_name" {}

variable "aws_region" {}

variable "nat_type" {
  description = "gateway (NAT Gateway gerenciado, ~$32-35/mes, HA) ou instance (EC2 t3.micro fazendo NAT, ~$3-4/mes, sem HA gerenciada - usar so em dev/teste)"
  type        = string
  default     = "gateway"

  validation {
    condition     = contains(["gateway", "instance"], var.nat_type)
    error_message = "nat_type deve ser \"gateway\" ou \"instance\"."
  }
}

