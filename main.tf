provider "aws" {
  region = "us-east-1"
}

data "aws_iam_policy_document" "lambda_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "lambda_role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

data "aws_iam_policy_document" "lambda" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "lambda"
  role   = aws_iam_role.lambda_role.id
  policy = data.aws_iam_policy_document.lambda.json
}

resource "aws_lambda_function" "code_lambda_autenticacao_cliente" {
  function_name = "lambda_autenticacao_cliente"
  role          = aws_iam_role.lambda_role.arn

  s3_bucket = "codigo-lambda"
  s3_key    = "lambda.zip"

  runtime = "python3.10"
  handler = "lambda_function.lambda_handler"
}