#!/bin/bash

# Script Information
################################################################################################
#     Author: SK2                                                                              #
#     Date: 11-01-2023                                                                         #
#     Purpose: Check for hardware issues of the box and battery failures                       #
################################################################################################

# Read IATA code and date from the user
iata="VN"
echo -n "Enter the start date (YYYYMMDD): "
read date

# Retrieve list of box IPs
/usr/local/bin/get-box-ip-from-disco.sh $iata 2> /dev/null > /tmp/.box-list-$iata

# AWK script for processing log files
awk_script='
{
    # Check for PMIC_BATTERY_LOW and subsequent charge information
    # ...
}
'

# Initialize counters and output file
box_count=0
output_file="Faulty_Boxes"
> "$output_file" # Clear the output file at the start

# Process each box
for ip in $(cat /tmp/.box-list-$iata); do
    echo "Processing Box: $ip"
    box_count=$((box_count + 1))  # Increment box counter
    box_faulty=0  # Flag to check if box IP is already recorded

    # Process each logfile of the box
    find /logs/$ip -type f -name "logfile-airfi-*$date*.gz" | while read logfile; do
        echo "Processing Logfile: $logfile"
        
        # Check for specified patterns in the logfile
        if zcat "$logfile" | grep -q -e "failure_init" -e "SYSTEM ERROR" -e "failure_usbreset" -e "PMIC_BATTERY_LOW"; then
            # Record the box IP if any pattern is found and not already recorded
            if [ $box_faulty -eq 0 ]; then
                echo "$ip" >> "$output_file"
                box_faulty=1
            fi
        fi

        # Additional processing of logfiles for PMIC_BATTERY_LOW and charge info
        # ...

        # Extract and display initial and last charge
        # ...

        echo "----------------------------------------"
    done
done

# Display total number of boxes processed
echo "Total number of boxes processed: $box_count"
