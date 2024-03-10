variable "cluster_name" {
    description = "O nome do cluster"
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

variable "desired_size" {
  description = "O tamanho desejado para o cluster"
  type        = number
}

variable "min_size" {
  description = "O tamanho mínimo para o cluster"
  type        = number
}

variable "max_size" {
  description = "O tamanho máximo para o cluster"
  type        = number
}