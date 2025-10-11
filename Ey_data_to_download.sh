#!/bin/bash

# File containing the list of IP addresses
box_file="Ey_boxes"

# Constants
total_bytes=325813204446
bytes_per_gb=1073741824
base_url="https://script-user:ug34AD_1TfYajg-23_aMeQt@airfi-disco.herokuapp.com/api/device/"

# Initialize arrays to store results
auto_boxes=()
standalone_boxes=()
proxy_boxes=()

# Loop through each IP in the file
while IFS= read -r ip; do
  # Fetch the data
  response=$(curl -s "${base_url}${ip}")

  # Extract contentSizeInBytes and mode.name separately
  content_size_bytes=$(echo "$response" | jq -r '.contentSizeInBytes')
  mode_name=$(echo "$response" | jq -r '.mode.name')

  # Subtract from total_bytes and convert to GB
  difference_bytes=$((total_bytes - content_size_bytes))
  difference_gb=$(echo "scale=2; $difference_bytes / $bytes_per_gb" | bc)

  # Format the result
  result="Box Serial: $ip -> Difference: ${difference_gb} GB, Mode: $mode_name"

  # Store result in appropriate array based on mode
  case $mode_name in
    AUTO)
      auto_boxes+=("$result")
      ;;
    STANDALONE)
      standalone_boxes+=("$result")
      ;;
    PROXY)
      proxy_boxes+=("$result")
      ;;
    *)
      echo "Unknown mode: $mode_name for IP: $ip"
      ;;
  esac
done < "$box_file"

# Print sorted results
echo "AUTO Boxes:"
for box in "${auto_boxes[@]}"; do
  echo "$box"
done

echo ""
echo "STANDALONE Boxes:"
for box in "${standalone_boxes[@]}"; do
  echo "$box"
done

echo ""
echo "PROXY Boxes:"
for box in "${proxy_boxes[@]}"; do
  echo "$box"
done
