variable "cluster_name" {
  default = "jlapp-cluster"
}

variable "aws_region" {
  default = "us-east-1"
}

variable "k8s_version" {
  default = "1.24"
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

