#!/bin/sh

# CouchDB Load Test Script
# This script generates random data and inserts it into a CouchDB database

# Configuration
COUCHDB_URL="http://localhost:5984"
DB_NAME="loadtest_db"
USERNAME="admin"
PASSWORD="password"
NUM_DOCS=1000
BATCH_SIZE=100
DELAY_MS=0  # Delay between batches in milliseconds (0 for no delay)

# Function to check if jq is installed
check_dependencies() {
  if ! command -v jq > /dev/null 2>&1; then
    echo "Error: jq is required but not installed. Please install it first."
    exit 1
  fi
  
  if ! command -v curl > /dev/null 2>&1; then
    echo "Error: curl is required but not installed. Please install it first."
    exit 1
  fi
}

# Function to create the database if it doesn't exist
create_database() {
  echo "Checking if database $DB_NAME exists..."
  
  # Check if database exists
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -u "$USERNAME:$PASSWORD" "$COUCHDB_URL/$DB_NAME")
  
  if [ "$HTTP_STATUS" = "404" ]; then
    echo "Creating database $DB_NAME..."
    curl -X PUT -u "$USERNAME:$PASSWORD" "$COUCHDB_URL/$DB_NAME"
    echo
  elif [ "$HTTP_STATUS" = "200" ]; then
    echo "Database $DB_NAME already exists."
  else
    echo "Error checking database. HTTP Status: $HTTP_STATUS"
    exit 1
  fi
}

# Function to generate a random number in a range
random_range() {
  min=$1
  max=$2
  # Use awk for portable random number generation
  echo $(awk -v min=$min -v max=$max 'BEGIN{srand(); print int(min+rand()*(max-min+1))}')
}

# Function to generate a random document
generate_document() {
  timestamp=$(date +%s)
  # Use multiple values to create more randomness
  random_num1=$(random_range 1000 9999)
  random_num2=$(random_range 1000 9999)
  random_id="${random_num1}${random_num2}${timestamp}"
  
  # Generate random data fields
  name="User_$(random_range 1000 9999)"
  age=$(random_range 18 97)
  score=$(random_range 0 99)
  active=$(random_range 0 1)
  created_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  # Generate a random array of tags
  tags_count=$(random_range 1 5)
  tags="["
  i=0
  while [ $i -lt $tags_count ]; do
    [ $i -gt 0 ] && tags="${tags},"
    tag_num=$(random_range 1 20)
    tags="${tags}\"tag_${tag_num}\""
    i=$((i + 1))
  done
  tags="${tags}]"
  
  # Generate a random nested object
  cat <<EOF
{
  "_id": "$random_id",
  "name": "$name",
  "age": $age,
  "score": $score,
  "active": $([ $active -eq 1 ] && echo "true" || echo "false"),
  "created_at": "$created_at",
  "tags": $tags,
  "profile": {
    "level": $(random_range 1 10),
    "region": "region_$(random_range 1 5)",
    "preferences": {
      "theme": "theme_$(random_range 1 3)",
      "notifications": $([ $(random_range 0 1) -eq 1 ] && echo "true" || echo "false")
    }
  }
}
EOF
}

# Function to insert documents in bulk
insert_bulk_documents() {
  batch_count=$1
  start_index=$2
  end_index=$3
  
  echo "Inserting batch $batch_count (documents $start_index to $end_index)..."
  
  # Create a bulk document
  bulk_doc='{"docs":['
  separator=""
  
  i=$start_index
  while [ $i -le $end_index ]; do
    bulk_doc="${bulk_doc}${separator}$(generate_document)"
    separator=","
    i=$((i + 1))
  done
  
  bulk_doc="${bulk_doc}]}"
  
  # Insert the bulk document
  start_time=$(date +%s)
  response=$(curl -s -X POST -H "Content-Type: application/json" \
                 -u "$USERNAME:$PASSWORD" \
                 -d "$bulk_doc" \
                 "$COUCHDB_URL/$DB_NAME/_bulk_docs")
  end_time=$(date +%s)
  
  # Calculate elapsed time (simpler version without floating point)
  elapsed=$((end_time - start_time))
  echo "Batch completed in $elapsed seconds"
  
  # Check for errors
  if echo "$response" | grep -q "\"error\":"; then
    echo "Error in batch $batch_count: $response"
  fi
}

# Main function
main() {
  check_dependencies
  create_database
  
  # Calculate total batches
  total_batches=$((NUM_DOCS / BATCH_SIZE))
  if [ $((NUM_DOCS % BATCH_SIZE)) -ne 0 ]; then
    total_batches=$((total_batches + 1))
  fi
  
  echo "Starting load test with $NUM_DOCS documents in $total_batches batches..."
  echo "Batch size: $BATCH_SIZE documents"
  
  start_time=$(date +%s)
  
  batch=1
  while [ $batch -le $total_batches ]; do
    start_index=$(( (batch-1) * BATCH_SIZE + 1 ))
    end_index=$(( batch * BATCH_SIZE ))
    [ $end_index -gt $NUM_DOCS ] && end_index=$NUM_DOCS
    
    insert_bulk_documents $batch $start_index $end_index
    
    # Add delay between batches if specified
    if [ $DELAY_MS -gt 0 ]; then
      # For POSIX compatibility, use sleep with whole seconds
      if [ $DELAY_MS -ge 1000 ]; then
        sleep $((DELAY_MS / 1000))
      else
        # For small delays less than 1 second
        sleep 1
      fi
    fi
    
    # Show progress
    progress=$((batch * 100 / total_batches))
    echo "Progress: $progress% ($batch/$total_batches batches)"
    
    batch=$((batch + 1))
  done
  
  end_time=$(date +%s)
  total_time=$((end_time - start_time))
  if [ $total_time -eq 0 ]; then
    total_time=1  # Avoid division by zero
  fi
  docs_per_second=$((NUM_DOCS / total_time))
  
  echo "Load test completed!"
  echo "Inserted $NUM_DOCS documents in $total_time seconds"
  echo "Average throughput: $docs_per_second documents per second"
}

main