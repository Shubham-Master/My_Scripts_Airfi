#!/bin/bash

#########################################################################################################################
#                                                                                                                       #
#       Author  : SK2                                                                                                   #
#       Date    : 06/06/2023                                                                                            #
#       Purpose : Purpose of this script is to check the box loaded charge and charge at the end of everyday along      #
#                 the PMIC reason                                                                                       #
#                                                                                                                       #
#########################################################################################################################

# User inputs
read -p "Enter month to check in yyyymm format: " month
read -p "Enter the last two segments of Box IPs (separated by space, e.g., 9.102 11.226): " -a box_ip_endings

# Define log pattern using the provided month
LOG_PATTERN="logfile-airfi-$month*.gz"

# Prefix for the common part of the box IP
IP_PREFIX="10.0"

# Function to calculate log duration
calculate_duration() {
    local start_time=$1
    local end_time=$2

    local start_date=$(date -d "${start_time:0:4}-${start_time:4:2}-${start_time:6:2} ${start_time:9:2}:${start_time:11:2}:${start_time:13:2}" +%s)
    local end_date=$(date -d "${end_time:0:4}-${end_time:4:2}-${end_time:6:2} ${end_time:9:2}:${end_time:11:2}:${end_time:13:2}" +%s)

    local duration=$(echo "scale=2;($end_date - $start_date) / 3600" | bc -l)
    echo "$duration"
}

# Process logs for each box IP ending
for ip_ending in "${box_ip_endings[@]}"; do
    echo -e "\n\n----------------------------------------"
    echo "Checking logs for Box IP: $IP_PREFIX.$ip_ending"
    echo "----------------------------------------"

    full_box_ip="$IP_PREFIX.$ip_ending"

    # Process each log file
    for date in $(ls /logs/$full_box_ip/$LOG_PATTERN 2>/dev/null | cut -d'-' -f3 | cut -d'_' -f1 | sort | uniq); do
        first_log=$(ls /logs/$full_box_ip/logfile-airfi-${date}_*.gz 2>/dev/null | head -n 1)
        last_log=$(ls /logs/$full_box_ip/logfile-airfi-${date}_*.gz 2>/dev/null | tail -n 1)

        if [ -n "$first_log" ] && [ -n "$last_log" ]; then
            start_time=$(echo "$first_log" | grep -oP '\d{8}_\d{6}' | head -1)
            end_time=$(echo "$last_log" | grep -oP '\d{8}_\d{6}' | tail -1)
            duration=$(calculate_duration "$start_time" "$end_time")

            echo "Date: $date"
            echo "Reading from first log: $first_log"
            zgrep -m 1 'charge=' $first_log
            echo "Reading from last log: $last_log"
            zgrep 'PMIC' $last_log | tail -n 1
            zgrep 'charge=' $last_log | tail -n 1
            echo "Total log duration: $duration hours"
            echo
        else
            echo "No logs found for date: $date"
        fi
    done
done