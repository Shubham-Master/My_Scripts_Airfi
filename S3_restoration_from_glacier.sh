#!/bin/bash
# Author: SK2
# Purpose: Restore Deep Archive objects in S3 to Standard for processing.

BUCKET="airserver-backups"
INPUT_FILE="/home/ubuntu/logs_only.txt"
LOG_FILE="/home/ubuntu/restore_status.log"
PROCESSED_LIST="/home/ubuntu/processed_objects.txt"

# How many days to keep the restored copy available
DAYS_TO_KEEP=60

# Control concurrency (number of parallel restores)
MAX_JOBS=20

echo "Starting restore requests at $(date)"
echo "Logging progress to $LOG_FILE"
> "$LOG_FILE"
touch "$PROCESSED_LIST"

# Function to restore one object
restore_object() {
  FULL_KEY="$1"

  if grep -Fxq "$FULL_KEY" "$PROCESSED_LIST"; then
    echo "Skipping already processed: s3://$BUCKET/$FULL_KEY" >> "$LOG_FILE"
    return
  fi

  echo "Restoring: s3://$BUCKET/$FULL_KEY" >> "$LOG_FILE"

  if aws s3api restore-object \
    --bucket "$BUCKET" \
    --key "$FULL_KEY" \
    --restore-request "Days=$DAYS_TO_KEEP,GlacierJobParameters={Tier=Bulk}" \
    >> "$LOG_FILE" 2>&1; then
      echo "$(date): SUCCESS - $FULL_KEY" >> "$LOG_FILE"
      echo "$FULL_KEY" >> "$PROCESSED_LIST"
  else
      echo "$(date): FAILED  - $FULL_KEY" >> "$LOG_FILE"
  fi
}

export -f restore_object
export BUCKET DAYS_TO_KEEP LOG_FILE PROCESSED_LIST

# Process in parallel (GNU parallel is fastest)
cat "$INPUT_FILE" | parallel -j "$MAX_JOBS" restore_object {}

echo "All restore requests submitted at $(date)"


