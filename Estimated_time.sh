#!/bin/bash

#########################################################################################################################
#                                                                                                                       #
#       Author  : SK2                                                                                                   #
#       Date    : 01/07/2024                                                                                            #
#       Purpose : Purpose of this script is to check the estimated time for the boxes which have pending content in EY  #
#                                                                                                                       #
#########################################################################################################################


# Define constants
TOTAL_CONTENT_COUNT=3720
TOTAL_CONTENT_SIZE_GB=323.08
AVG_DOWNLOAD_SPEED_GB_PER_DAY=15
OUTPUT_FILE="output.csv"

# Write the header to the CSV file
echo "BOX,ACDC STATUS,TOTAL CONTENT COUNT,CONTENT COUNT ON THIS BOX,CONTENT COUNT PENDING,TOTAL CONTENT SIZE,CONTENT SIZE ON THE BOX,CONTENT SIZE PENDING,ESTIMATED TIME" > $OUTPUT_FILE

# Read the list of boxes from ank.txt
boxes=$(cat Ey_boxes)

# Loop through each box and fetch data
for box in $boxes; do
    echo "Processing box: $box"

    # Fetch manifest data
    manifest_data=$(curl -s "https://script-user:ug34AD_1TfYajg-23_aMeQt@airfi-disco.herokuapp.com/api/device/$box/content")
    manifest_count=$(echo "$manifest_data" | jq -r '.[] | "\(.manifestId)"' | wc -l)
    total_size=$(echo "$manifest_data" | jq -r '.[] | select(.fileSize != null) | .fileSize' | awk '{s+=$1} END {print s}')

    # Convert total size from bytes to GB
    total_size_gb=$(echo "scale=9; $total_size * 0.000000001" | bc -l)

    # Calculate pending counts and sizes
    content_count_pending=$(($TOTAL_CONTENT_COUNT - $manifest_count))
    content_size_pending_gb=$(echo "scale=9; $TOTAL_CONTENT_SIZE_GB - $total_size_gb" | bc -l)

    # Estimate download time in days and hours
    estimated_time_days=$(echo "scale=2; $content_size_pending_gb / $AVG_DOWNLOAD_SPEED_GB_PER_DAY" | bc -l)
    estimated_time_hours=$(echo "scale=2; ($estimated_time_days - ${estimated_time_days%.*}) * 24" | bc -l)
    estimated_time="${estimated_time_days%.*} days and ${estimated_time_hours%.*} hours"

    # Fetch ACDC status
    acdc_status=$(curl -s "https://script-user:ug34AD_1TfYajg-23_aMeQt@airfi-disco.herokuapp.com/api/device/$box" | jq -r '.contentSyncStatus')

    # Append data to the CSV file
    echo "$box,$acdc_status,$TOTAL_CONTENT_COUNT,$manifest_count,$content_count_pending,$TOTAL_CONTENT_SIZE_GB,$total_size_gb,$content_size_pending_gb,$estimated_time" >> $OUTPUT_FILE
done

echo "Data has been written to $OUTPUT_FILE"
