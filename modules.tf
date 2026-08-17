module "network" {
  source = "./modules/network"

  cluster_name = var.cluster_name
  aws_region   = var.aws_region
}

module "master" {
  source = "./modules/master"

  cluster_name = var.cluster_name
  aws_region   = var.aws_region
  k8s_version  = var.k8s_version

  cluster_vpc       = module.network.cluster_vpc
  private_subnet_1a = module.network.private_subnet_1a
  private_subnet_1c = module.network.private_subnet_1c
}

module "nodes" {
  source = "./modules/nodes"

  cluster_name = var.cluster_name
  aws_region   = var.aws_region
  k8s_version  = var.k8s_version

  cluster_vpc       = module.network.cluster_vpc
  private_subnet_1a = module.network.public_subnet_1a
  private_subnet_1c = module.network.public_subnet_1c

  eks_cluster    = module.master.eks_cluster
  eks_cluster_sg = module.master.security_group
  #  clb_sg         = module.nlb.security_group

  nodes_instances_sizes = var.nodes_instances_sizes
  auto_scale_options    = var.auto_scale_options

  auto_scale_cpu = var.auto_scale_cpu
}

module "rds_pedido" {
  source = "./modules/rds"

  identifier          = "${var.cluster_name}-pedido"
  engine              = "postgres"
  db_name             = "pedido"
  instance_class      = var.rds_instance_class
  multi_az            = var.rds_multi_az
  deletion_protection = var.rds_multi_az

  cluster_vpc        = module.network.cluster_vpc
  private_subnet_ids = [module.network.private_subnet_1a.id, module.network.private_subnet_1c.id]
  eks_sg_id          = module.master.security_group.id
}

module "rds_producao" {
  source = "./modules/rds"

  identifier          = "${var.cluster_name}-producao"
  engine              = "mysql"
  db_name             = "producao"
  instance_class      = var.rds_instance_class
  multi_az            = var.rds_multi_az
  deletion_protection = var.rds_multi_az

  cluster_vpc        = module.network.cluster_vpc
  private_subnet_ids = [module.network.private_subnet_1a.id, module.network.private_subnet_1c.id]
  eks_sg_id          = module.master.security_group.id
}

module "documentdb_pagamento" {
  source = "./modules/documentdb"

  identifier     = "${var.cluster_name}-pagamento"
  instance_class = var.documentdb_instance_class
  instance_count = var.documentdb_instance_count

  cluster_vpc        = module.network.cluster_vpc
  private_subnet_ids = [module.network.private_subnet_1a.id, module.network.private_subnet_1c.id]
  eks_sg_id          = module.master.security_group.id
}

module "mq_shared" {
  source = "./modules/mq"

  identifier      = "${var.cluster_name}-mq"
  instance_type   = var.mq_instance_type
  deployment_mode = var.mq_deployment_mode

  cluster_vpc        = module.network.cluster_vpc
  private_subnet_ids = [module.network.private_subnet_1a.id, module.network.private_subnet_1c.id]
  eks_sg_id          = module.master.security_group.id
}

module "ecr" {
  source = "./modules/ecr"
}

module "github_oidc" {
  source = "./modules/github_oidc"

  github_org = var.github_org

  repos = {
    "pos_tech_fiap_pedido"           = { policy_arns = ["arn:aws:iam::aws:policy/AmazonEKSClusterPolicy", "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"] }
    "pos_tech_fiap_pagamento"        = { policy_arns = ["arn:aws:iam::aws:policy/AmazonEKSClusterPolicy", "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"] }
    "pos_tech_fiap_producao"         = { policy_arns = ["arn:aws:iam::aws:policy/AmazonEKSClusterPolicy", "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"] }
    "pos_tech_fiap_lambda"           = { policy_arns = ["arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser", "arn:aws:iam::aws:policy/AWSLambda_FullAccess"] }
    "pos_tech_fiap_terraform"        = { policy_arns = ["arn:aws:iam::aws:policy/PowerUserAccess"] }
    "pos_tech_fiap_db"               = { policy_arns = ["arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"] }
    "pos_tech_fiap_lambda_terraform" = { policy_arns = ["arn:aws:iam::aws:policy/PowerUserAccess"] }
  }
}

module "irsa_pedido" {
  source = "./modules/irsa"

  service_name      = "pedido"
  oidc_provider_arn = module.master.oidc_provider_arn
  oidc_provider_url = module.master.oidc_provider_url
  secret_arns       = [module.rds_pedido.secret_arn, module.mq_shared.secret_arn]
}

module "irsa_pagamento" {
  source = "./modules/irsa"

  service_name      = "pagamento"
  oidc_provider_arn = module.master.oidc_provider_arn
  oidc_provider_url = module.master.oidc_provider_url
  secret_arns       = [module.documentdb_pagamento.secret_arn, module.mq_shared.secret_arn]
}

module "irsa_producao" {
  source = "./modules/irsa"

  service_name      = "producao"
  oidc_provider_arn = module.master.oidc_provider_arn
  oidc_provider_url = module.master.oidc_provider_url
  secret_arns       = [module.rds_producao.secret_arn, module.mq_shared.secret_arn]
}

#module "nlb" {
# source = "./modules/nlb"

#  private_subnet_1a = module.network.private_subnet_1a
#  private_subnet_1c = module.network.private_subnet_1c
#  cluster_vpc       = module.network.cluster_vpc.id
#  node_group        = module.nodes.node_group_arn
#  cluster_name      = var.cluster_name
#}
