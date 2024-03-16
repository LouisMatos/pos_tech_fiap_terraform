variable "cluster_name" {
    description = "O nome do cluster"
    
}

variable "private_subnet_1a" {
    description = "A subnet privada 1a"
    
}

variable "private_subnet_1c" {
    description = "A subnet privada 1c"
    
}

variable "aws_region" {
    description = "A região da AWS"
    
}

variable "k8s_version" {
    description = "A versão do Kubernetes"
    
}

variable "cluster_vpc" {
    description = "A VPC do cluster"
}


variable "eks_cluster" {
    description = "O nome do cluster"
    
}

variable "eks_cluster_sg" {
    description = "O security group do cluster"
    
}

variable "nodes_instances_sizes" {
    description = "O tamanho das instâncias dos nodes"
    type        = list(string)
}

variable "auto_scale_options" { 
    description = "Opções de auto scale"
    type        = map
} 

variable "auto_scale_cpu" {
    description = "Auto scale por CPU"
    type        = map
}