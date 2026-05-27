terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    bucket = "tfstate-carla-demos-2026"
    key    = "wp-ec2/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region
}

# Usem la VPC per defecte del Learner Lab
data "aws_vpc" "default" { default = true }

# SOLUCIÓ DE XARXA: Busquem només les subnets que tinguin IP pública real
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "map-public-ip-on-launch"
    values = ["true"]
  }
}

# Security Group: obrim port 80 (Web) i port 22 (SSH de seguretat)
resource "aws_security_group" "wp" {
  name        = "wp-ec2-sg"
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

# AMI Amazon Linux 2023
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_instance" "wordpress" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t2.micro"
  
  # Forcem l'ús de la subnet pública trobada pel filtre
  subnet_id                   = tolist(data.aws_subnets.public.ids)[0]
  
  vpc_security_group_ids      = [aws_security_group.wp.id]
  associate_public_ip_address = true
  user_data_replace_on_change = true

  key_name                    = "vockey"
  iam_instance_profile        = "LabInstanceProfile"

  user_data = <<EOF
#!/bin/bash
# Evitar bloquejos interns de sortida a Internet
echo "START" > /var/log/user-data.log

# Anem directes a instal·lar DOCKER sense fer el 'yum update' sencer per no congelar la màquina
yum install -y docker &>> /var/log/user-data.log

# Descarreguem manualment el Docker Compose per si el paquet d'Amazon falla
mkdir -p /usr/local/lib/docker/cli-plugins/
curl -SL https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Engeguem el servei
systemctl start docker &>> /var/log/user-data.log
systemctl enable docker &>> /var/log/user-data.log

# Crear directori i el fitxer
mkdir -p /opt/wp
cat << 'ENDOFCOMPOSE' > /opt/wp/docker-compose.yml
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
    depends_on:
      - db
    volumes:
      - wp_data:/var/www/html
volumes:
  db_data:
  wp_data:
ENDOFCOMPOSE

# Executar el docker compose amb rutes clares
cd /opt/wp
docker compose up -d &>> /var/log/user-data.log

echo "END" >> /var/log/user-data.log
EOF

  tags = {
    Name = "wordpress-ec2-demo"
  }
}
