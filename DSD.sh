#!/bin/bash

#########################################################################################################################
##                                                                                                                     ##
##       Author  : SK2                                                                                                 ##
##       Date    : 19/01/2024                                                                                          ##
##       Purpose : Purpose of this script is to check the Health of all DSD Boxes                                      ##
##                                                                                                                     ##
#########################################################################################################################

# Function to check for unexpected EOF in a log file
check_unexpected_eof() {
    local log_file="$1"
    if ! zcat "$log_file" > /dev/null 2>&1; then
        echo "Unexpected EOF in $log_file" >> "$output_file"
        return 1  # Return 1 to indicate unexpected EOF
    fi
    return 0  # Return 0 to indicate successful check
}

# Prompt the user for a date
read -p "Please enter the date (YYYYMMDD): " date

# Output CSV file
output_file="DSD_issues.csv"

# Initialize the output CSV with headers
echo "Box IP, Firmware Version, Issue Type, Start Date, Occurrences, Logfile Count, Last Charge" > "$output_file"

# AWK script for processing logs
awk_script='
/PMIC_BATTERY_LOW/ {
    print $0; flag=100; next;
}
flag && /charge=/ {
    print $0; flag=0; next;
}
flag { flag--; }
'

# Function to extract battery and hardware issues
extract_issues() {
    local ip=$1
    local date=$2
    local output_file=$3
    local firmware_version=$(zgrep -m 1 "SWver" /logs/$ip/logfile-airfi-*${date}*.gz | head -1 | awk '{print $NF}')

    echo -n "$ip, $firmware_version, " >> "$output_file"

    local issue_types=("PMIC_BATTERY_LOW" "SYSTEM ERROR" "failure_usbreset")
    for issue in "${issue_types[@]}"; do
        local issue_data=$(zgrep -i "$issue" /logs/$ip/logfile-airfi-*${date}*.gz)
        if [[ -n "$issue_data" ]]; then
            local start_date=$(echo "$issue_data" | head -1 | awk '{print $1}')
            local occurrences=$(echo "$issue_data" | wc -l)
            local logfile_count=$(echo "$issue_data" | awk '{print $3}' | sort -u | wc -l)
            
            # Use AWK script to find lines with "charge=" near the issue
            local charge_info=$(echo "$issue_data" | awk "$awk_script")
            local last_charge=$(echo "$charge_info" | tail -1)

            echo "$issue, $start_date, $occurrences, $logfile_count, $last_charge" >> "$output_file"
        else
            echo "No $issue, , , , ," >> "$output_file"
        fi
    done
}

# Read boxes from DSD_Boxes and process
while IFS= read -r box; do
    # Process each box
    echo "Processing box: $box"
    # Create a flag to track unexpected EOF
    unexpected_eof_flag=0

    # Check log files and handle unexpected EOF
    for log in /logs/$box/logfile-airfi-*${date}*.gz; do
        if [ -f "$log" ]; then
            # Check for unexpected EOF
            if ! check_unexpected_eof "$log"; then
                unexpected_eof_flag=1
                continue  # Skip further processing for this file
            fi

            # Process log with issues
            extract_issues "$box" "$date" "$output_file"
        fi
    done

    # Report unexpected EOF if encountered
    if [ "$unexpected_eof_flag" -eq 1 ]; then
        echo "Unexpected EOF(s) detected in log files for $box" >> "$output_file"
    fi

done < "DSD_Boxes"

echo "Data extraction completed. Output saved in $output_file."
