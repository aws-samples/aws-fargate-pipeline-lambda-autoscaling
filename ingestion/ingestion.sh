#!/bin/bash

echo "$(date) Running ECS PIPELINE Task"
TASK_ARN=$(curl -s 169.254.170.2/v2/metadata | jq -r '.TaskARN')
echo "$(date) TASK_ARN=$TASK_ARN"

# This property is set on the ECS environment, not SSM (unlike every other property)
if [ -z "$PIPELINE_ECS_JOB_MODE" ]; then
  PIPELINE_ECS_JOB_MODE="0"
fi
echo "$(date) PIPELINE_ECS_JOB_MODE=$PIPELINE_ECS_JOB_MODE"

service sshd start

# Get SSM parameters and export them here
$(aws ssm get-parameters --with-decryption --names PIPELINE_S3_DEST_BUCKET PIPELINE_S3_DEST_PREFIX PIPELINE_UNPROCESSED_SQS_URL |  jq -r '.Parameters| .[] | "export " + .Name + "=" + .Value ')

echo "PIPELINE_UNPROCESSED_SQS_URL=$PIPELINE_UNPROCESSED_SQS_URL"

echo "PIPELINE_S3_DEST_BUCKET=$PIPELINE_S3_DEST_BUCKET"
echo "PIPELINE_S3_DEST_PREFIX=$PIPELINE_S3_DEST_PREFIX"

echo "ECS Pipeline running in folder: $(pwd)"

# Setup Preprocessor folders
mkdir -p output/
mkdir -p work/
mkdir -p logs/

while [ /bin/true ]; do

  # Check if Preprocessor is enabled
  $(aws ssm get-parameters --with-decryption --names PIPELINE_ENABLED |  jq -r '.Parameters| .[] | "export " + .Name + "=" + .Value ')

  if [ $PIPELINE_ENABLED -eq 0 ]; then
    msg="None"
    echo "$(date) PIPELINE_ENABLED operation is DISABLED. Sleeping for 60 seconds."
    sleep 60
  else
    msg=$( \
      aws sqs receive-message \
          --queue-url $PIPELINE_UNPROCESSED_SQS_URL \
          --wait-time-seconds 20 \
          --output text \
          --query Messages[0].[Body,ReceiptHandle] \
          --visibility-timeout 300
    )
  fi

  if [ -z "${msg}" -o "${msg}" = "None" ]; then
    if [ $PIPELINE_ECS_JOB_MODE -eq 1 ]; then
      echo "$(date) Processing complete. Stopping task."
      exit
    else
      echo "$(date) No files available to process. Retrying."
      sleep 1
    fi
  else
    echo "$(date) SQS Message: ${msg}"
    sqs_message=$(echo "${msg}" | cut -f1 --)
    echo "${sqs_message}" > work/sqs_message.json

    receipt_handle=$(echo "${msg}" | cut -f2 --)

    s3_bucket=$(echo "${sqs_message}" | jq -r '.Records[0].s3.bucket.name')
    s3_key=$(echo "${sqs_message}" | jq -r '.Records[0].s3.object.key')
    s3_path="s3://${s3_bucket}/${s3_key}"
    s3_file=$(basename ${s3_key})
    s3_file_no_ext=$(basename ${s3_file} .jpg)
    echo "$(date) Received SQS upload message: bucket: $s3_bucket key: $s3_key file: $s3_file"

    aws s3 cp ${s3_path} work/ --sse aws:kms > logs/s3get.log 2>&1

    echo "$(date) Running PIPELINE Preprocessor"
    $(python python/preprocess_job.py work/${s3_file} output/${s3_file_no_ext}_processed.jpg >>logs/pipeline.log 2>&1)
    CMD_EXIT=$?

    if [ $CMD_EXIT -eq 0 ]; then
        echo "$(date) PIPELINE Preprocessor SUCCESS" >> logs/pipeline.log
        aws s3 sync output/ s3://$PIPELINE_S3_DEST_BUCKET/$PIPELINE_S3_DEST_PREFIX/processed/date=$(date +%Y-%m-%d)/
        aws s3 cp logs/pipeline.log s3://$PIPELINE_S3_DEST_BUCKET/$PIPELINE_S3_DEST_PREFIX/logs/date=$(date +%Y-%m-%d)/${s3_file}.success
    else
        echo "$(date) PIPELINE Preprocessor FAILURE" >> logs/pipeline.log
        aws s3 cp logs/pipeline.log s3://$PIPELINE_S3_DEST_BUCKET/$PIPELINE_S3_DEST_PREFIX/logs/date=$(date +%Y-%m-%d)/${s3_file}.failure
    fi

    # Clean up temp folders
    rm -rf output/*
    rm -rf work/*
    rm -rf logs/*

    aws sqs delete-message \
        --queue-url $PIPELINE_UNPROCESSED_SQS_URL \
        --receipt-handle ${receipt_handle}

    echo "$(date) Processing complete for ${sqs_message}"

  fi
done
exit
