# IAM da role usada pelo AWS Load Balancer Controller (instalado via Helm no
# script de deploy, fora do Terraform - ver Fase 3 do plano). O controller
# nao existe como EKS managed addon (aws/containers-roadmap#1162 ainda aberto).
#
# Pod Identity, nao IRSA: a association abaixo so precisa do nome do
# namespace/service account, entao e declaravel aqui sem depender do Helm
# ja ter criado a ServiceAccount - IRSA exigiria anotar uma SA que ainda nao
# existe no plan-time deste apply.

resource "aws_iam_policy" "lbc" {
  name   = "${var.cluster_name}-lbc-policy"
  policy = file("${path.module}/iam_policy.json") # vendorizado de v3.5.0/docs/install/iam_policy.json
}

data "aws_iam_policy_document" "lbc_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lbc" {
  name               = "${var.cluster_name}-lbc-role"
  assume_role_policy = data.aws_iam_policy_document.lbc_trust.json
}

resource "aws_iam_role_policy_attachment" "lbc" {
  role       = aws_iam_role.lbc.name
  policy_arn = aws_iam_policy.lbc.arn
}

resource "aws_eks_pod_identity_association" "lbc" {
  cluster_name    = var.cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.lbc.arn
}
