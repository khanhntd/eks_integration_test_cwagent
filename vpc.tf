#Requires two subnet in at least 2 AZs:
# Public subnet: create for load balancer to get contact with Kube API in master node
# Private subnet: for Kube API in master node contacts with workers node or communication between worker nodes

resource "aws_vpc" "custom_vpc" {
  cidr_block = var.vpc_cidr_block
  # Your VPC must have DNS hostname and DNS resolution support. 
  # Otherwise, your worker nodes cannot register with your cluster. 
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name                                            = "${var.vpc_tag_name}-${var.environment}"
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
  }
}

##########################################
# VPC Network setup
##########################################
# Create the private subnet
resource "aws_subnet" "private_subnet" {
  vpc_id     = aws_vpc.custom_vpc.id
  cidr_block = var.private_subnet_cidr_block
  tags = {
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"               = 1
  }
  depends_on = [
    aws_vpc.custom_vpc
  ]
}

# Create the public subnet
resource "aws_subnet" "public_subnet" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.custom_vpc.id
  cidr_block        = element(var.public_subnet_cidr_blocks, count.index)
  availability_zone = element(var.availability_zones, count.index)
  tags = {
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
    "kubernetes.io/role/elb"                        = 1
  }
  map_public_ip_on_launch = true
  depends_on = [
    aws_vpc.custom_vpc
  ]
}

# Create Internet Gateway for the public subnets: route address to public subnet
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.custom_vpc.id
}

# Route the public subnet traffic through the IGW
resource "aws_route_table" "main" {
  vpc_id = aws_vpc.custom_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "${var.route_table_tag_name}-${var.environment}"
  }
}
# Route table and subnet associations
resource "aws_route_table_association" "internet_access" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.main.id
}

### Communications between ECR and EKS within VPC
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.custom_vpc.id
  service_name        = "com.amazonaws.${var.region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = flatten([["${aws_subnet.private_subnet.id}"], aws_subnet.public_subnet.*.id])
  security_group_ids  = [aws_security_group.endpoint_ecr.id]
  tags = {
    Name        = "ECR Docker VPC Endpoint Interface - ${var.environment}"
    Environment = var.environment
  }
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.custom_vpc.id
  service_name        = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = flatten([["${aws_subnet.private_subnet.id}"], aws_subnet.public_subnet.*.id])
  security_group_ids  = [aws_security_group.endpoint_ecr.id]
  tags = {
    Name        = "ECR API VPC Endpoint Interface - ${var.environment}"
    Environment = var.environment
  }
}

resource "aws_security_group" "endpoint_ecr" {
  name   = "endpoint-ecr-sg"
  vpc_id = aws_vpc.custom_vpc.id
}

resource "aws_security_group_rule" "endpoint_ecr_443" {
  security_group_id = aws_security_group.endpoint_ecr.id
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = flatten([[var.private_subnet_cidr_block], var.public_subnet_cidr_blocks])
}

### Communications between EC2 and EKS within VPC
resource "aws_vpc_endpoint" "ec2" {
  vpc_id              = aws_vpc.custom_vpc.id
  service_name        = "com.amazonaws.${var.region}.ec2"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = flatten([["${aws_subnet.private_subnet.id}"], aws_subnet.public_subnet.*.id])
  security_group_ids  = [aws_security_group.endpoint_ec2.id]
  tags = {
    Name        = "EC2 VPC Endpoint Interface - ${var.environment}"
    Environment = var.environment
  }
}

resource "aws_security_group" "endpoint_ec2" {
  name   = "endpoint-ec2-sg"
  vpc_id = aws_vpc.custom_vpc.id
}

resource "aws_security_group_rule" "endpoint_ec2_443" {
  security_group_id = aws_security_group.endpoint_ec2.id
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = flatten([[var.private_subnet_cidr_block], var.public_subnet_cidr_blocks])
}

# S3
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.custom_vpc.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [var.main_pvt_route_table_id]
  tags = {
    Name        = "S3 VPC Endpoint Gateway - ${var.environment}"
    Environment = var.environment
  }
}


