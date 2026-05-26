terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Estat en S3 (crea el bucket manualment abans: aws s3 mb s3://tfstate-cv-challenge)
  backend "s3" {
    bucket = "tfstate-cv-challenge"
    key    = "static-web/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region
}

# --- S3 bucket per la web ---
resource "aws_s3_bucket" "web" {
  bucket = "${var.project_name}-web-${var.environment}"
}

resource "aws_s3_bucket_public_access_block" "web" {
  bucket                  = aws_s3_bucket.web.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "web" {
  bucket = aws_s3_bucket.web.id
  index_document { suffix = "index.html" }
  error_document { key    = "error.html" }
}

resource "aws_s3_bucket_policy" "web" {
  bucket = aws_s3_bucket.web.id
  depends_on = [aws_s3_bucket_public_access_block.web]
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.web.arn}/*"
    }]
  })
}
