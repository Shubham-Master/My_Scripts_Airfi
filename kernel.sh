#!/bin/bash

# Script Information
################################################################################################
#     Author: SK2                                                                              #
#     Date: 03-06-2024                                                                         #
#     Purpose: Check for kernel NULL pointer errors in the logs of a BOX                       #
################################################################################################

# Output CSV file
output_file="Kernel_Null_Pointer_Errors.csv"
echo "BOX,LOGFILE" > "$output_file"

# Function to check for kernel NULL pointer errors in the logs
check_log_info() {
    local ip=$1
    # Find the log files for the box
    local log_files=$(find /logs/$ip -type f -name "logfile-airfi-*")

    # Check if log files exist
    if [ -z "$log_files" ]; then
        echo "No log files found for BOX $ip"
        return
    fi

    # Process each log file
    for log_file in $log_files; do
        echo "Processing log file: $log_file"  # Debug statement

        # Check for "Unable to handle kernel NULL pointer" in the log file
        if zcat "$log_file" | grep -iq "Unable to handle kernel NULL pointer" ; then
            # Extract log file name
            local log_name=$(basename "$log_file")
            echo "Log name: $log_name"  # Debug statement

            # Output the box IP and log file name
            echo "$ip,$log_name" >> "$output_file"
        else
            echo "No kernel NULL pointer error found in log file for BOX $ip"
        fi
    done
}

# Read boxes from 6E_Pod_boxes.txt and process
while IFS= read -r box; do
    # Display progress
    echo "Processing Box: $box"

    # Check log info for the box
    check_log_info "$box"
done < "6E_Pod_boxes.txt"

# Display completion message
echo "Total number of boxes processed: $(wc -l < "6E_Pod_boxes.txt")"
echo "Kernel NULL pointer error extraction completed. Output saved in $output_file."