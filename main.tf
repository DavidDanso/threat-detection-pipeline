provider "aws" {
  region = var.aws_region
}

module "guardduty" {
  source       = "./modules/guardduty"
  project_name = var.project_name
}

# module "eventbridge" {
#   source = "./modules/eventbridge"
# }

module "lambda" {
  source                    = "./modules/lambda"
  project_name              = var.project_name
  sns_topic_arn             = module.notifications.sns_topic_arn
  cloudwatch_log_group_name = module.notifications.cloudwatch_log_group_name
  guardduty_detector_id     = module.guardduty.detector_id
  lambda_timeout            = var.lambda_timeout
  lambda_memory             = var.lambda_memory
}

module "notifications" {
  source             = "./modules/notifications"
  project_name       = var.project_name
  alert_email        = var.alert_email
  log_retention_days = var.log_retention_days
}
