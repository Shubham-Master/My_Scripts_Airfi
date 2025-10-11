#!/bin/bash

# Define the S3 buckets and paths
s3_buckets=("s3://streamingbuzz-ey/Deployed/ey/" "s3://anuvu-ey/Deployed/ey/")

# Get the current date and calculate the current month and the past two months
current_date=$(date +%Y-%m-%d)
current_month=$(date +%Y-%m)
last_month=$(date -v -1m +%Y-%m)
two_months_ago=$(date -v -2m +%Y-%m)

# Temporary file to store results
temp_file=$(mktemp)

# Function to process a bucket
process_bucket() {
  local bucket=$1
  local bucket_name=$2

  # List files and filter by date
  aws s3 ls $bucket --recursive > "$temp_file"

  # Process the temporary file to sum sizes by date
  awk -v cm="$current_month" -v lm="$last_month" -v tma="$two_months_ago" -v bucket_name="$bucket_name" '
  {
    date = $1;
    size = $3;
    month = substr(date, 1, 7);
    if (month == cm || month == lm || month == tma) {
      sizes[date] += size;
    }
  }
  END {
    for (date in sizes) {
      size_gb = sizes[date] / 1073741824;
      printf "%s %s %.6f\n", bucket_name, date, size_gb;
    }
  }
  ' "$temp_file" >> "$temp_file.processed"
}

# Process each bucket
process_bucket "s3://streamingbuzz-ey/Deployed/ey/" "Streamingbuzz"
process_bucket "s3://anuvu-ey/Deployed/ey/" "Anuvu"

# Print the results
echo "Streamingbuzz EY Bucket (Updated on $current_date):"
grep "Streamingbuzz" "$temp_file.processed" | awk '{printf "Total File Size on %s: %.6f GB\n", $2, $3}'

echo ""
echo "Anuvu EY Bucket (Updated on $current_date):"
grep "Anuvu" "$temp_file.processed" | awk '{printf "Total File Size on %s: %.6f GB\n", $2, $3}'

# Clean up
rm "$temp_file" "$temp_file.processed"
