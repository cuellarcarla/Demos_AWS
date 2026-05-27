terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    bucket = "tfstate-carla-demos-2026"
    key    = "wp-ecs/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_vpc" "default" { default = true }

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_caller_identity" "current" {}

locals {
  # LabRole és el rol pre-creat per AWS Academy — NO es crea, es referencia
  lab_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LabRole"
}

# Security Group per ECS i ALB
resource "aws_security_group" "ecs" {
  name        = "wp-ecs-sg"
  description = "WordPress ECS"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
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

# CloudWatch Log Group (ECS necessita on escriure logs)
resource "aws_cloudwatch_log_group" "wp" {
  name              = "/ecs/wordpress"
  retention_in_days = 1
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "wordpress-cluster"
}

# Task Definition — usa LabRole directament
resource "aws_ecs_task_definition" "wordpress" {
  family                   = "wordpress"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"

  # Aquí va el LabRole — no el creem, ja existeix
  execution_role_arn = local.lab_role_arn
  task_role_arn      = local.lab_role_arn

  container_definitions = jsonencode([
    {
      name      = "wordpress"
      image     = "wordpress:php8.2-apache"
      essential = true
      portMappings = [{ containerPort = 80, hostPort = 80, protocol = "tcp" }]
      environment = [
        { name = "WORDPRESS_DB_HOST",     value = "127.0.0.1:3306" },
        { name = "WORDPRESS_DB_USER",     value = "wpuser" },
        { name = "WORDPRESS_DB_PASSWORD", value = "wppass" },
        { name = "WORDPRESS_DB_NAME",     value = "wordpress" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.wp.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "wp"
        }
      }
    },
    {
      name      = "mysql"
      image     = "mysql:8.0"
      essential = false
      environment = [
        { name = "MYSQL_DATABASE",      value = "wordpress" },
        { name = "MYSQL_USER",          value = "wpuser" },
        { name = "MYSQL_PASSWORD",      value = "wppass" },
        { name = "MYSQL_ROOT_PASSWORD", value = "rootpass" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.wp.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "mysql"
        }
      }
    }
  ])
}

# ALB
resource "aws_lb" "wp" {
  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ecs.id]
  subnets            = tolist(data.aws_subnets.default.ids)
}

resource "aws_lb_target_group" "wp" {
  name        = "wordpress-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 10
    interval            = 30
    matcher             = "200,301,302"
  }
}

resource "aws_lb_listener" "wp" {
  load_balancer_arn = aws_lb.wp.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wp.arn
  }
}

# ECS Service
resource "aws_ecs_service" "wordpress" {
  name            = "wordpress-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.wordpress.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = tolist(data.aws_subnets.default.ids)
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.wp.arn
    container_name   = "wordpress"
    container_port   = 80
  }

  depends_on = [aws_lb_listener.wp]
}
