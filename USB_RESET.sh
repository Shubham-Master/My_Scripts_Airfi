#!/bin/bash

#########################################################################################################################
#                                                                                                                       #
#       Author  : SK2                                                                                                   #
#       Date    : 22/12/2023                                                                                            #
#       Purpose : The purpose of this script is to check for the occurrence of the "failure_usbreset" event in logs.    #
#                                                                                                                       #
#########################################################################################################################

# User input
read -p "Enter the last two segments of Box IPs (separated by space, e.g., 9.102 11.226): " -a box_ip_endings

# Define log patterns using the provided date range
LOG_PATTERN_MAINTENANCE="logfile-maintenance-*.gz"
LOG_PATTERN_AIRFI="logfile-airfi-*.gz"

# Prefix for the common part of the box IP
IP_PREFIX="10.0"

# Function to process log files
process_logs() {
    local log_pattern=$1
    for ip_ending in "${box_ip_endings[@]}"; do
        echo -e "\n\n----------------------------------------"
        echo "Checking logs for Box IP: $IP_PREFIX.$ip_ending"
        echo "----------------------------------------"

        full_box_ip="$IP_PREFIX.$ip_ending"
        occurrence_count=0
        logfile_count=0
        total_logfile_checked=0

        # Count all log files for the current Box IP
        for log_file in /logs/$full_box_ip/$log_pattern; do
            if [ -f "$log_file" ]; then
                total_logfile_checked=$((total_logfile_checked + 1))
            fi
        done

        # Process each log file
        for log in /logs/$full_box_ip/$log_pattern; do
            if [ -f "$log" ]; then
                echo "Checking file: $log"
                # Process log with grep
                occurrences=$(zcat "$log" | grep "failure_usbreset")
                if [ -n "$occurrences" ]; then
                    echo "$occurrences"
                    logfile_count=$((logfile_count + 1))
                    occurrence_count=$(($(echo "$occurrences" | grep -c "failure_usbreset") + occurrence_count))
                fi
            fi
        done

        echo -e "Total occurrences of 'failure_usbreset' for Box IP $full_box_ip: $occurrence_count in $logfile_count logfiles (out of $total_logfile_checked checked)"
        echo -e "----------------------------------------\n\n"
    done
}

# Process both maintenance and airfi logs
process_logs "$LOG_PATTERN_MAINTENANCE"
process_logs "$LOG_PATTERN_AIRFI"