# Broker unico compartilhado por pedido/pagamento/producao - substitui os 3
# Deployments de RabbitMQ duplicados que hoje existem um por servico no k8s.

resource "random_password" "this" {
  length  = 24
  special = false
}

resource "aws_security_group" "this" {
  name        = "${var.identifier}-sg"
  description = "Permite acesso ao Amazon MQ ${var.identifier} apenas a partir do EKS"
  vpc_id      = var.cluster_vpc.id

  ingress {
    from_port       = 5671
    to_port         = 5671
    protocol        = "tcp"
    security_groups = [var.eks_sg_id]
  }

  ingress {
    from_port       = 15671
    to_port         = 15671
    protocol        = "tcp"
    security_groups = [var.eks_sg_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_mq_broker" "this" {
  broker_name         = var.identifier
  engine_type         = "RabbitMQ"
  engine_version      = var.engine_version
  host_instance_type  = var.instance_type
  deployment_mode     = var.deployment_mode
  subnet_ids          = var.deployment_mode == "SINGLE_INSTANCE" ? [var.private_subnet_ids[0]] : var.private_subnet_ids
  security_groups     = [aws_security_group.this.id]
  publicly_accessible = false

  user {
    username = var.username
    password = random_password.this.result
  }
}

resource "aws_secretsmanager_secret" "this" {
  name = "${var.identifier}-mq-credentials"
}

resource "aws_secretsmanager_secret_version" "this" {
  secret_id = aws_secretsmanager_secret.this.id
  secret_string = jsonencode({
    host     = replace(aws_mq_broker.this.instances[0].endpoints[0], "amqps://", "")
    username = var.username
    password = random_password.this.result
  })
}
