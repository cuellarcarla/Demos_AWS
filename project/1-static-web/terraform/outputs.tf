output "website_url" {
  value       = aws_s3_bucket_website_configuration.web.website_endpoint
  description = "URL pública de la web estàtica"
}

output "bucket_name" {
  value = aws_s3_bucket.web.id
}
