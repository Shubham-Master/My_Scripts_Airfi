#!/bin/bash

# Database credentials
DB_USER="admin"
DB_PASS="V3ryS3cur3"
DB_INSTALLED_MANIFESTS="installed-manifests-6e"
DB_AIRFI_MASTER="airfi-master-6e"
DHCP_FILE="/tmp/dhcp.lan*"

# Function to fetch _rev and delete a document by ID via SSH
fetch_and_delete_document() {
  local db=$1
  local doc_id=$2
  local ip=$3

  echo "Fetching _rev for document: $doc_id from $db on $ip"
  # SSH into the remote machine and fetch the _rev value using jq
  rev=$(ssh root@$ip "curl -s -u $DB_USER:$DB_PASS http://localhost:5984/$db/$doc_id | jq -r '._rev'")

  if [ ! -z "$rev" ]; then
    echo "Fetched revision: $rev from $ip"
    echo "Deleting document: $doc_id from $db with revision $rev on $ip"
    # SSH into the remote machine and delete the document
    delete_result=$(ssh root@$ip "curl -s -X DELETE -u $DB_USER:$DB_PASS http://localhost:5984/$db/$doc_id?rev=$rev")
    if echo "$delete_result" | grep -q '"ok":true'; then
      echo "Deleted $doc_id from $db on $ip"
      return 0
    else
      echo "Failed to delete $doc_id from $db on $ip: $delete_result"
      return 1
    fi
  else
    echo "Document $doc_id not found in $db on $ip or _rev field missing"
    return 1
  fi
}

# Function to retry fetching the document if the host is unreachable
retry_fetch_and_delete() {
  local db=$1
  local doc_id=$2
  local ip=$3
  local max_retries=3
  local retry_count=0

  while [ $retry_count -lt $max_retries ]; do
    fetch_and_delete_document "$db" "$doc_id" "$ip"
    if [ $? -eq 0 ]; then
      return 0
    fi
    echo "Retrying... ($((retry_count + 1))/$max_retries) for $ip"

    retry_count=$((retry_count + 1))
    sleep 5
  done
  echo "Failed to fetch and delete document after $max_retries attempts on $ip"
  return 1
}

# Read product IDs from product_id.txt and iterate over them
while IFS= read -r product_id; do
  # Read IP addresses from DHCP file and iterate over them
  for ip in $(awk '{print $3}' $DHCP_FILE); do
    # First try to delete from installed manifests
    if retry_fetch_and_delete "$DB_INSTALLED_MANIFESTS" "$product_id" "$ip"; then
      echo "Successfully deleted $product_id from $DB_INSTALLED_MANIFESTS on $ip"
    else
      # If not found in installed manifests, try to delete from master
      if retry_fetch_and_delete "$DB_AIRFI_MASTER" "$product_id" "$ip"; then
        echo "Successfully deleted $product_id from $DB_AIRFI_MASTER on $ip"
      else
        echo "Failed to delete $product_id from both $DB_INSTALLED_MANIFESTS and $DB_AIRFI_MASTER on $ip"
      fi
    fi
  done
done < /media/product_id.txt
