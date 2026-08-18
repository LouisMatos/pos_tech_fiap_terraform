variable "identifier" {
  type = string
}

variable "engine" {
  type        = string
  description = "postgres ou mysql"
}

variable "engine_version" {
  type    = string
  default = null
}

variable "instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "multi_az" {
  type    = bool
  default = false
}

variable "deletion_protection" {
  type    = bool
  default = false
}

variable "db_name" {
  type = string
}

variable "username" {
  type    = string
  default = "app_admin"
}

variable "cluster_vpc" {
  description = "objeto aws_vpc do modulo network"
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "eks_sg_id" {
  description = "security group compartilhado pelo control plane/nodes EKS - unica origem de ingress permitida"
  type        = string
}
