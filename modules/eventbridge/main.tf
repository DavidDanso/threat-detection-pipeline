resource "aws_cloudwatch_event_rule" "guardduty_remediation" {
  name        = "${var.project_name}-guardduty-rule"
  description = "Routes specific GuardDuty findings to the remediation Lambda"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    "detail-type" = ["GuardDuty Finding"]
    detail = {
      type = [
        "UnauthorizedAccess:IAMUser/ConsoleLoginSuccess.NoMFA",
        "UnauthorizedAccess:IAMUser/MaliciousIPCaller.Custom",
        "Recon:IAMUser/MaliciousIPCaller",
        "CredentialAccess:IAMUser/AnomalousBehavior"
      ]
    }
  })
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.guardduty_remediation.name
  target_id = "RemediationLambda"
  arn       = var.lambda_function_arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.guardduty_remediation.arn
}
