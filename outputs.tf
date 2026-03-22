output "guardduty_detector_id" {
  description = "GuardDuty detector ID"
  value       = module.guardduty.detector_id
}

output "sns_topic_arn" {
  description = "SNS Topic ARN"
  value       = module.notifications.sns_topic_arn
}

output "lambda_function_arn" {
  description = "Lambda function ARN"
  value       = module.lambda.lambda_function_arn
}
