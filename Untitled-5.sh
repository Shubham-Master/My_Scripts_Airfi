#!/bin/bash

#########################################################################################################################
#                                                                                                                       #
#       Author  : SK2                                                                                                   #
#       Date    : 26/02/2024                                                                                            #
#       Purpose : Check PMIC_BATTERY_LOW event and usbreset occurrence in logs. Reads Box IPs from G9_24feb_boxes.txt.  #
#                                                                                                                       #
#########################################################################################################################

# Calculate previous day's date for dynamic log file naming
previous_date=$(date -d "$(date +%Y%m%d) -1 day" +%Y%m%d)

# Define log pattern using the calculated previous date
LOG_PATTERN="logfile-airfi-$previous_date*.gz"

# awk script for processing logs, now exclusively noting usbreset events without charge info
awk_script='
/PMIC_BATTERY_LOW/ {
    print "PMIC_BATTERY_LOW event: ", $0; flag=100; next;
}
/usbreset/ {
    print "usbreset event: ", $0; next;
}
flag && /charge=/ {
    print "Charge at PMIC_BATTERY_LOW event: ", $0; flag=0; next;
}
flag { flag--; }
'

# Prepare the output file
echo "" > results.txt

# Read Box IPs from the file G9_24feb_boxes.txt
while read -r full_box_ip; do
    echo -e "\n\n----------------------------------------" >> results.txt
    echo "Checking logs for Box IP: $full_box_ip" >> results.txt
    echo "----------------------------------------" >> results.txt

    occurrence_count=0
    usbreset_count=0
    logfile_count=0
    total_logfile_checked=0

    # Count all log files for the current Box IP
    for log_file in /logs/$full_box_ip/$LOG_PATTERN; do
        if [ -f "$log_file" ]; then
            total_logfile_checked=$((total_logfile_checked + 1))
        fi
    done

    # Process each log file
    for log in /logs/$full_box_ip/$LOG_PATTERN; do
        if [ -f "$log" ]; then
            echo "Checking file: $log" >> results.txt
            # Process log with awk
            occurrences=$(zcat "$log" | awk "$awk_script")
            if [ -n "$occurrences" ]; then
                echo "$occurrences" >> results.txt
                logfile_count=$((logfile_count + 1))
                occurrence_count=$(($(echo "$occurrences" | grep -c "PMIC_BATTERY_LOW event:") + occurrence_count))
                usbreset_count=$(($(echo "$occurrences" | grep -c "usbreset event:") + usbreset_count))
            fi
        fi
    done

    echo -e "Total occurrences of PMIC_BATTERY_LOW for Box IP $full_box_ip: $occurrence_count in $logfile_count logfiles (out of $total_logfile_checked checked)" >> results.txt
    echo -e "Total occurrences of usbreset for Box IP $full_box_ip: $usbreset_count in $logfile_count logfiles (out of $total_logfile_checked checked)" >> results.txt
    echo -e "----------------------------------------\n\n" >> results.txt
done < G9_24feb_boxes.txt
