variable "identifier" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "mq.t3.micro"
}

variable "deployment_mode" {
  type    = string
  default = "SINGLE_INSTANCE"
}

variable "engine_version" {
  type    = string
  default = "3.13"
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
  type = string
}
