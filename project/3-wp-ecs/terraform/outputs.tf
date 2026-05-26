output "wordpress_url" {
  value = "http://${aws_lb.wp.dns_name}"
}
