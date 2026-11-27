resource "aws_eks_cluster" "eks_cluster" {

  name     = var.cluster_name
  version  = var.k8s_version
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {

    security_group_ids = [
      aws_security_group.cluster_master_sg.id
    ]

    subnet_ids = [
      var.private_subnet_1a.id,
      var.private_subnet_1c.id
    ]

  }

  # Explicito: sem isso a API do EKS tenta habilitar Auto Mode por
  # default, que exige k8s >= 1.29 e usa um modelo de compute diferente
  # do managed node group provisionado em modules/nodes.
  compute_config {
    enabled = false
  }

  # access_entries.tf (operadores e roles do GitHub Actions) exige modo API.
  # Correção do deploy de ago/2026 que tinha se perdido (gotcha 4).
  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
    # ForceNew: precisa casar com o valor de criação (true), senão recria o cluster.
    bootstrap_cluster_creator_admin_permissions = true
  }

  tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

}
