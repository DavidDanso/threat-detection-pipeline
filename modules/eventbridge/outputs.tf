output "event_rule_arn" {
  description = "EventBridge rule ARN"
  value       = aws_cloudwatch_event_rule.guardduty_remediation.arn
}

output "event_rule_name" {
  description = "EventBridge rule name"
  value       = aws_cloudwatch_event_rule.guardduty_remediation.name
}
