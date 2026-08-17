output "eks_cluster" {
  value = aws_eks_cluster.eks_cluster
}

output "security_group" {
  value = aws_security_group.cluster_master_sg
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.eks_oidc.arn
}

output "oidc_provider_url" {
  value = aws_iam_openid_connect_provider.eks_oidc.url
}
