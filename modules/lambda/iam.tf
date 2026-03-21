data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${var.project_name}-lambda-exec-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "lambda_permissions" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:log-group:${var.cloudwatch_log_group_name}:*"
    ]
  }

  statement {
    actions   = ["sns:Publish"]
    resources = [var.sns_topic_arn]
  }

  statement {
    actions = [
      "iam:DeleteLoginProfile",
      "iam:UpdateAccessKey",
      "iam:ListAccessKeys",
      "iam:GetUser"
    ]
    resources = ["arn:aws:iam::*:user/*"]
  }

  statement {
    actions   = ["guardduty:GetFindings"]
    resources = ["arn:aws:guardduty:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:detector/${var.guardduty_detector_id}"]
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name   = "${var.project_name}-lambda-policy"
  policy = data.aws_iam_policy_document.lambda_permissions.json
}

resource "aws_iam_role_policy_attachment" "lambda_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}
