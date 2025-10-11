#!/bin/bash

read -p "Enter S3 bucket name: " BUCKET_NAME
read -p "Enter IATA (in capital): " IATA
read -p "Enter cost allocation (AirFi/CC): " COST_ALLOCATION
read -p "Enter user stack (production/staging): " USER_STACK
read -p "Enter content provider (i.e. AirFi/streamingbuzz): " PROVIDER
read -p "Cloudformation stack name (of your choice): " STACK_NAME

TEMPLATE_FILE="S3BucketProd.yml"

if [[ "$USER_STACK" == "staging" ]];then
	TEMPLATE_FILE="S3BucketStaging.yml"
fi

if aws cloudformation create-stack --template-body file://${TEMPLATE_FILE} --parameters ParameterKey=S3BucketName,ParameterValue="${BUCKET_NAME}" ParameterKey=S3IATA,ParameterValue="${IATA}" ParameterKey=S3CostAlloc,ParameterValue="${COST_ALLOCATION}" ParameterKey=S3UserStack,ParameterValue="${USER_STACK}" ParameterKey=S3Provider,ParameterValue="${PROVIDER}" --stack-name "${STACK_NAME}";then
  echo "Stack ${STACK_NAME} is created successfully. Please check if bucket ${BUCKET_NAME} is created in S3."
else
  echo "The stack creation failed"
fi
