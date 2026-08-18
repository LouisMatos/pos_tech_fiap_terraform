variable "identifier" {
  type = string
}

variable "instance_class" {
  type    = string
  default = "db.t3.medium"
}

variable "instance_count" {
  type    = number
  default = 1
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
