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
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# -------- VPC --------
data "aws_vpc" "default" {
  default = true
}

# -------- IAM Role (créé par Terraform) --------
resource "aws_iam_role" "docmost_prod_role" {
  name = "docmost-ec2-role-prod-v2"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "docmost_prod_profile" {
  name = "docmost-prod-instance-profile-v2"
  role = aws_iam_role.docmost_prod_role.name
}

# -------- S3 Backup Access (Docmost Prod) --------
resource "aws_iam_role_policy" "docmost_s3_backup_policy" {
  name = "docmost-backup-s3-policy"
  role = aws_iam_role.docmost_prod_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::docmost-backups-prod-682135518833-v2",
          "arn:aws:s3:::docmost-backups-prod-682135518833-v2/*"
        ]
      }
    ]
  })
}

# -------- Attach CloudWatch Policy --------
resource "aws_iam_role_policy_attachment" "cloudwatch_agent_policy" {
  role       = aws_iam_role.docmost_prod_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Attach CloudWatch Read Only (pour Grafana)
resource "aws_iam_role_policy_attachment" "cloudwatch_readonly_policy" {
  role       = aws_iam_role.docmost_prod_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

# Attach EC2 Read Only (pour récupérer InstanceId)
resource "aws_iam_role_policy_attachment" "ec2_readonly_policy" {
  role       = aws_iam_role.docmost_prod_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
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
    description = "Custom TCP"
    from_port   = 90
    to_port     = 90
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # TEMPORARY RULE
# Allows direct public access to Prometheus (port 9090).
# This rule must be removed once monitoring is isolated on a dedicated instance
# or behind a reverse proxy / private network.

  ingress {
    description = "Temporary public access to Prometheus"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

# END TEMPORARY RULE

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
  iam_instance_profile        = aws_iam_instance_profile.docmost_prod_profile.name
  user_data_replace_on_change = true

  root_block_device {
  volume_size = 30
  volume_type = "gp3"
}

#  IMDSv2 only (sécurité AWS)  
  metadata_options {
    http_tokens = "required"
  }

  user_data = <<-EOF
#!/bin/bash
set -e

apt update -y
apt install -y ca-certificates curl gnupg git

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  gpg --dearmor -o /etc/apt/keyrings/docker.gpg

chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo $VERSION_CODENAME) stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update -y
apt install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

systemctl enable docker
systemctl start docker

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