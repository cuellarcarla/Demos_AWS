terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    bucket = "tfstate-cv-challenge"
    key    = "wp-ec2/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region
}

# --- VPC default (Learner Lab ja la té) ---
data "aws_vpc" "default" { default = true }

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# --- Security Group ---
resource "aws_security_group" "wp_ec2" {
  name        = "${var.project_name}-wp-ec2-sg"
  description = "WordPress EC2"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
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
}

# --- AMI Ubuntu 22.04 ---
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# --- EC2 Instance ---
resource "aws_instance" "wordpress" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = tolist(data.aws_subnets.default.ids)[0]
  vpc_security_group_ids = [aws_security_group.wp_ec2.id]
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y docker.io docker-compose-plugin
    systemctl start docker
    systemctl enable docker

    mkdir -p /opt/wordpress
    cat > /opt/wordpress/docker-compose.yml << 'COMPOSE'
version: '3.8'
services:
  db:
    image: mysql:8.0
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: rootpass
      MYSQL_DATABASE: wordpress
      MYSQL_USER: wpuser
      MYSQL_PASSWORD: wppass
    volumes:
      - db_data:/var/lib/mysql

  wordpress:
    image: wordpress:latest
    restart: always
    ports:
      - "80:80"
    environment:
      WORDPRESS_DB_HOST: db
      WORDPRESS_DB_USER: wpuser
      WORDPRESS_DB_PASSWORD: wppass
      WORDPRESS_DB_NAME: wordpress
    volumes:
      - wp_data:/var/www/html

volumes:
  db_data:
  wp_data:
COMPOSE

    cd /opt/wordpress && docker compose up -d
  EOF

  tags = {
    Name        = "${var.project_name}-wordpress-ec2"
    Environment = var.environment
  }
}
