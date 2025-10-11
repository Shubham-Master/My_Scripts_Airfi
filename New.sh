#!/bin/bash

# Script Information
################################################################################################
#     Author: SK2                                                                              #
#     Date: 25-01-2023                                                                         #
#     Purpose: Check for the latest Firmware of a BOX                                          #
################################################################################################

# Output CSV file
output_file="DSD_Firmware.csv"
echo "BOX_IP,LATEST_FIRMWARE_VERSION" > "$output_file"

# Function to extract the latest firmware version from the last log file
extract_latest_firmware_version() {
    local ip=$1
    # Find the last log file for the box
    local last_log=$(find /logs/$ip -type f -name "logfile-airfi-*" | sort -r | head -1)
    
    # Extract the latest firmware version from the last log file
    local latest_firmware_version=$(zgrep -m 1 "SWver" "$last_log" | awk '{print $NF}')
    echo $latest_firmware_version
}

# Read boxes from DSD_Boxes and process
while IFS= read -r box; do
    # Display progress
    echo "Processing Box: $box"
    
    # Extract the latest firmware version for the box
    latest_firmware_version=$(extract_latest_firmware_version "$box")
    
    # Write box IP and the latest firmware version to the output CSV file
    echo "$box,$latest_firmware_version" >> "$output_file"
done < "DSD_Boxes"

# Display completion message
echo "Total number of boxes processed: $(wc -l < "DSD_Boxes")"
echo "Latest firmware extraction completed. Output saved in $output_file."
