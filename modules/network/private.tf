resource "aws_subnet" "private_subnet_1a" {
  vpc_id     = aws_vpc.cluster_vpc.id
  cidr_block = "10.0.32.0/20"

  availability_zone = format("%sa", var.aws_region)

  tags = {
    Name                                        = format("%s-private-1a", var.cluster_name),
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_subnet" "private_subnet_1c" {
  vpc_id     = aws_vpc.cluster_vpc.id
  cidr_block = "10.0.48.0/20"

  availability_zone = format("%sc", var.aws_region)

  tags = {
    Name                                        = format("%s-private-1c", var.cluster_name),
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_route_table_association" "private1a" {
  subnet_id      = aws_subnet.private_subnet_1a.id
  route_table_id = aws_route_table.nat.id
}

resource "aws_route_table_association" "private1c" {
  subnet_id      = aws_subnet.private_subnet_1c.id
  route_table_id = aws_route_table.nat.id
}

# S3 gateway endpoint: gratis; tira do NAT as camadas de imagem do ECR (ficam no S3).
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.cluster_vpc.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.nat.id]

  tags = {
    Name = format("%s-s3-endpoint", var.cluster_name)
  }
}
