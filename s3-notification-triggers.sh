#!/bin/bash

######################################################

# Author: Ashutosh
# Date: 28/8/24
# version: v0.1

# This script build an event friven system.
# When an object gets uploaded to s3 bucket
# a lambda function gets triggered which then
# sends an email notification to the respective person.

######################################################

set -x

# 1. Store the AWS account ID to a variable
# 2. Print the aws acc id from the variable
aws_account_id=$(aws sts get-caller-identity --query Account --output text)
echo $aws_account_id

# 3. Set AWS region name and bucket name
aws_region="ap-south-1"
bucket_name="ashutosh-pictures"
lambda_func_name="s3-lambda-function"
lambda_func_zip_file="s3-lambda-function.zip"
role_name="s3-lamda-sns"
sns_topic_name="s3-lambda-sns"
email_address="kdashu420@gmail.com"


# 5. Create IAM role for the project
role_response=$(aws iam create-role --role-name $role_name --assume-role-policy-document '{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": [
            "lambda.amazonaws.com",
            "s3.amazonaws.com",
            "sns.amazonaws.com"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}')


# 6.Extract the role arn from the json response and store it in a variable
role_arn=$(echo "${role_response}" | jq -r '.Role.Arn')

# 7.Print the role arn
echo "Role Arn: $role_arn"

# 8.Attach permissions to the role
aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AWSLambda_FullAccess --role-name $role_name
aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonSNSFullAccess --role-name $role_name

# 9.Create the S3 bucket and store the output in a variable
bucket_output=$(aws s3api create-bucket --bucket $bucket_name --create-bucket-configuration LocationConstraint=$aws_region)

# 10.Print the output from the variable
echo "Bucket Name: $bucket_output"

# 11.Copy a file from local to the bucket
aws s3 cp ./example_file.txt s3://$bucket_name/example_file_test.txt

# 12.create a zip file to upload lambda function
zip -r $lambda_func_zip_file ./s3-lambda-function

sleep 5

# 13.Create a lambda function
aws lambda create-function \
    --region "$aws_region" \
    --function-name $lambda_func_name \
    --runtime "python3.8" \
    --zip-file fileb://$lambda_func_zip_file \
    --handler "s3-lambda-function/s3-lambda-function.lambda_handler" \
    --timeout 30 \
    --role arn:aws:iam::$aws_account_id:role/$role_name

# 14.Permissions to s3 Bucket to invoke lambda
aws lambda add-permission \
    --function-name $lambda_func_name \
    --action lambda:InvokeFunction \
    --statement-id s3-lambda-s3 \
    --principal s3.amazonaws.com \
    --source-arn "arn:aws:s3:::$bucket_name"

# 15.Create an S3 event trigger for the lambda function
LambdaFunctionArn="arn:aws:lambda:$aws_region:$aws_account_id:function:$lambda_func_name"
aws s3api put-bucket-notification-configuration \
    --bucket $bucket_name \
    --region $aws_region \
    --notification-configuration '{
    "LambdaFunctionConfigurations": [{
        "LambdaFunctionArn": "'"$LambdaFunctionArn"'",
        "Events": ["s3:ObjectCreated:*"]
    }]
}'

# 16.Create an SNS topic and save the sns topic to a variable
sns_topic_arn=$(aws sns create-topic --name $sns_topic_name --output json | jq -r '.TopicArn')

# 17.Print the topic arn
echo "SNS Topic ARN: $sns_topic_arn"

# 18.Trigger SNS Topic using lambda function

# 19.Add SNS publish permissions to the lambda function
aws sns subscribe \
    --topic-arn $sns_topic_arn \
    --protocol email \
    --notification-endpoint "$email_address"

# 20.Publish the sns
aws sns publish \
    --topic-arn "$sns_topic_arn" \
    --subject "A new object created in s3 bucket" \
    --message "Hello from Ashutosh. A new object is being created in your s3 bucket $bucket_name"