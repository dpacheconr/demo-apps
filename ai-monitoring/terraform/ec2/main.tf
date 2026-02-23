terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Owner = var.owner
    }
  }
}

locals {
  # Derive a short slug from the owner email for resource naming
  # e.g. "dpacheco@newrelic.com" → "dpacheco"
  owner_slug = replace(split("@", var.owner)[0], "/[^a-zA-Z0-9-]/", "-")
}

# ---------- Data Sources ----------

# Deep Learning OSS NVIDIA Driver AMI (Ubuntu 22.04) — drivers pre-installed
data "aws_ami" "dl_nvidia" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Deep Learning OSS Nvidia Driver AMI GPU TensorFlow * (Ubuntu 22.04)*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# ---------- SSH Key Pair (auto-generated) ----------

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "this" {
  key_name   = "${var.name_prefix}-${local.owner_slug}"
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "${path.module}/keys/${local.owner_slug}.pem"
  file_permission = "0400"
}

# ---------- Security Group ----------

resource "aws_security_group" "aim_demo" {
  name        = "${var.name_prefix}-${local.owner_slug}-sg"
  description = "Security group for AI Monitoring demo (${local.owner_slug})"
  vpc_id      = var.vpc_id

  # SSH
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # All outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-${local.owner_slug}-sg"
  }
}

# ---------- IAM Role (SSM access) ----------

resource "aws_iam_role" "aim_demo" {
  name = "${var.name_prefix}-${local.owner_slug}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = { Name = "${var.name_prefix}-${local.owner_slug}-ec2-role" }
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.aim_demo.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "aim_demo" {
  name = "${var.name_prefix}-${local.owner_slug}-ec2-profile"
  role = aws_iam_role.aim_demo.name
}

# ---------- EC2 Instance ----------

resource "aws_instance" "aim_demo" {
  ami                         = data.aws_ami.dl_nvidia.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.this.key_name
  iam_instance_profile        = aws_iam_instance_profile.aim_demo.name
  vpc_security_group_ids      = [aws_security_group.aim_demo.id]
  subnet_id                   = var.subnet_id
  associate_public_ip_address              = true
  instance_initiated_shutdown_behavior = "terminate"

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/user_data.sh", {
    new_relic_license_key = var.new_relic_license_key
    model_a_name          = var.model_a_name
    model_b_name          = var.model_b_name
    instance_ttl_hours    = var.instance_ttl_hours
  })

  metadata_options {
    http_tokens = "required" # IMDSv2
  }

  tags = {
    Name = "${var.name_prefix}-${local.owner_slug}-ec2"
  }
}
