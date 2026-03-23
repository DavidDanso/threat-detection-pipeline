output "security_hub_id" {
  description = "Security Hub account ID"
  value       = aws_securityhub_account.main.id
}

output "security_hub_arn" {
  description = "Security Hub account ARN"
  value       = aws_securityhub_account.main.arn
}
