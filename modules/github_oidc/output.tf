output "role_arns" {
  value = { for repo, role in aws_iam_role.this : repo => role.arn }
}
