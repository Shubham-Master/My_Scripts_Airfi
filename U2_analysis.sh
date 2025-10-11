#!/bin/bash

# Update log pattern with date pattern
LOG_PATTERN="logfile-airfi-20231*.gz"

# Output files
output_file_U2issue="U2issue.txt"
output_file_planned="Planned.txt"

# Check if U2 file exists
if [ ! -f U2 ]; then
    echo "Error: U2 file not found."
    exit 1
fi

while read -r box; do
    # Check if /logs/$box directory exists
    if [ ! -d "/logs/$box" ]; then
        echo "Error: Directory /logs/$box not found."
        continue
    fi

    for log in /logs/$box/$LOG_PATTERN; do
        # Check for no matches case
        if [ "$log" = "/logs/$box/$LOG_PATTERN" ]; then
            echo "No log files match the pattern in /logs/$box."
            break
        fi

        # Check if file exists and grep for the "Start of rcK" pattern
        if [ -f "$log" ]; then
            if zcat "$log" 2>/dev/null | grep -q "Start of rcK"; then
                echo "Found in $log:" >> "$output_file_U2issue"
                zcat "$log" 2>/dev/null | grep -H "Start of rcK" >> "$output_file_U2issue"
            fi

            # Grep for the "Executing planned shutdown" pattern and output to a different file
            if zcat "$log" 2>/dev/null | grep -q "Executing planned shutdown"; then
                echo "Found in $log:" >> "$output_file_planned"
                zcat "$log" 2>/dev/null | grep -H "Executing planned shutdown" >> "$output_file_planned"
            fi
        fi
    done
done < U2
