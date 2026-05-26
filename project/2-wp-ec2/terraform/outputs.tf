output "wordpress_url" {
  value       = "http://${aws_instance.wordpress.public_ip}"
  description = "URL pública de WordPress"
}

output "public_ip" {
  value = aws_instance.wordpress.public_ip
}
