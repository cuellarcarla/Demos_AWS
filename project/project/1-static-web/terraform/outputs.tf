output "website_url" {
  value = "http://${aws_s3_bucket_website_configuration.web.website_endpoint}"
}
output "bucket_name" {
  value = aws_s3_bucket.web.id
}
