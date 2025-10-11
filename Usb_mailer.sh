#!/bin/bash

#########################################################################################################################
#                                                                                                                       #
#       Author  : SK2                                                                                                   #
#       Date    : 14/02/2024                                                                                            #
#       Purpose : This script is designed to track the first occurrence of USB resets and identify logs                 #
#                 where "Start of rcK: OK" is missing for Ytt and Alice Dongles.                                        #
#                                                                                                                       #
#                                                                                                                       #
#########################################################################################################################

## Read Box IPs from a file
box_ips=$(cat "Ytt_Alice_Boxes.txt")

## Determine yesterday's date for log file selection
yesterday=$(date -d "$(date +%Y%m%d) -1 day" +%Y%m%d)

## Log file pattern for the last day
LOG_PATTERN="logfile-*-${yesterday}*.gz"

## Define the output file path
output_file="failure_usbreset_report_${yesterday}.txt"

## Initialize or clear the output file to ensure it starts empty
echo "Failure USB Reset Report for $yesterday" > "$output_file"
echo "-------------------------------------------------------------" >> "$output_file"

## Check logs for each Box IP
for box_ip in $box_ips; do
    first_occurrence_file_airclient_usbreset=""
    first_occurrence_file_usbreset_phy0=""
    total_occurrences_airclient_usbreset=0
    total_occurrences_usbreset_phy0=0
    missing_rcK_logs=""
    permanent_address_info=""

    ## Since logs are stored in a directory structure /logs/${box_ip}/
    for log_file in $(find /logs/${box_ip}/ -name "$LOG_PATTERN"); do
        if [ -f "$log_file" ]; then
            # Check for AIRCLIENT_USBRESET occurrences
            occurrences_airclient_usbreset=$(zgrep -ic "AIRCLIENT_USBRESET" "$log_file" 2>/dev/null)
            total_occurrences_airclient_usbreset=$((total_occurrences_airclient_usbreset + occurrences_airclient_usbreset))
            if [ "$occurrences_airclient_usbreset" -gt 0 ] && [ -z "$first_occurrence_file_airclient_usbreset" ]; then
                first_occurrence_file_airclient_usbreset=$log_file
            fi

            # Check for usbreset: soft resetting phy0 occurrences
            occurrences_usbreset_phy0=$(zgrep -ic "usbreset: soft resetting phy0" "$log_file" 2>/dev/null)
            total_occurrences_usbreset_phy0=$((total_occurrences_usbreset_phy0 + occurrences_usbreset_phy0))
            if [ "$occurrences_usbreset_phy0" -gt 0 ] && [ -z "$first_occurrence_file_usbreset_phy0" ]; then
                first_occurrence_file_usbreset_phy0=$log_file
            fi

            # Check for permanent address and only record it once
            if [ "$total_occurrences_airclient_usbreset" -gt 0 ] && [ -z "$permanent_address_info" ]; then
                permanent_address_info=$(zgrep -m 1 "wlan0: Permanent address:" "$log_file" 2>/dev/null)
            fi

            # Check for missing "Start of rcK: OK"
            if ! zgrep -q "Start of rcK: OK" "$log_file" 2>/dev/null; then
                missing_rcK_logs+="${log_file}\n"
            fi
        fi
    done

    # Report findings for each box IP
    if [ "$total_occurrences_airclient_usbreset" -gt 0 ] || [ "$total_occurrences_usbreset_phy0" -gt 0 ] || [ ! -z "$missing_rcK_logs" ]; then
        echo "Box IP: $box_ip" >> "$output_file"
        if [ "$total_occurrences_airclient_usbreset" -gt 0 ]; then
            echo "'AIRCLIENT_USBRESET' occurrences: $total_occurrences_airclient_usbreset. First occurrence in $first_occurrence_file_airclient_usbreset." >> "$output_file"
            # Include permanent address info if available
            if [ ! -z "$permanent_address_info" ]; then
                echo "$permanent_address_info" >> "$output_file"
            fi
        fi
        if [ "$total_occurrences_usbreset_phy0" -gt 0 ]; then
            echo "'usbreset: soft resetting phy0' occurrences: $total_occurrences_usbreset_phy0. First occurrence in $first_occurrence_file_usbreset_phy0." >> "$output_file"
        fi
        if [ ! -z "$missing_rcK_logs" ]; then
            echo -e "Logs missing 'Start of rcK: OK':\n$missing_rcK_logs" >> "$output_file"
        fi
        echo "--------------------------------" >> "$output_file"
    fi
done

## Send the report via email only if occurrences were found
Line_count=$(wc -l < "$output_file")
if [ $Line_count -gt 2 ]; then
    recipient_emails="shubham.kr@airfi.aero, rohit.malaviya@airfi.aero, yash.anand@airfi.aero, priyadarshan.roy@airfi.aero, pavan.kumar@airfi.aero"
    subject="Failure USB Reset Report for $yesterday"
    mail -s "$subject" $recipient_emails < "$output_file"

    ## Uncomment the below line if you want to delete the output file after sending the mail
    # rm "$output_file"
fi
