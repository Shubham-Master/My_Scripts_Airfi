#!/bin/bash

# Script Information
################################################################################################
#     Author: SK2                                                                              #
#     Date: 27-05-2024                                                                         #
#     Purpose: Check for the shutdown reasons in all AirFi logs in the 6E production boxes     #
################################################################################################

shutdown_charge="./shutdown_reason.csv"

get_voltage() {
    local line=$1
    echo $(echo $line | grep -oP 'voltage=-?\w+.?[\w\s]+(\(\K[\d]+)?' | awk -F"=" '{print $2}')
}

get_current() {
    local line=$1
    echo $(echo $line | grep -oP 'current=-?\w+.?[\w\s]+(\(\K[\d]+)?' | awk -F"=" '{print $2}')
}

get_charge() {
    local line=$1
    echo $(echo $line | grep -oP 'charge=-?\w+.?[\w\s]+(\(\K[\d]+)?')
}

echo "LogFile,DurationHours,ShutdownReason,LastCharge" > $shutdown_charge

while read -r box; do
    echo "Processing box: $box"
    while read -r log; do
        echo "Processing log: $log"
        mode=$(echo $log | awk -F"-" '{print $2}')
        if [[ $mode == 'airfi' ]]; then
            zcat $log 2>/dev/null | grep "charge=" > relevant_data
            while read -r line; do
                charge=$(get_charge "$line")
                voltage=$(get_voltage "$line")
                current=$(get_current "$line")
                # No condition check needed as we want to process all logs
                echo $log,$charge,$voltage,$current
            done < relevant_data

            # Extract start and end times from the filename
            start_time=$(echo "$log" | grep -oP '\d{8}_\d{6}' | head -1)
            end_time=$(echo "$log" | grep -oP '\d{8}_\d{6}' | tail -1)

            # Convert times to a format that can be used with 'date' command for calculation
            start_date=$(date -d "${start_time:0:4}-${start_time:4:2}-${start_time:6:2} ${start_time:9:2}:${start_time:11:2}:${start_time:13:2}" +%s)
            end_date=$(date -d "${end_time:0:4}-${end_time:4:2}-${end_time:6:2} ${end_time:9:2}:${end_time:11:2}:${end_time:13:2}" +%s)

            # Calculate the difference in hours
            diff_hours=$(echo "scale=2;($end_date - $start_date) / 3600" | bc -l)

            echo "$diff_hours"

            shutdown_reason=$(zcat "$log" | egrep "\-\-shutdown|\-\-reboot" | awk '{print $NF}' | tail -1)
            last_charge=$(get_charge "$(zcat $log | egrep "\-\-shutdown|\-\-reboot" -B5000 | grep "charge=" | tail -1)")
            echo $log,$diff_hours,$shutdown_reason,$last_charge >> $shutdown_charge
        fi
    done < <(ls -1 /logs/$box/*-2024*.gz 2>/dev/null | sort -t'-' -k3,3 2>/dev/null)
done < 6E_Pod_boxes.txt
