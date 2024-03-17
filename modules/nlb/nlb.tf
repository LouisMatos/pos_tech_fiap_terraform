
resource "aws_lb" "aws_alb" {
  name               = "jlapp-service-lb"
  internal           = false
  load_balancer_type = "application"
  subnets            = [var.private_subnet_1a.id, var.private_subnet_1c.id]
  security_groups    = [aws_security_group.elb_sg.id]

  enable_deletion_protection = true

  tags = {
    Name = "jlapp-service-lb"
  }
}

resource "aws_lb_listener" "listener_jlapp_service" {
  load_balancer_arn = aws_lb.aws_alb.arn
  port              = "8070"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_jlapp_service.arn
  }
}

resource "aws_lb_target_group" "target_jlapp_service" {
  name     = "targetjlappservice"
  port     = 8070
  protocol = "HTTP"
  vpc_id      = var.cluster_vpc

  health_check {
    enabled             = true
    interval            = 30
    path                = "/actuator/health"
    port                = "traffic-port"
    timeout             = 3
    healthy_threshold   = 3
    unhealthy_threshold = 3
    matcher             = "200-399"
  }
}

resource "aws_security_group" "elb_sg" {
  name        = "elb_sg"
  description = "Allow inbound traffic to ELB"
  vpc_id      = var.cluster_vpc

  ingress {
    from_port   = 8070
    to_port     = 8070
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_instances" "node_group_instances" {
  instance_tags = {
    "aws:eks:nodegroup-name" = var.node_group
    "aws:eks:cluster-name" = var.cluster_name
  }
}

resource "aws_lb_target_group_attachment" "target_group_attachment" {
  count            = length(data.aws_instances.node_group_instances.ids)
  target_group_arn = aws_lb_target_group.target_jlapp_service.arn
  target_id        = data.aws_instances.node_group_instances.ids[count.index]
}