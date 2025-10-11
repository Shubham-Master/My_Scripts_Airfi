#!/bin/bash

# Initialize unexpected EOF counter
unexpected_eof_count=0

# Set the year and month for processing logs
year=2024
month=01

# Update log pattern for the entire month
LOG_PATTERN="logfile-airfi-$year$month*.gz"

# Output file in CSV format
output_file="low_battery_instances.csv"

# Initialize the output file with column headers
echo "Box,LogFile,EventDetails" > "$output_file"

# awk script for processing logs
awk_script='
/PMIC_BATTERY_LOW/ {
    print box","log_file","$0; flag=100; next;
}
flag && /charge=/ {
    print box","log_file","$0; flag=0; next;
}
flag { flag--; }
'

while read -r box; do
    for log in /logs/$box/$LOG_PATTERN; do
        if [ -f "$log" ]; then
            # Check for unexpected EOF
            if ! zcat "$log" > /dev/null 2>&1; then
                unexpected_eof_count=$((unexpected_eof_count + 1))
                echo "$box,$log,Unexpected EOF" >> "$output_file"
                continue  # Skip further processing for this file
            fi

            # Process log with awk, passing box and log file name as variables
            occurrences=$(zcat "$log" | awk -v box="$box" -v log_file="$log" "$awk_script")
            if [ -n "$occurrences" ]; then
                echo "$occurrences" >> "$output_file"
            fi
        fi
    done
done < new_battery

# Append information about any unexpected EOFs at the end of the CSV file
if [ $unexpected_eof_count -gt 0 ]; then
    echo "EOF Summary,,Number of log files with unexpected EOF: $unexpected_eof_count" >> "$output_file"
fi
