#!/bin/bash


# List of IP addresses
ips=(
  "10.0.14.37"
  "10.0.14.212"
  "10.0.12.235"
  "10.0.10.208"
  "10.0.8.11"
  "10.0.14.250"
  "10.0.7.27"

)

# Constants
total_bytes=323076499335
bytes_per_gb=1073741824
base_url="https://script-user:ug34AD_1TfYajg-23_aMeQt@airfi-disco.herokuapp.com/api/device/"

# Loop through each IP
for ip in "${ips[@]}"; do

  # Fetch the data
  response=$(curl -s "${base_url}${ip}")

  # Extract contentSizeInBytes and serial
  content_size_bytes=$(echo "$response" | jq -r '.contentSizeInBytes')
   
 # serial=$(echo "$response" | grep -oP '(?<="serial":")[^"]*')

  # Subtract from total_bytes and convert to GB
  difference_bytes=$((total_bytes - content_size_bytes))
  difference_gb=$(echo "scale=2; $difference_bytes / $bytes_per_gb" | bc)

  # Print the result
  echo "Box Serial: $ip -> Difference: ${difference_gb} GB"
done