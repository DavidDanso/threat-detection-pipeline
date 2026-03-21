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

# module "lambda" {
#   source = "./modules/lambda"
# }

# module "notifications" {
#   source = "./modules/notifications"
# }
