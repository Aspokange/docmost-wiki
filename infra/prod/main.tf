terraform {
  required_version = ">= 1.2"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.92"
    }
  }

  backend "s3" {
    bucket         = "docmost-terraform-state-nina"
    key            = "prod/terraform.tfstate"
    region         = "eu-west-3"
    dynamodb_table = "terraform-locks"
    encrypt        = true 
  }
}

provider "aws" {
  region = var.region
}

# -------- AMI --------
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-22.04-amd64-server-*"]
  }

  owners = ["099720109477"]
}

# -------- VPC --------
data "aws_vpc" "default" {
  default = true
}

# -------- Security Group --------
resource "aws_security_group" "docmost_sg" {
  name        = "${var.server_name}-sg"
  description = "Allow HTTP, HTTPS and SSH"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
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

  tags = {
    Environment = var.environment
  }
}

# -------- EC2 --------
resource "aws_instance" "docmost" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = "ci-cd-deploy-prod"
  vpc_security_group_ids      = [aws_security_group.docmost_sg.id]
  associate_public_ip_address = true
  user_data_replace_on_change = true

  # 🔐 IMDSv2 only (sécurité AWS)
  metadata_options {
    http_tokens = "required"
  }

  user_data = <<-EOF
#!/bin/bash
# force recreate
set -e

# Update system
apt update -y
apt install -y ca-certificates curl gnupg git

# Add Docker official GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  gpg --dearmor -o /etc/apt/keyrings/docker.gpg

chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo $VERSION_CODENAME) stable" | \
  tee /etc/apt/sources.list.d/docker.list > /prod/null

# Install Docker Engine + Compose v2
apt update -y
apt install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

# Enable and start Docker
systemctl enable docker
systemctl start docker

# Allow ubuntu user to run docker
usermod -aG docker ubuntu

EOF

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = var.server_name
    Environment = var.environment
  }
}