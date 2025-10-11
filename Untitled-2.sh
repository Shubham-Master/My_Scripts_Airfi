#!/bin/bash

output_file="./output.csv"

# Function to extract voltage
get_voltage() {
    local line=$1
    echo $(echo "$line" | grep -oP 'voltage=-?\w+.?[\w\s]+(\(\K[\d]+)?' | awk -F"=" '{print $2}')
}

# Function to extract charge
get_charge() {
    local line=$1
    echo $(echo "$line" | grep -oP 'charge=-?\w+.?[\w\s]+(\(\K[\d]+)?')
}

# Initialize CSV file header
echo "Box,MaintenanceLogFile,AirFiLogFile,LastCharge,ShutdownReason,LastVoltage,Abrupt_shutdown" > $output_file

# Read through each box directory provided in a file called DSD_Boxes
while read -r box; do
    echo "Processing box: $box"
     List all gzipped log files for the box sorted by date
    all_logs=($(ls -1 /logs/$box/*.gz | sort -t '-' -k3))
    found_pair=false

    prev_log=""
    prev_log_type=""
echo "${all_logs[@]}"
    for log in "${all_logs[@]}"; do
        echo "Processing log: $log"
        content=$(zcat "$log")
        log_type=$(echo "$log" | grep -oP 'logfile-\K\w+')

        if [[ "$log_type" == "maintenance" ]]; then
            # Extract all charge and voltage values from the maintenance log
            charges=($(get_charge "$content"))
            voltages=($(get_voltage "$content"))

            # Debug output for charges and voltages
            for index in "${!charges[@]}"; do
                charge="${charges[$index]}"
                voltage="${voltages[$index]}"
                echo "Debug: Charge = $charge, Voltage = $voltage"

                # Criteria to determine if the log should be considered for further processing
                if [[ "$charge" -eq 100 && "$(echo "$voltage >= 3.6" | bc -l)" -eq 1 ]]; then
                    prev_log="$log"
                    prev_log_type="maintenance"
                    echo "Maintenance criteria met: $log"
                    break
                fi
            done
        elif [[ "$log_type" == "airfi" && "$prev_log_type" == "maintenance" ]]; then
            # Extract the shutdown reason and last charge/voltage close to the shutdown or reboot event
            shutdown_reason=$(zcat "$log" | egrep "\-\-shutdown|\-\-reboot" | awk '{print $NF}' | tail -1)
            last_charge_line=$(zcat "$log"| grep "charge=" | tail -1)
            last_charge=$(get_charge "$last_charge_line")
            last_voltage=$(get_voltage "$last_charge_line")

            # Check for abrupt shutdown
            if ! grep -q "rcK" <<< "$(zcat "$log")"; then
                abrupt_shutdown="YES"
            else
                abrupt_shutdown="NO"
            fi

            # Output the results to a CSV file if last charge is less than 20%
            if [[ "$last_charge" -lt 20 || $abrupt_shutdown == "YES" || $shutdown_reason = *'USBRESET'* ||  $shutdown_reason = *'BATTERY_LOW'* ]]; then
                echo "$box,$prev_log,$log,$last_charge,$shutdown_reason,$last_voltage,$abrupt_shutdown" >> $output_file
                found_pair=true
            fi

            # Reset the previous log details for the next cycle
            prev_log=""
            prev_log_type=""
        fi
    done
    if [[ "$found_pair" == false ]]; then
        echo "No valid airfi and maintenance log pair found for box: $box"
    fi
#done < test_boxes

echo "Script completed."