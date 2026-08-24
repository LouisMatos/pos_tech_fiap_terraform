# NAT Gateway (padrao, gerenciado pela AWS, ~$32-35/mes fixo + dados) ---
resource "aws_eip" "vpc_iep" {
  count = var.nat_type == "gateway" ? 1 : 0

  tags = {
    Name = format("%s-eip", var.cluster_name)
  }
}

resource "aws_nat_gateway" "nat" {
  count = var.nat_type == "gateway" ? 1 : 0

  allocation_id = aws_eip.vpc_iep[0].id
  subnet_id     = aws_subnet.public_subnet_1a.id

  tags = {
    Name = format("%s-nat-gateway", var.cluster_name)
  }
}

# NAT Instance (EC2 t3.micro, ~$3-4/mes, sem HA gerenciada - so pra dev/teste) ---
data "aws_ami" "nat_instance" {
  count = var.nat_type == "instance" ? 1 : 0

  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "nat_instance" {
  count = var.nat_type == "instance" ? 1 : 0

  name        = format("%s-nat-instance-sg", var.cluster_name)
  description = "Permite trafego da VPC atraves da NAT instance"
  vpc_id      = aws_vpc.cluster_vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.cluster_vpc.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = format("%s-nat-instance-sg", var.cluster_name)
  }
}

resource "aws_instance" "nat" {
  count = var.nat_type == "instance" ? 1 : 0

  ami                    = data.aws_ami.nat_instance[0].id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_subnet_1a.id
  vpc_security_group_ids = [aws_security_group.nat_instance[0].id]
  source_dest_check      = false

  user_data = <<-EOF
    #!/bin/bash
    echo 1 > /proc/sys/net/ipv4/ip_forward
    sysctl -w net.ipv4.ip_forward=1
    sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    /usr/sbin/iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
    /sbin/iptables-save > /etc/sysconfig/iptables
  EOF

  tags = {
    Name = format("%s-nat-instance", var.cluster_name)
  }
}

resource "aws_eip" "nat_instance" {
  count = var.nat_type == "instance" ? 1 : 0

  instance = aws_instance.nat[0].id
  domain   = "vpc"

  tags = {
    Name = format("%s-nat-instance-eip", var.cluster_name)
  }
}

# Route table compartilhada pelas subnets privadas, aponta pro NAT ativo (gateway ou instance) ---
resource "aws_route_table" "nat" {
  vpc_id = aws_vpc.cluster_vpc.id

  tags = {
    Name = format("%s-private-route", var.cluster_name)
  }
}

resource "aws_route" "nat_access" {
  route_table_id         = aws_route_table.nat.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = var.nat_type == "gateway" ? aws_nat_gateway.nat[0].id : null
  network_interface_id   = var.nat_type == "instance" ? aws_instance.nat[0].primary_network_interface_id : null
}
