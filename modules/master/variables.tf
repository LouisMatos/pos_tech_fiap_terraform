variable "cluster_name" {
     description = "O nome do cluster"
  type        = string
}

variable "kubernetes_version" {
    description = "A versão do Kubernetes"
    type        = string
}

variable "private_subnet_1a" {
    description = "A subnet privada 1a"
    type        = string
}

variable "private_subnet_1b" {
    description = "A subnet privada 1b"
    type        = string
}