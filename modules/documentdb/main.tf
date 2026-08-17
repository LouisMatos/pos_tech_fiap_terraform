# DocumentDB nao tem tier "micro" - db.t3.medium e o menor disponivel,
# custo bem maior que RDS. Trade-off aceito por usar Mongo-compativel gerenciado.

resource "random_password" "this" {
  length  = 24
  special = false
}

resource "aws_docdb_subnet_group" "this" {
  name       = "${var.identifier}-subnet-group"
  subnet_ids = var.private_subnet_ids
}

resource "aws_security_group" "this" {
  name        = "${var.identifier}-sg"
  description = "Permite acesso ao DocumentDB ${var.identifier} apenas a partir do EKS"
  vpc_id      = var.cluster_vpc.id

  ingress {
    from_port       = 27017
    to_port         = 27017
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

resource "aws_docdb_cluster" "this" {
  cluster_identifier     = var.identifier
  master_username        = var.username
  master_password        = random_password.this.result
  db_subnet_group_name   = aws_docdb_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  skip_final_snapshot    = true
  storage_encrypted      = true
}

resource "aws_docdb_cluster_instance" "this" {
  count              = var.instance_count
  identifier         = "${var.identifier}-${count.index}"
  cluster_identifier = aws_docdb_cluster.this.id
  instance_class     = var.instance_class
}

resource "aws_secretsmanager_secret" "this" {
  name = "${var.identifier}-db-credentials"
}

resource "aws_secretsmanager_secret_version" "this" {
  secret_id = aws_secretsmanager_secret.this.id
  secret_string = jsonencode({
    host     = aws_docdb_cluster.this.endpoint
    port     = aws_docdb_cluster.this.port
    username = var.username
    password = random_password.this.result
  })
}
