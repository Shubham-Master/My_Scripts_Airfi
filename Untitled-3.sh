#!/bin/bash

output_file="./output.csv"
pattern="voltage=|\-\-shutdown|\-\-reboot|rcK"

# Initialize CSV file header
echo "Box,MaintenanceLogFile,AirFiLogFile,LastCharge,ShutdownReason,LastVoltage,Abrupt_shutdown" > $output_file

# Read through each box directory provided in a file called test_boxes
while read -r box; do
   echo "Processing box: $box"
    
    all_logs=($(ls -1 /logs/$box/*.gz | sort -t '-' -k3))

    prev_log=""
    prev_log_type=""
    for log in "${all_logs[@]}"; do
        echo "Processing log: $log"
        content=$(zgrep -E $pattern $log)
        log_type=$(echo "$log" | grep -oP 'logfile-\K\w+')

        if [[ "$log_type" == "maintenance" ]]; then
            charges=($(echo "$content" | grep "charge=" | awk -F"=" '{print $2}'))
            voltages=($(echo "$content" | grep "voltage=" | awk -F"=" '{print $2}'))

            for index in "${!charges[@]}"; do
                charge="${charges[$index]}"
                voltage="${voltages[$index]}"
                echo "Debug: Charge = $charge, Voltage = $voltage"

                if [[ "$charge" -eq 100 && "$(echo "$voltage >= 3.6" | bc -l)" -eq 1 ]]; then
                    prev_log="$log"
                    prev_log_type="maintenance"
                    echo "Maintenance criteria met: $log"
                    break
                fi
            done
        elif [[ "$log_type" == "airfi" && "$prev_log_type" == "maintenance" ]]; then
            shutdown_reason=$(echo "$content" | egrep "\-\-shutdown|\-\-reboot" | awk '{print $NF}' | tail -1)
            last_charge_line=$(echo "$content" | grep "charge=" | tail -1)
            last_charge=$(echo "$last_charge_line" | awk -F"=" '{print $2}')
            last_voltage=$(echo "$last_charge_line" | grep "voltage=" | awk -F"=" '{print $2}')

            if ! grep -q "rcK" <<< "$content"; then
                abrupt_shutdown="YES"
            else
                abrupt_shutdown="NO"
            fi

            if [[ "$last_charge" -lt 20 || $abrupt_shutdown == "YES" || $shutdown_reason = *'USBRESET'* ||  $shutdown_reason = *'BATTERY_LOW'* ]]; then
                echo "$box,$prev_log,$log,$last_charge,$shutdown_reason,$last_voltage,$abrupt_shutdown" >> $output_file
            fi

            prev_log=""
            prev_log_type=""
        fi
    done
done < test_box

echo "Script completed."
