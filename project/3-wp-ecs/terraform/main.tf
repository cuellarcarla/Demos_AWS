terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    bucket = "tfstate-cv-challenge"
    key    = "wp-ecs/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_vpc" "default"     { default = true }
data "aws_subnets" "default" {
  filter { name = "vpc-id", values = [data.aws_vpc.default.id] }
}

# --- Security Group ---
resource "aws_security_group" "ecs_wp" {
  name   = "${var.project_name}-ecs-wp-sg"
  vpc_id = data.aws_vpc.default.id

  ingress { from_port = 80, to_port = 80, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] }
  egress  { from_port = 0,  to_port = 0,  protocol = "-1",  cidr_blocks = ["0.0.0.0/0"] }
}

# --- ECS Cluster ---
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"
}

# --- IAM Role per ECS Task Execution ---
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project_name}-ecs-task-exec"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_exec" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# --- ECS Task Definition ---
resource "aws_ecs_task_definition" "wordpress" {
  family                   = "${var.project_name}-wp"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name  = "wordpress"
      image = "wordpress:latest"
      portMappings = [{ containerPort = 80, hostPort = 80 }]
      environment = [
        { name = "WORDPRESS_DB_HOST",     value = "127.0.0.1" },
        { name = "WORDPRESS_DB_USER",     value = "root" },
        { name = "WORDPRESS_DB_PASSWORD", value = "rootpass" },
        { name = "WORDPRESS_DB_NAME",     value = "wordpress" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.project_name}-wp"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    },
    {
      name  = "mysql"
      image = "mysql:8.0"
      environment = [
        { name = "MYSQL_ROOT_PASSWORD", value = "rootpass" },
        { name = "MYSQL_DATABASE",      value = "wordpress" }
      ]
    }
  ])
}

# --- CloudWatch Log Group ---
resource "aws_cloudwatch_log_group" "ecs_wp" {
  name              = "/ecs/${var.project_name}-wp"
  retention_in_days = 7
}

# --- ALB ---
resource "aws_lb" "wp" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ecs_wp.id]
  subnets            = tolist(data.aws_subnets.default.ids)
}

resource "aws_lb_target_group" "wp" {
  name        = "${var.project_name}-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"
  health_check { path = "/" }
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

# --- ECS Service ---
resource "aws_ecs_service" "wordpress" {
  name            = "${var.project_name}-wp-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.wordpress.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = tolist(data.aws_subnets.default.ids)
    security_groups  = [aws_security_group.ecs_wp.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.wp.arn
    container_name   = "wordpress"
    container_port   = 80
  }

  depends_on = [aws_lb_listener.wp]
}
