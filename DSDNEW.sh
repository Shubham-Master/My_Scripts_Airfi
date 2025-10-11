#!/bin/bash

# Define the start and end dates
start_date="20231101"
end_date=$(date +"%Y%m%d")

# Output CSV file
output_file="DSD_issues.csv"
echo "BoxIP,FirmwareVersion,PMIC_BATTERY_LOW_Event,PMIC_BATTERY_LOW_Occurrences,AIRCLIENT_USBRESET_Event,AIRCLIENT_USBRESET_Occurrences" > "$output_file"

# Function to check log files for a specific issue and count occurrences
check_issue() {
    local issue=$1
    local ip=$2
    local start_date=$3
    local end_date=$4

    local occurrences=0
    local current_date="$start_date"

    while [[ "$current_date" -le "$end_date" ]]; do
        occurrences=$((occurrences + $(zgrep -c "$issue" /logs/$ip/logfile-airfi-$current_date*.gz 2>/dev/null)))
        current_date=$(date -d "$current_date +1 day" +"%Y%m%d")
    done

    local event_occurred="NO"
    if [[ "$occurrences" -gt 0 ]]; then
        event_occurred="YES"
    fi

    echo "$event_occurred,$occurrences"
}

# Function to extract firmware version and issues
extract_issues() {
    local ip=$1

    # Extract firmware version
    local firmware_version=$(zgrep -m 1 "SWver" /logs/$ip/logfile-airfi-*.gz | head -1 | awk '{print $NF}')
    local line="$ip,$firmware_version,"

    # Check for PMIC_BATTERY_LOW
    local pmic_data=$(check_issue "PMIC_BATTERY_LOW" "$ip" "$start_date" "$end_date")
    line+="$pmic_data,"

    # Check for AIRCLIENT_USBRESET
    local airclient_data=$(check_issue "AIRCLIENT_USBRESET" "$ip" "$start_date" "$end_date")
    line+="$airclient_data"

    echo "$line"
}

# Create an array to store the data
declare -a data_lines

# Read boxes from DSD_Boxes and process
while IFS= read -r box; do
    echo "Processing box: $box"
    data_lines+=("$(extract_issues "$box")")
done < "DSD_Boxes"

# Write all data to the output file
printf "%s\n" "${data_lines[@]}" >> "$output_file"

echo "Data extraction completed. Output saved in $output_file."
