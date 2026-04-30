output "api_base_url" {
  description = "Base URL for the events ingestion API"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "s3_events_bucket" {
  description = "S3 bucket where raw user events are stored"
  value       = aws_s3_bucket.events.bucket
}

output "firehose_stream_name" {
  description = "Firehose stream receiving validated events"
  value       = aws_kinesis_firehose_delivery_stream.events.name
}

output "athena_workgroup" {
  description = "Athena workgroup for analytics users"
  value       = aws_athena_workgroup.events.name
}

output "glue_database" {
  description = "Glue database used by downstream data teams"
  value       = aws_glue_catalog_database.events.name
}
