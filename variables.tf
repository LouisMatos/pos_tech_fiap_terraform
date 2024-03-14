
variable "cluster_name" {
  default     = "jlapp-cluster"
  description = "O nome do cluster"
  type        = string
}

variable "desired_size" {
  default     = 1
  description = "O tamanho desejado para o cluster"
  type        = number
}

variable "min_size" {
  default     = 1
  description = "O tamanho mínimo para o cluster"
  type        = number
}

variable "max_size" {
  default     = 2
  description = "O tamanho máximo para o cluster"
  type        = number
}

variable "kubernetes_version" {
  default     = "1.24"
  description = "A versão do Kubernetes"
  type        = string
}
