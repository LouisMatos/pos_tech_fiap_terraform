# Network outputs
output "vpc_id" {
  description = "VPC ID do cluster EKS"
  value       = module.network.cluster_vpc.id
}

output "vpc_cidr" {
  description = "CIDR block do VPC"
  value       = module.network.cluster_vpc.cidr_block
}

output "private_subnet_1a_id" {
  description = "ID da subnet privada 1a"
  value       = module.network.private_subnet_1a.id
}

output "private_subnet_1c_id" {
  description = "ID da subnet privada 1c"
  value       = module.network.private_subnet_1c.id
}

output "public_subnet_1a_id" {
  description = "ID da subnet pública 1a"
  value       = module.network.public_subnet_1a.id
}

output "public_subnet_1c_id" {
  description = "ID da subnet pública 1c"
  value       = module.network.public_subnet_1c.id
}

# EKS Cluster outputs
output "eks_cluster_name" {
  description = "Nome do cluster EKS"
  value       = module.master.eks_cluster.name
}

output "eks_cluster_endpoint" {
  description = "Endpoint do EKS control plane"
  value       = module.master.eks_cluster.endpoint
}

output "eks_cluster_sg_id" {
  description = "Security Group ID do cluster EKS"
  value       = module.master.security_group.id
}

# IRSA role outputs (pra injetar nos GitHub secrets PEDIDO_IRSA_ROLE_ARN, etc)
output "irsa_pedido_role_arn" {
  description = "ARN da IRSA role pra serviço pedido"
  value       = module.irsa_pedido.role_arn
}

output "irsa_pagamento_role_arn" {
  description = "ARN da IRSA role pra serviço pagamento"
  value       = module.irsa_pagamento.role_arn
}

output "irsa_producao_role_arn" {
  description = "ARN da IRSA role pra serviço producao"
  value       = module.irsa_producao.role_arn
}

# Database outputs
output "rds_pedido_endpoint" {
  description = "Endpoint do RDS Postgres pra pedido (host:port)"
  value       = "${module.rds_pedido.endpoint}:${module.rds_pedido.port}"
}

output "rds_pedido_db_name" {
  description = "Database name do RDS pedido"
  value       = module.rds_pedido.db_name
}

output "rds_pedido_secret_arn" {
  description = "ARN do secret AWS Secrets Manager pra RDS pedido"
  value       = module.rds_pedido.secret_arn
}

output "rds_producao_endpoint" {
  description = "Endpoint do RDS MySQL pra producao (host:port)"
  value       = "${module.rds_producao.endpoint}:${module.rds_producao.port}"
}

output "rds_producao_db_name" {
  description = "Database name do RDS producao"
  value       = module.rds_producao.db_name
}

output "rds_producao_secret_arn" {
  description = "ARN do secret AWS Secrets Manager pra RDS producao"
  value       = module.rds_producao.secret_arn
}

output "documentdb_pagamento_endpoint" {
  description = "Endpoint do DocumentDB pra pagamento (host:port)"
  value       = "${module.documentdb_pagamento.endpoint}:${module.documentdb_pagamento.port}"
}

output "documentdb_pagamento_secret_arn" {
  description = "ARN do secret AWS Secrets Manager pra DocumentDB pagamento"
  value       = module.documentdb_pagamento.secret_arn
}

# Message broker outputs
output "mq_shared_secret_arn" {
  description = "ARN do secret AWS Secrets Manager pra Amazon MQ"
  value       = module.mq_shared.secret_arn
}

# ECR repository URLs
output "ecr_repository_urls" {
  description = "URLs de todos os repositórios ECR (mapa: jlapp-pedido, jlapp-pagamento, jlapp-producao, jlapp-monolith)"
  value       = module.ecr.repository_urls
}
