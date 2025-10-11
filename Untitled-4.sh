#!/bin/bash

output_file="./output.csv"
pattern="voltage=|charge=|--shutdown|--reboot|rcK"

# Function to extract voltage
get_voltage() {
    local line=$1
    echo $(echo "$line" | grep -oP 'voltage=\K[\d\.]+')
}

# Function to extract charge
get_charge() {
    local line=$1
    echo $(echo "$line" | grep -oP 'charge=\K\d+')
}

# Initialize CSV file header
echo "Box,MaintenanceLogFile,AirFiLogFile,LastCharge,ShutdownReason,LastVoltage,Abrupt_shutdown" > $output_file

# Read through each box directory provided in a file 
while read -r box; do
    echo "Processing box: $box"
    all_logs=($(ls -1 /logs/$box/*.gz | sort -t '-' -k3))
    found_pair=false

    prev_log=""
    prev_log_type=""

    for log in "${all_logs[@]}"; do
        echo "Processing log: $log"
        log_type=$(echo "$log" | grep -oP 'logfile-\K\w+')

        if [[ "$log_type" == "maintenance" ]]; then
            zcat "$log" | while IFS= read -r line; do
                charge=$(get_charge "$line")
                voltage=$(get_voltage "$line")
                echo "Debug: Charge = $charge, Voltage = $voltage"

                if [[ "$charge" -eq 100 && "$(echo "$voltage >= 3.6" | bc -l)" -eq 1 ]]; then
                    prev_log="$log"
                    prev_log_type="maintenance"
                    echo "Maintenance criteria met: $log"
                    break
                fi
            done
        elif [[ "$log_type" == "airfi" && "$prev_log_type" == "maintenance" ]]; then
            shutdown_reason=$(zgrep -- "--shutdown|--reboot" "$log" | tail -1 | awk '{print $NF}')
            last_charge_line=$(zgrep "charge=" "$log" | tail -1)
            last_charge=$(get_charge "$last_charge_line")
            last_voltage=$(get_voltage "$last_charge_line")

            if ! zgrep -q "rcK" "$log"; then
                abrupt_shutdown="YES"
            else
                abrupt_shutdown="NO"
            fi

            if [[ "$last_charge" -lt 20 || "$abrupt_shutdown" == "YES" || "$shutdown_reason" == *'USBRESET'* || "$shutdown_reason" == *'BATTERY_LOW'* ]]; then
                echo "$box,$prev_log,$log,$last_charge,$shutdown_reason,$last_voltage,$abrupt_shutdown" >> $output_file
                found_pair=true
            fi

            prev_log=""
            prev_log_type=""
        fi
    done
    if [[ "$found_pair" == false ]]; then
        echo "No valid airfi and maintenance log pair found for box: $box"
    fi
done < test_box

echo "Script completed."
