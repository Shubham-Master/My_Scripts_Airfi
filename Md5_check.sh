#!/bin/bash

# Prompt the user for required variables
read -p "Enter your S3 bucket name: " S3_BUCKET
read -p "Enter the S3 file name (including path within the bucket): " S3_FILE

# Set the local file path
LOCAL_FILE="/Users/sk2/Desktop/Shubham/AWS_Downloads/$(basename $S3_FILE)"

# Download the file from S3
aws s3 cp s3://$S3_BUCKET/$S3_FILE $LOCAL_FILE > /dev/null 2>&1

# Calculate the MD5 checksum
MD5_SUM=$(md5 -q $LOCAL_FILE)

# Calculate the SHA-256 checksum
SHA256_SUM=$(shasum -a 256 $LOCAL_FILE | awk '{print $1}')

# Get the file size
FILE_SIZE=$(stat -f%z "$LOCAL_FILE")

echo "MD5 checksum: $MD5_SUM"
echo "SHA-256 checksum: $SHA256_SUM"
echo "File size: $FILE_SIZE bytes"
