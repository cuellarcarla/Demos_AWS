output "wordpress_url" {
  value       = "http://${aws_lb.wp.dns_name}"
  description = "URL de WordPress via ALB"
}
