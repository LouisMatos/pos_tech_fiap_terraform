# EKS managed add-ons. Antes desta fase o repo nao tinha nenhum aws_eks_addon:
# vpc-cni/coredns/kube-proxy ficavam nos defaults automaticos do EKS, sem
# versao pinada e sem controle de drift.

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = module.master.eks_cluster.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = module.master.eks_cluster.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name                = module.master.eks_cluster.name
  addon_name                  = "eks-pod-identity-agent"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

# coredns, aws-ebs-csi-driver e metrics-server precisam de node pra agendar -
# so depois do node group existir.

resource "aws_eks_addon" "coredns" {
  cluster_name                = module.master.eks_cluster.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [module.nodes]
}

resource "aws_eks_addon" "metrics_server" {
  cluster_name                = module.master.eks_cluster.name
  addon_name                  = "metrics-server"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [module.nodes]
}

# --- aws-ebs-csi-driver: precisa de IAM propria via Pod Identity ---

data "aws_iam_policy_document" "ebs_csi_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.cluster_name}-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_trust.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_pod_identity_association" "ebs_csi" {
  cluster_name    = module.master.eks_cluster.name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi.arn
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = module.master.eks_cluster.name
  addon_name                  = "aws-ebs-csi-driver"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # A associacao pod-identity do ebs-csi-controller-sa e gerida pelo recurso
  # standalone aws_eks_pod_identity_association.ebs_csi acima. Declarar tambem
  # o bloco inline aqui faz o EKS tentar criar uma segunda associacao pro
  # mesmo SA -> ResourceInUseException (Association already exists).
  depends_on = [module.nodes, aws_eks_pod_identity_association.ebs_csi]
}

# --- AWS Load Balancer Controller: so IAM aqui, o Helm roda no script (Fase 3) ---

module "lbc" {
  source = "./modules/lbc"

  cluster_name = module.master.eks_cluster.name

  depends_on = [aws_eks_addon.pod_identity_agent]
}
