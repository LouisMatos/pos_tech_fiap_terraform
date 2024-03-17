output "nlb_arn" {
  description = "The ARN of the Network Load Balancer"
  value       = aws_lb.aws_alb.arn
}

output "nlb_dns_name" {
  description = "The DNS name of the Network Load Balancer"
  value       = aws_lb.aws_alb.dns_name
}

output "security_group" {
  value = aws_security_group.elb_sg
}
