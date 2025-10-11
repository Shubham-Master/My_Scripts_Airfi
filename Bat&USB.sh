#!/bin/bash

# Prompt user to enter month to check in yyyymm format
read -p "Enter month to check in yyyymm format: " month

# Define log pattern using the provided month
LOG_PATTERN="logfile-airfi-$month*.gz"

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
usbreset_awk_script='
/USBRESET/ {
    print $0;
}
'

# Initialize the output file
output_file="box_check_results.txt"
echo "Box IP Check Results for Month $month" > "$output_file"
echo "========================================" >> "$output_file"

# Read full box IPs from Binter_boxes file
while IFS= read -r full_box_ip; do
    echo -e "\n\n----------------------------------------" >> "$output_file"
    echo "Checking logs for Box IP: $full_box_ip" >> "$output_file"
    echo "----------------------------------------" >> "$output_file"

    occurrence_count=0
    usbreset_occurrence_count=0
    logfile_count=0
    usbreset_logfile_count=0
    unexpected_eof_count=0
    total_logfile_checked=0

    # Process each log file
    for log in /logs/$full_box_ip/$LOG_PATTERN; do
        if [ -f "$log" ]; then
            total_logfile_checked=$((total_logfile_checked + 1))
            echo "Checking file: $log" >> "$output_file"
            # Check for unexpected EOF in log file
            if ! zcat "$log" > /dev/null 2>&1; then
                echo "Error: Unexpected end of file in $log" >> "$output_file"
                unexpected_eof_count=$((unexpected_eof_count + 1))
                continue # Skip processing this log file further
            fi

            # Process log with awk for PMIC_BATTERY_LOW
            occurrences=$(zcat "$log" | awk "$awk_script")
            if [ -n "$occurrences" ]; then
                echo "$occurrences" >> "$output_file"
                logfile_count=$((logfile_count + 1))
                occurrence_count=$(($(echo "$occurrences" | grep -c "PMIC_BATTERY_LOW") + occurrence_count))
            fi

            # Process log with awk for USBRESET
            usbreset_occurrences=$(zcat "$log" | awk "$usbreset_awk_script")
            if [ -n "$usbreset_occurrences" ]; then
                echo "$usbreset_occurrences" >> "$output_file"
                usbreset_logfile_count=$((usbreset_logfile_count + 1))
                usbreset_occurrence_count=$(($(echo "$usbreset_occurrences" | grep -c "USBRESET") + usbreset_occurrence_count))
            fi
        fi
    done

    echo -e "Total occurrences of PMIC_BATTERY_LOW for Box IP $full_box_ip: $occurrence_count in $logfile_count logfiles (out of $total_logfile_checked checked)" >> "$output_file"
    echo -e "Total occurrences of USBRESET for Box IP $full_box_ip: $usbreset_occurrence_count in $usbreset_logfile_count logfiles (out of $total_logfile_checked checked)" >> "$output_file"
    echo -e "Total unexpected EOF errors for Box IP $full_box_ip: $unexpected_eof_count" >> "$output_file"
    echo -e "----------------------------------------\n\n" >> "$output_file"
done < Binter_boxes

echo "Processing complete. Check the results in $output_file."
