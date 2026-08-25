variable "vpc_cidr" { default = "10.0.0.0/16" }

resource "aws_vpc" "custom_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "production-eks-vpc"
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.custom_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name                     = "production-public-subnet-1a"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.custom_vpc.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name                              = "production-private-subnet-1b"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

output "vpc_id" { value = aws_vpc.custom_vpc.id }
output "private_subnet_id" { value = aws_subnet.private_subnet.id }
