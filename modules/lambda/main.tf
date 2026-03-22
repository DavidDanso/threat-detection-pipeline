data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.root}/lambda_src"
  output_path = "${path.module}/lambda_payload.zip"
}

data "aws_cloudwatch_log_group" "remediate_log" {
  # Mix in an unknown-at-plan-time variable to force data source reading to defer to apply phase
  name = var.sns_topic_arn != "" ? var.cloudwatch_log_group_name : var.cloudwatch_log_group_name
}

resource "aws_lambda_function" "remediate" {
  function_name    = "${var.project_name}-remediate"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "remediate.handler"
  runtime          = "python3.12"
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN = var.sns_topic_arn
      LOG_LEVEL     = "INFO"
    }
  }

  depends_on = [
    data.aws_cloudwatch_log_group.remediate_log,
    aws_iam_role_policy_attachment.lambda_attach
  ]
}
