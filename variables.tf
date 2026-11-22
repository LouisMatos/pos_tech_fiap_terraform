variable "cluster_name" {
  default = "jlapp-cluster"
}

variable "aws_region" {
  default = "us-east-1"
}

variable "nat_type" {
  description = "gateway (NAT Gateway gerenciado, ~$32-35/mes, HA) ou instance (EC2 t3.micro, ~$3-4/mes, sem HA - so dev/teste)"
  default     = "gateway"
}

variable "k8s_version" {
  # CONFIRME a versao atual em standard support antes de aplicar:
  # aws eks describe-cluster-versions --output table
  # 1.24 estava fora de standard support e cairia em extended support
  # (+$0.60/h/cluster, ~+$438/mes) - nao aplicar sem checar.
  default = "1.31"
}

variable "nodes_instances_sizes" {
  default = [
    "t3.large"
  ]
}

variable "auto_scale_options" {
  default = {
    min     = 1
    max     = 1
    desired = 1
  }
}

variable "github_org" {
  description = "Organizacao/usuario dono dos repos no GitHub, usado pelo trust policy do OIDC"
  type        = string
}

variable "rds_instance_class" {
  default = "db.t4g.micro"
}

variable "rds_multi_az" {
  default = false
}

variable "documentdb_instance_class" {
  default = "db.t3.medium"
}

variable "documentdb_instance_count" {
  default = 1
}

variable "mq_instance_type" {
  default = "mq.t3.micro"
}

variable "mq_deployment_mode" {
  default = "SINGLE_INSTANCE"
}

variable "auto_scale_cpu" {
  default = {
    scale_up_threshold  = 80
    scale_up_period     = 60
    scale_up_evaluation = 2
    scale_up_cooldown   = 300
    scale_up_add        = 2

    scale_down_threshold  = 40
    scale_down_period     = 120
    scale_down_evaluation = 2
    scale_down_cooldown   = 300
    scale_down_remove     = -1
  }
}


variable "enable_mq" {
  description = "Cria o Amazon MQ. No dev e false: o RabbitMQ roda em StatefulSet (k8s-bootstrap/dev/rabbitmq.yaml)."
  type        = bool
  default     = true
}

variable "enable_documentdb" {
  description = "Cria o DocumentDB. No dev e false: o Free Plan bloqueia, o pagamento usa Mongo em StatefulSet."
  type        = bool
  default     = true
}

variable "operator_principal_arns" {
  description = "ARNs de IAM users/roles que ganham acesso de admin ao cluster EKS (access entries)"
  type        = list(string)
  default     = []
}

variable "node_azs_single" {
  description = "true: node group so em private_subnet_1a (mesma AZ das RDS). So dev; sem HA de AZ."
  type        = bool
  default     = false
}

variable "node_ami_type" {
  description = "AMI type do node group. AL2023_ARM_64_STANDARD para instancias t4g."
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "coredns_replicas" {
  description = "Replicas do CoreDNS"
  type        = number
  default     = 2
}
