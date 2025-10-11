#!/bin/bash


################################################################################################
#     Author: SK2                                                                              #
#     Date: 23-05-2025                                                                         #
#     Purpose: Retrieves logs from S3, for selcted dates and and put it in the box serial      #
#                        DIR                                                                  #
################################################################################################


#!/bin/bash

# Prompt for inputs
read -p "Enter last two octets of the serial (e.g., 25.115): " ip_suffix
read -p "Enter start date (YYYYMMDD): " start_date
read -p "Enter end date (YYYYMMDD): " end_date

# Define paths
local_dir="/logs/10.0.$ip_suffix"
s3path="s3://airserver-backups/logs/10.0.$ip_suffix"

# Check if local directory exists
if [ ! -d "$local_dir" ]; then
  echo "❌ Box directory $local_dir does not exist"
  exit 1
fi

# Validate date range
if [[ "$start_date" -gt "$end_date" ]]; then
  echo "❌ Start date must be less than or equal to end date"
  exit 1
fi

echo "🔍 Fetching logs from $start_date to $end_date for 10.0.$ip_suffix"

# Build regex for date pattern
rinclude_pattern="logfile-airfi-($(seq -f "%08.0f" $start_date $end_date | tr '\n' '|' | sed 's/|$//'))"

# Change to target dir and fetch logs
cd "$local_dir"
s3cmd get -c /home/ubuntu/.s3cfg --recursive --rinclude "$rinclude_pattern" "$s3path"

echo "✅ Done. Logs copied to $local_dir"
