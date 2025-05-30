# ============================================================================
# main.tf — single‑region template
# ---------------------------------------------------------------------------
# Provision one VPC + public subnet + IGW + Security Group + Amazon Linux 2023
# instance in **the region supplied via -var="aws_region=<region>"**.
# Works standalone or via deploy.sh.
# ============================================================================

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  profile = var.profile
}

#########################
# Data sources
#########################

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*x86_64"]
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

#########################
# Networking
#########################
resource "aws_vpc" "this" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = var.vpc_name }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.vpc_name}-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = { Name = "${var.vpc_name}-public-subnet" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${var.vpc_name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

#########################
# Security Group
#########################
resource "aws_security_group" "host" {
  name        = "${var.instance_name_prefix}-sg"
  description = "Allow ICMP + iperf3 inbound; all outbound"
  vpc_id      = aws_vpc.this.id

  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol    = "icmp"
    from_port   = -1
    to_port     = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol    = "udp"
    from_port   = 5201
    to_port     = 5201
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 5201
    to_port     = 5201
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.instance_name_prefix}-sg" }
}

#########################
# EC2 Instance
#########################
resource "aws_instance" "host" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.host.id]
  key_name                    = var.key_name
  associate_public_ip_address = true
  user_data                   = file(var.user_data_path)

  tags = { Name = "${var.instance_name_prefix}" }
}

#########################
# Outputs
#########################
output "instance_public_ip"  { value = aws_instance.host.public_ip  }
output "instance_public_dns" { value = aws_instance.host.public_dns }
