#!/bin/bash

# Initialize unexpected EOF counter
unexpected_eof_count=0

# Calculate previous date in format YYYYMMDD
previous_date=$(date -d "$(date +%Y%m%d) -1 day" +%Y%m%d)

# Update log pattern with previous date
LOG_PATTERN="logfile-airfi-$previous_date*.gz"

# Output file
output_file="low_battery_instances.txt"

# Initialize the output file to ensure it exists
> "$output_file"

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

while read -r box; do
    for log in /logs/$box/$LOG_PATTERN; do
        if [ -f "$log" ]; then
            # Check for unexpected EOF
            if ! zcat "$log" > /dev/null 2>&1; then
                unexpected_eof_count=$((unexpected_eof_count + 1))
                echo "Unexpected EOF in $log" >> "$output_file"
                continue  # Skip further processing for this file
            fi

            # Process log with awk
            occurrences=$(zcat "$log" | awk "$awk_script")
            if [ -n "$occurrences" ]; then
                echo "Found in $log:" >> "$output_file"
                echo "$occurrences" >> "$output_file"
            fi
        fi
    done
done < new_battery

# Check if there were any unexpected EOFs and append to the email
if [ $unexpected_eof_count -gt 0 ]; then
    echo "Number of log files with unexpected EOF: $unexpected_eof_count" >> "$output_file"
fi


# Send the output file via email only if it exists and is not empty
if [ -s "$output_file" ]; then
    subject="Low Battery Instances Report: New battery boxes G9"  # Customized subject line
    recipient_emails="shubham.kr@airfi.aero, bharat.manral@airfi.aero, jalal.zriouil@airfi.aero, priyadarshan.roy@airfi.aero"
    mail -s "$subject" $recipient_emails < "$output_file"
    # Remove the output file after sending the email
    rm "$output_file"
fi
