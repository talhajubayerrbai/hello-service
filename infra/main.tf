terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------
variable "aws_region"     { type = string }
variable "service_name"   { type = string }
variable "image_tag"      { type = string  default = "latest" }
variable "instance_type"  { type = string  default = "t3.micro" }
variable "github_owner"   { type = string  default = "talhajubayerrbai" }

locals {
  image = "ghcr.io/${var.github_owner}/${var.service_name}:${var.image_tag}"
}

# ---------------------------------------------------------------------------
# AMI  — latest Amazon Linux 2023 in the target region
# ---------------------------------------------------------------------------
data "aws_ami" "al2023" {
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

# ---------------------------------------------------------------------------
# Networking — reuse the default VPC
# ---------------------------------------------------------------------------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ---------------------------------------------------------------------------
# Security group
# ---------------------------------------------------------------------------
resource "aws_security_group" "hello" {
  name        = "${var.service_name}-sg"
  description = "Allow HTTP and SSH for ${var.service_name}"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "App port"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.service_name}-sg" }
}

# ---------------------------------------------------------------------------
# EC2 instance
# ---------------------------------------------------------------------------
resource "aws_instance" "hello" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = tolist(data.aws_subnets.default.ids)[0]
  vpc_security_group_ids      = [aws_security_group.hello.id]
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    set -e
    dnf install -y docker
    systemctl enable --now docker

    # Pull and run the container; fall back to building locally if registry unavailable
    docker pull ${local.image} || true

    # Run on port 80 -> container 8000
    docker run -d \
      --name ${var.service_name} \
      --restart unless-stopped \
      -p 80:8000 \
      ${local.image}
  EOF

  user_data_replace_on_change = true

  tags = { Name = var.service_name }
}

# ---------------------------------------------------------------------------
# Elastic IP — stable address survives stop/start
# ---------------------------------------------------------------------------
resource "aws_eip" "hello" {
  instance = aws_instance.hello.id
  domain   = "vpc"
  tags     = { Name = "${var.service_name}-eip" }

  depends_on = [aws_instance.hello]
}
