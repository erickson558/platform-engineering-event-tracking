provider "aws" {
  region = var.aws_region
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "random_id" "suffix" {
  byte_length = 3
}

resource "aws_s3_bucket" "events" {
  bucket = "${local.name_prefix}-events-${random_id.suffix.hex}"

  tags = merge(var.tags, {
    name = "${local.name_prefix}-events"
  })
}

resource "aws_s3_bucket_public_access_block" "events" {
  bucket = aws_s3_bucket.events.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "events" {
  bucket = aws_s3_bucket.events.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "events" {
  bucket = aws_s3_bucket.events.id

  rule {
    id     = "expire-old-objects"
    status = "Enabled"

    filter {}

    expiration {
      days = 365
    }
  }
}

resource "aws_cloudwatch_log_group" "firehose" {
  name              = "/aws/kinesisfirehose/${local.name_prefix}"
  retention_in_days = 30

  tags = var.tags
}

resource "aws_iam_role" "firehose" {
  name = "${local.name_prefix}-firehose-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "firehose.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "firehose" {
  name = "${local.name_prefix}-firehose-policy"
  role = aws_iam_role.firehose.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.events.arn,
          "${aws_s3_bucket.events.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.firehose.arn}:*"
      }
    ]
  })
}

resource "aws_kinesis_firehose_delivery_stream" "events" {
  name        = "${local.name_prefix}-events"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn           = aws_iam_role.firehose.arn
    bucket_arn         = aws_s3_bucket.events.arn
    buffering_size     = 5
    buffering_interval = 60
    compression_format = "GZIP"

    prefix              = "year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "errors/!{firehose:error-output-type}/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose.name
      log_stream_name = "delivery"
    }
  }

  tags = var.tags
}

resource "aws_iam_role" "lambda" {
  name = "${local.name_prefix}-ingestion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "lambda" {
  name = "${local.name_prefix}-ingestion-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "firehose:PutRecordBatch"
        ]
        Resource = aws_kinesis_firehose_delivery_stream.events.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

data "archive_file" "ingestion_lambda" {
  type        = "zip"
  source_file = "${path.module}/../app/ingestion/handler.py"
  output_path = "${path.module}/build/ingestion_lambda.zip"
}

resource "aws_lambda_function" "ingestion" {
  function_name    = "${local.name_prefix}-ingestion"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  timeout          = 10
  memory_size      = 256
  filename         = data.archive_file.ingestion_lambda.output_path
  source_code_hash = data.archive_file.ingestion_lambda.output_base64sha256

  environment {
    variables = {
      FIREHOSE_STREAM_NAME = aws_kinesis_firehose_delivery_stream.events.name
      AUTH_SHARED_SECRET   = var.api_shared_secret
      MAX_BATCH_SIZE       = "100"
    }
  }

  tags = var.tags
}

resource "aws_apigatewayv2_api" "events" {
  name          = "${local.name_prefix}-events-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_headers = ["content-type", "x-api-key"]
    allow_methods = ["POST", "OPTIONS"]
    allow_origins = ["*"]
    max_age       = 86400
  }

  tags = var.tags
}

resource "aws_apigatewayv2_integration" "ingestion" {
  api_id                 = aws_apigatewayv2_api.events.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.ingestion.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "post_events" {
  api_id    = aws_apigatewayv2_api.events.id
  route_key = "POST /events"
  target    = "integrations/${aws_apigatewayv2_integration.ingestion.id}"
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/apigateway/${local.name_prefix}-events-api"
  retention_in_days = 14

  tags = var.tags
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.events.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api.arn
    format = jsonencode({
      requestId   = "$context.requestId"
      ip          = "$context.identity.sourceIp"
      requestTime = "$context.requestTime"
      routeKey    = "$context.routeKey"
      status      = "$context.status"
      error       = "$context.error.message"
    })
  }

  default_route_settings {
    detailed_metrics_enabled = true
    throttling_burst_limit   = 500
    throttling_rate_limit    = 1000
  }

  tags = var.tags
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingestion.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.events.execution_arn}/*/*"
}

resource "aws_glue_catalog_database" "events" {
  name = replace("${local.name_prefix}_events", "-", "_")
}

resource "aws_glue_catalog_table" "events" {
  name          = "user_events"
  database_name = aws_glue_catalog_database.events.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL             = "TRUE"
    "classification"     = "json"
    "compressionType"    = "gzip"
    "projection.enabled" = "false"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.events.bucket}/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }

    columns {
      name = "event_id"
      type = "string"
    }

    columns {
      name = "event_name"
      type = "string"
    }

    columns {
      name = "event_timestamp"
      type = "string"
    }

    columns {
      name = "source"
      type = "string"
    }

    columns {
      name = "user_id"
      type = "string"
    }

    columns {
      name = "version"
      type = "string"
    }

    columns {
      name = "payload"
      type = "string"
    }

    columns {
      name = "received_at"
      type = "string"
    }
  }

  partition_keys {
    name = "year"
    type = "string"
  }

  partition_keys {
    name = "month"
    type = "string"
  }

  partition_keys {
    name = "day"
    type = "string"
  }
}

resource "aws_athena_workgroup" "events" {
  name = "${local.name_prefix}-athena"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.events.bucket}/athena-results/"
    }
  }

  tags = var.tags
}
