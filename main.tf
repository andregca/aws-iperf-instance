# ============================================================================
# main.tf — single‑region template
# ---------------------------------------------------------------------------
# Provision one VPC + public subnet + IGW + Security Group + Amazon Linux 2023
# instance in **the region supplied via -var="aws_region=<region>"**.
# Works standalone or via iperf-ctl.sh.
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
  region  = var.aws_region
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
    values = ["al2023-ami-2023*-x86_64"]
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
# Security Groups
#########################
# Inbound is controlled by SGs attached to the same ENI:
#   - cato_pop SG(s): all ports/protocols from Cato POP CIDRs (var.cato_pop_cidrs).
#     Split into chunks of 60 rules (default AWS quota per SG).
#   - test SG: all ports/protocols from the user's test CIDRs (var.test_cidrs),
#     plus allow-all outbound.
# AWS default quota is 5 SGs per ENI, so at most 4 Cato POP chunks (240 CIDRs).
locals {
  sg_rules_per_group = 60
  cato_pop_chunks    = chunklist(var.cato_pop_cidrs, local.sg_rules_per_group)
  cato_pop_rules = merge([
    for i, chunk in local.cato_pop_chunks : {
      for cidr in chunk : "${i}-${cidr}" => { group = i, cidr = cidr }
    }
  ]...)
}

resource "aws_security_group" "cato_pop" {
  count       = length(local.cato_pop_chunks)
  name        = "${var.instance_name_prefix}-cato-pop-sg-${count.index + 1}"
  description = "Allow all inbound from Cato POPs (${count.index + 1}/${length(local.cato_pop_chunks)})"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${var.instance_name_prefix}-cato-pop-sg-${count.index + 1}" }

  lifecycle {
    precondition {
      condition     = length(local.cato_pop_chunks) <= 4
      error_message = "cato_pop_cidrs needs ${length(local.cato_pop_chunks)} security groups, but only 4 fit on one ENI with the default quota of 5 SGs per ENI (the 5th is the test SG)."
    }
  }
}

resource "aws_vpc_security_group_ingress_rule" "cato_pop" {
  for_each          = local.cato_pop_rules
  security_group_id = aws_security_group.cato_pop[each.value.group].id
  ip_protocol       = "-1"
  cidr_ipv4         = each.value.cidr
  description       = "Cato POP"
}

resource "aws_security_group" "test" {
  name        = "${var.instance_name_prefix}-test-sg"
  description = "Allow all inbound from user test CIDRs; all outbound"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${var.instance_name_prefix}-test-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "test" {
  for_each          = toset(var.test_cidrs)
  security_group_id = aws_security_group.test.id
  ip_protocol       = "-1"
  cidr_ipv4         = each.value
  description       = "Test source"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.test.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Allow all outbound"
}

#########################
# EC2 Instance
#########################
resource "aws_instance" "host" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = concat(aws_security_group.cato_pop[*].id, [aws_security_group.test.id])
  key_name                    = var.key_name
  associate_public_ip_address = true
  user_data                   = file(var.user_data_path)

  tags = { Name = "${var.instance_name_prefix}" }
}

#########################
# Outputs
#########################
output "instance_public_ip" { value = aws_instance.host.public_ip }
output "instance_public_dns" { value = aws_instance.host.public_dns }
