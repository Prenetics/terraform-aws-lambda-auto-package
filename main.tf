#---------------------------------------------------------------------------------------------------
# IAM role for Lambda function
#---------------------------------------------------------------------------------------------------
resource "aws_iam_role" "this" {
  name_prefix        = var.iam_role_name_prefix
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = var.allowed_services
    }
  }
}

resource "aws_iam_role_policy_attachment" "basic" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "vpc" {
  count      = var.vpc_config == null ? 0 : 1
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda" {
  count = length(var.policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = var.policy_arns[count.index]
}


# Attach an additional policy if provided.
locals {
  attach_policy = var.policy != null
}

resource "aws_iam_policy" "additional" {
  count = local.attach_policy ? 1 : 0

  name   = var.function_name
  policy = var.policy.json
}

resource "aws_iam_role_policy_attachment" "additional" {
  count = local.attach_policy ? 1 : 0

  role      = aws_iam_role.this.name
  policy_arn = aws_iam_policy.additional[0].arn
}

#---------------------------------------------------------------------------------------------------
# CloudWatch Log group
#---------------------------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.retention_in_days
  kms_key_id        = var.kms_key_id

  tags = var.tags
}

#---------------------------------------------------------------------------------------------------
# Lambda function
#---------------------------------------------------------------------------------------------------

resource "aws_lambda_function" "this" {
  filename         = data.archive_file.source.output_path
  role             = aws_iam_role.this.arn
  source_code_hash = filebase64sha256(var.output_path)

  runtime                        = var.runtime
  handler                        = var.handler
  description                    = var.description
  function_name                  = var.function_name
  memory_size                    = var.memory_size
  reserved_concurrent_executions = var.reserved_concurrent_executions
  layers                         = var.layers
  timeout                        = var.timeout
  publish                        = var.publish

  dynamic "dead_letter_config" {
    for_each = var.dead_letter_config == null ? [] : [var.dead_letter_config]
    content {
      target_arn = dead_letter_config.value.target_arn
    }
  }

  dynamic "environment" {
    for_each = var.environment == null ? [] : [var.environment]
    content {
      variables = environment.value.variables
    }
  }

  dynamic "tracing_config" {
    for_each = var.tracing_config == null ? [] : [var.tracing_config]
    content {
      mode = tracing_config.value.mode
    }
  }

  dynamic "vpc_config" {
    for_each = var.vpc_config == null ? [] : [var.vpc_config]
    content {
      security_group_ids = vpc_config.value.security_group_ids
      subnet_ids         = vpc_config.value.subnet_ids
    }
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [
      filename,
      last_modified
    ]
  }

  depends_on = [aws_iam_role_policy_attachment.basic, aws_iam_role_policy_attachment.vpc[0], aws_cloudwatch_log_group.this]
}

