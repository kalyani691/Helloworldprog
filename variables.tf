variable "aws_region" {
  type    = string
  default = "eu-north-1"
}

variable "lambda_name" {
  type    = string
  default = "my-lambda-function"
}

variable "ecr_repo_name" {
  type    = string
  default = "my-lambda-ecr"
}
