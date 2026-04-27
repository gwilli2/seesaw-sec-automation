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