#!/bin/bash

#########################################################################################################################
#                                                                                                                       #
#       Author  : SK2                                                                                                   #
#       Date    : 12/07/2023                                                                                            #
#       Purpose : Purpose of this script is to check the box loaded charge and charge at the end of everyday along      #
#                 the PMIC reason also it checkes the shutdwon reason and charge of intermediate logs                   #                                                                    #
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

# Function to find shutdown reason
find_shutdown_reason() {
    local log=$1
    local reason="ABRUPT"  # Default reason

    pmic_reason=$(zgrep 'PMIC' $log | tail -n 1)
    telemetry_action=$(zgrep 'TELEMETRY_ACTION' $log | tail -n 1)
    rck_reason=$(zgrep 'rcK' $log | tail -n 1)

    if [ -n "$pmic_reason" ]; then
        reason=$pmic_reason
    elif [ -n "$telemetry_action" ]; then
        reason=$telemetry_action
    fi

    echo "$reason"
}

# Process logs for each box IP ending
for ip_ending in "${box_ip_endings[@]}"; do
    echo -e "\n\n----------------------------------------"
    echo "Checking logs for Box IP: $IP_PREFIX.$ip_ending"
    echo "----------------------------------------"

    full_box_ip="$IP_PREFIX.$ip_ending"

    # Process each log file
    for date in $(ls /logs/$full_box_ip/$LOG_PATTERN 2>/dev/null | cut -d'-' -f3 | cut -d'_' -f1 | sort | uniq); do
        log_files=( $(ls /logs/$full_box_ip/logfile-airfi-${date}_*.gz 2>/dev/null) )
        log_count=${#log_files[@]}

        if [ "$log_count" -gt 0 ]; then
            first_log=${log_files[0]}
            last_log=${log_files[-1]}

            echo -e "\n========================="
            echo "Date: $date"
            echo "========================="
            echo "Reading from first log: $first_log"
            zgrep -m 1 'charge=' $first_log

            echo "Reading from last log: $last_log"
            last_shutdown_reason=$(find_shutdown_reason "$last_log")
            echo "Shutdown reason: $last_shutdown_reason"
            zgrep 'charge=' $last_log | tail -n 1

            total_start_time=$(echo "$first_log" | grep -oP '\d{8}_\d{6}' | head -1)
            total_end_time=$(echo "$last_log" | grep -oP '\d{8}_\d{6}' | tail -1)
            total_duration=$(calculate_duration "$total_start_time" "$total_end_time")
            echo "Total log duration: $total_duration hours"
            echo

            # Process each log file for shutdown reasons and charge states
            for (( i=1; i<${#log_files[@]}; i++ )); do
                log=${log_files[$i]}
                prev_log=${log_files[$i-1]}
                
                shutdown_reason=$(find_shutdown_reason "$log")
                first_charge=$(zgrep -m 1 'charge=' $log)
                nearest_charge=$(zgrep 'charge=' $log | tail -n 1)

                log_start_time=$(echo "$prev_log" | grep -oP '\d{8}_\d{6}' | head -1)
                log_end_time=$(echo "$log" | grep -oP '\d{8}_\d{6}' | head -1)
                log_duration=$(calculate_duration "$log_start_time" "$log_end_time")

                echo "Intermediate log: $log"
                echo "Shutdown reason: $shutdown_reason"
                echo "First charge: $first_charge"
                echo "Nearest charge: $nearest_charge"
                echo "Log duration: $log_duration hours"
                echo
            done
            echo "Total number of logs checked for date $date: $log_count"
        else
            echo "No logs found for date: $date"
        fi
    done
done
