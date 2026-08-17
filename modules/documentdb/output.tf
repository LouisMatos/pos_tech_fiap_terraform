output "endpoint" {
  value = aws_docdb_cluster.this.endpoint
}

output "port" {
  value = aws_docdb_cluster.this.port
}

output "secret_arn" {
  value = aws_secretsmanager_secret.this.arn
}
