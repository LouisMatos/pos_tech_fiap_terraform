resource "aws_security_group" "cluster_master_sg" {

  name   = format("%s-master-sg", var.cluster_name)
  vpc_id = var.cluster_vpc.id

  egress {
    from_port = 0
    to_port   = 0

    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = format("%s-master-sg", var.cluster_name)
  }

}

resource "aws_security_group_rule" "cluster_ingress_https" {
  cidr_blocks = [var.cluster_vpc.cidr_block]
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"

  security_group_id = aws_security_group.cluster_master_sg.id
  type              = "ingress"
  description       = "Allow HTTPS from VPC for EKS control plane communication"
}

resource "aws_security_group_rule" "cluster_ingress_kubelet" {
  cidr_blocks = [var.cluster_vpc.cidr_block]
  from_port   = 10250
  to_port     = 10250
  protocol    = "tcp"

  security_group_id = aws_security_group.cluster_master_sg.id
  type              = "ingress"
  description       = "Allow kubelet API from worker nodes"
}