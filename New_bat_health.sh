#!/bin/bash

#########################################################################################################################
#                                                                                                                       #
#       Author  : SK2                                                                                                   #
#       Date    : 26/06/2024                                                                                            #
#       Purpose : Purpose of this script is to check the PMIC_BATTERY_LOW event occurrence                              #
#                  in logs and at which charge with duration of each log.                                               #
#                                                                                                                       #
#########################################################################################################################

# User inputs
read -p "Enter month to check in yyyymm format: " month
read -p "Enter the last two segments of Box IPs (separated by space, e.g., 9.102 11.226): " -a box_ip_endings

# Define log pattern using the provided month
LOG_PATTERN="logfile-airfi-$month*.gz"

# Prefix for the common part of the box IP
IP_PREFIX="10.0"

# Function to calculate duration
calculate_duration() {
    start_time=$1
    end_time=$2

    # Convert timestamps to seconds from the epoch
    start_seconds=$(date -d "$start_time" +%s)
    end_seconds=$(date -d "$end_time" +%s)

    # Calculate the difference in seconds
    duration_seconds=$((end_seconds - start_seconds))

    # Convert seconds to hours and minutes
    hours=$(($duration_seconds / 3600))
    minutes=$((($duration_seconds % 3600) / 60))

    echo "$hours hours and $minutes minutes"
}

# awk script for processing logs
awk_script='
/PMIC_BATTERY_LOW/ {
    print $0; flag=100; next;
}
flag && /charge=/ {
    print $0; flag=0; next;
}
flag { flag--; }
'

# Process logs for each box IP ending
for ip_ending in "${box_ip_endings[@]}"; do
    echo -e "\n\n----------------------------------------"
    echo "Checking logs for Box IP: $IP_PREFIX.$ip_ending"
    echo "----------------------------------------"

    full_box_ip="$IP_PREFIX.$ip_ending"
    occurrence_count=0
    logfile_count=0
    total_logfile_checked=0

    # Count all log files for the current Box IP
    for log_file in /logs/$full_box_ip/$LOG_PATTERN; do
        if [ -f "$log_file" ]; then
            total_logfile_checked=$((total_logfile_checked + 1))
        fi
    done

    # Process each log file
    for log in /logs/$full_box_ip/$LOG_PATTERN; do
        if [ -f "$log" ]; then
            # Extract and format start and end times
            formatted_start_time=$(echo $log | sed -r 's/.*logfile-airfi-([0-9]{4})([0-9]{2})([0-9]{2})_([0-9]{2})([0-9]{2})([0-9]{2})-.*$/\1-\2-\3 \4:\5:\6/')
            formatted_end_time=$(echo $log | sed -r 's/.*logfile-airfi-[0-9]{12}-([0-9]{4})([0-9]{2})([0-9]{2})_([0-9]{2})([0-9]{2})([0-9]{2}).*$/\1-\2-\3 \4:\5:\6/')

            # Calculate duration
            duration=$(calculate_duration "$formatted_start_time" "$formatted_end_time")

            echo "Checking file: $log ||||||| Duration - $duration"

            # Process log with awk
            occurrences=$(zcat "$log" | awk "$awk_script")
            if [ -n "$occurrences" ]; then
                echo "$occurrences"
                logfile_count=$((logfile_count + 1))
                occurrence_count=$(($(echo "$occurrences" | grep -c "PMIC_BATTERY_LOW") + occurrence_count))
            fi
        fi
    done

    echo -e "Total occurrences of PMIC_BATTERY_LOW for Box IP $full_box_ip: $occurrence_count in $logfile_count logfiles (out of $total_logfile_checked checked)"
    echo -e "----------------------------------------\n\n"
done
