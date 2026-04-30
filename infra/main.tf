provider "aws" {
  region = "us-east-1"
}

# 1. Create the S3 Bucket we want to protect
resource "aws_s3_bucket" "secure_storage" {
  bucket = "gregory-secure-data-lab-001" # Must be unique
}

# 2. Create the IAM Role for our Python Lambda
resource "aws_iam_role" "guardian_role" {
  name = "S3GuardianRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# 3. Add permissions to the role (Least Privilege)
resource "aws_iam_role_policy" "guardian_policy" {
  role = aws_iam_role.guardian_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:PutPublicAccessBlock", "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "*"
    }]
  })
}

# 1. Create a "Sensor" that listens for S3 configuration changes
resource "aws_cloudwatch_event_rule" "s3_change_sensor" {
  name        = "s3-change-sensor"
  description = "Triggers when an S3 bucket's public access settings change"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail_type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["s3.amazonaws.com"]
      eventName   = ["PutBucketPublicAccessBlock"]
    }
  })
}

# 2. Connect the Sensor to your Python Lambda
resource "aws_cloudwatch_event_target" "trigger_lambda" {
  rule      = aws_cloudwatch_event_rule.s3_change_sensor.name
  target_id = "S3Guardian"
  arn       = aws_lambda_function.s3_guardian.arn # Ensure this name matches your lambda resource name
}

# 3. Give the Sensor permission to "invoke" (call) the Lambda
resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_guardian.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.s3_change_sensor.arn
}

# This block tells Terraform to zip up your Python script
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../scripts/guardian.py"
  output_path = "${path.module}/guardian.zip"
}

# This block creates the actual Lambda function in AWS
resource "aws_lambda_function" "s3_guardian" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "s3_guardian"
  role             = aws_iam_role.guardian_role.arn
  handler          = "guardian.lambda_handler" # This must match your filename and function name
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.12"

  depends_on = [aws_iam_role_policy.guardian_policy]
}

# 1. Create a bucket to store the logs (CloudTrail requirement)
resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket        = "gregory-trail-logs-unique-id" # Change to a unique name
  force_destroy = true
}

# 2. Create the Trail to monitor the S3 bucket
resource "aws_cloudtrail" "s3_monitor" {
  name                          = "s3-management-events"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.id
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_log_file_validation    = true

  event_selector {
    read_write_type           = "WriteOnly"
    include_management_events = true
  }
}

resource "aws_s3_bucket_policy" "allow_cloudtrail_logging" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail_logs.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_logs.arn}/AWSLogs/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      }
    ]
  })
}