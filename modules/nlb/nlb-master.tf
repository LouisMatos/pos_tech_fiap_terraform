resource "aws_lb" "nlb" {
  name               = var.name
  internal           = false
  load_balancer_type = "network"
  subnets            = var.subnet_ids
}

data "aws_instances" "eks_nodes" {
  filter {
    name   = "tag:Name"
    values = ["jlapp-cluster-node-group"]
  }
}

resource "aws_lb_target_group_attachment" "eks_nodes" {
  count            = length(data.aws_instances.eks_nodes.ids)
  target_group_arn = aws_lb_target_group.target_group.arn
  target_id        = data.aws_instances.eks_nodes.ids[count.index]
  port             = var.port
}

resource "aws_lb_target_group" "target_group" {
  name     = "${var.name}-tg"
  port     = var.port
  protocol = "TCP"
  vpc_id   = var.vpc_id

  target_type = var.target_type
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = var.port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group.arn
  }
}