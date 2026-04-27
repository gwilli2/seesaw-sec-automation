import boto3
import json

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    
    # Extract the bucket name from the CloudWatch Event
    bucket_name = event['detail']['requestParameters']['bucketName']
    print(f"Checking security posture for bucket: {bucket_name}")

    # FORCE the bucket to Block All Public Access
    try:
        s3.put_public_access_block(
            Bucket=bucket_name,
            PublicAccessBlockConfiguration={
                'BlockPublicAcl': True,
                'IgnorePublicAcls': True,
                'BlockPublicPolicy': True,
                'RestrictPublicBuckets': True
            }
        )
        return {
            'statusCode': 200,
            'body': json.dumps(f"Security Guardrail Applied: {bucket_name} is now private.")
        }
    except Exception as e:
        print(e)
        raise e