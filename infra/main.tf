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