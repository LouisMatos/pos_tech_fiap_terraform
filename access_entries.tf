# As roles github-actions-* (modules/github_oidc) tem permissao IAM pra
# "eks:DescribeCluster" (via AmazonEKSClusterPolicy), o que basta pro
# `aws eks update-kubeconfig` funcionar. Mas sem access entry o `kubectl`
# do workflow retorna Unauthorized - autenticacao IAM != autorizacao RBAC.

locals {
  service_repos = [
    "pos_tech_fiap_pedido",
    "pos_tech_fiap_pagamento",
    "pos_tech_fiap_producao",
  ]
}

resource "aws_eks_access_entry" "service_repos" {
  for_each      = toset(local.service_repos)
  cluster_name  = module.master.eks_cluster.name
  principal_arn = module.github_oidc.role_arns[each.key]
}

resource "aws_eks_access_policy_association" "service_repos_edit" {
  for_each      = toset(local.service_repos)
  cluster_name  = module.master.eks_cluster.name
  principal_arn = module.github_oidc.role_arns[each.key]
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  access_scope {
    type = "cluster"
  }
}

# Operador local (deploy-dev-fresh-account.sh roda kubectl/helm como esse
# principal). O EKS nao concede admin automatico pro criador quando access_config
# e explicito, entao a entry precisa ser declarada.
resource "aws_eks_access_entry" "operators" {
  for_each      = toset(var.operator_principal_arns)
  cluster_name  = module.master.eks_cluster.name
  principal_arn = each.value
}

resource "aws_eks_access_policy_association" "operators_admin" {
  for_each      = toset(var.operator_principal_arns)
  cluster_name  = module.master.eks_cluster.name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.operators]
}

resource "aws_eks_access_entry" "terraform_repo" {
  cluster_name  = module.master.eks_cluster.name
  principal_arn = module.github_oidc.role_arns["pos_tech_fiap_terraform"]
}

resource "aws_eks_access_policy_association" "terraform_repo_admin" {
  cluster_name  = module.master.eks_cluster.name
  principal_arn = module.github_oidc.role_arns["pos_tech_fiap_terraform"]
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}
