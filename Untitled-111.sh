#!/bin/bash

# Script Information
################################################################################################
#     Author: SK2                                                                              #
#     Date: 28-05-2024                                                                         #
#     Purpose: Check for the box performance in factory after FUSE replacement by CDS          #
################################################################################################

detailed_output="./Detailed-data.csv"
shutdown_charge="./shutdown_reason.csv"

get_voltage() {
    local line=$1
    echo $(echo $line | grep -oP 'voltage=-?\d+\.?\d*' | awk -F"=" '{print $2}')
}

get_current() {
    local line=$1
    echo $(echo $line | grep -oP 'current=-?\d+\.?\d*' | awk -F"=" '{print $2}')
}

get_charge() {
    local line=$1
    echo $(echo $line | grep -oP 'charge=-?\d+\.?\d*' | awk -F"=" '{print $2}')
}

get_temperature() {
    local line=$1
    echo $(echo $line | grep -oP 'temperature=-?\d+\.?\d*' | awk -F"=" '{print $2}')
}

get_time() {
    local line=$1
    echo $(echo $line | grep -oP '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}')
}

echo "Box,Mode,LogFile,Initial_Charge,Initial_Charge_Time,Charge_50%,Time_to_50%_hrs,USB_Reset,Shutdown_Reason" >$detailed_output

while read -r box; do
    echo "Processing box: $box"
    while read -r log; do
        echo "Processing log: $log"
        mode=$(echo $log | awk -F"-" '{print $2}')
        log_date=$(basename $log | awk -F"_" '{print $1}')
        if [[ $log_date -le 20240520 ]]; then
            continue
        fi
        zcat $log 2>/dev/null | grep "charge=" >relevant_data
        usbreset=$(zcat $log 2>/dev/null | grep -c "usbreset")

        if [[ $mode == 'maintenance' || $mode == 'airfi' ]]; then
            initial_line=$(head -1 relevant_data)
            charge_50_line=$(grep -m1 "charge=50" relevant_data)

            initial_charge=$(get_charge "$initial_line")
            initial_time=$(get_time "$initial_line")
            charge_50=$(get_charge "$charge_50_line")
            time_50=$(get_time "$charge_50_line")

            initial_epoch=$(date -d "$initial_time" +%s)
            epoch_50=$(date -d "$time_50" +%s)

            time_to_50_hrs=$(echo "scale=2;($epoch_50 - $initial_epoch) / 3600" | bc -l)

            shutdown_reason=$(zcat "$log" | egrep "\-\-shutdown|\-\-reboot" | awk '{print $NF}' | tail -1)

            echo $box,$mode,$log,$initial_charge,$initial_time,$charge_50,$time_to_50_hrs,$([ $usbreset -gt 0 ] && echo "YES" || echo "NO"),$shutdown_reason >>$detailed_output
        fi
    done < <(ls -1 /logs/$box/*-2024*.gz 2>/dev/null | sort -t'-' -k3,3 2>/dev/null)
done <jp.txt
