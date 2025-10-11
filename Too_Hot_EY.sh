#!/bin/bash

#########################################################################################################################
#                                                                                                                       #
#       Author  : SK2                                                                                                   #
#       Date    : 24/06/2024                                                                                            #
#       Purpose : Purpose of this script is to check the TOO HOT occurrence in EY_Production boxes .                    #
#                                                                                                                       #
#########################################################################################################################

# Define the months for which we will check the logs
months=("03" "04" "05" "06") # March, April, May, June
month_names=("March" "April" "May" "June")

# Output file
output_file="EY_hotcounts.csv"

# Header for the output CSV
echo "box ip,March,April,May,June,Total" > "$output_file"

# Read box IPs from Ey_boxes
while read -r box_ip; do
    # Initialize an array to store counts for each month
    monthly_counts=(0 0 0 0)
    total_count=0

    # Iterate over each month
    for i in "${!months[@]}"; do
        month="${months[$i]}"
        # Define the log pattern
        log_pattern="/logs/$box_ip/logfile-maintenance-2024$month*.gz"

        # Count "TOO HOT" occurrences for the current month
        for log in $log_pattern; do
            if [[ -f "$log" ]]; then
                count=$(zgrep -c "TOO HOT" "$log" 2>/dev/null)
                monthly_counts[$i]=$((monthly_counts[$i] + count))
                total_count=$((total_count + count))
            fi
        done
    done

    # Write the results to the CSV file
    echo "$box_ip,${monthly_counts[0]},${monthly_counts[1]},${monthly_counts[2]},${monthly_counts[3]},$total_count" >> "$output_file"
done < Ey_boxes

echo "Report generated: $output_file"
