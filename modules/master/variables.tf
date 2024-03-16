variable "aws_region" {
    description = "A região da AWS"
    
}

variable "cluster_name" {
    description = "O nome do cluster"
    
}

variable "k8s_version" {
    description = "A versão do Kubernetes"
    
}

variable "cluster_vpc" {
    description = "A VPC do cluster"
}

variable "private_subnet_1a" {
    description = "A subnet privada 1a"
}

variable "private_subnet_1c" {
    description = "A subnet privada 1c"
}