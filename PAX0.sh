#!/bin/bash

############################################################################################
#                                                                                          #
#    Author: SK2                                                                           #
#    Date: 22-09-2025                                                                      #
#    Notes: This script gets a list of box serial numbers for the passed IATA code.        #
#    And check if there are 0 PAX connection in last 30 Days                               #
#                                                                                          #
############################################################################################


# Ensure exactly one argument (the IATA code) is provided
[[ $# != 1 ]] && {
    echo "Error: Incorrect number of arguments provided."
    echo "Usage: $(basename "$0") IATA_CODE or BOX_SERIAL"
    echo "Example: $(basename "$0") G9 or 10.0.9.13"
    exit 1
}

iata=$1

# Determine if argument is a serial (box serial like 10.0.9.13) or an IATA code (like G9)
if [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    # Argument looks like a serial/IP, use directly
    serials="$1"
else
    # Argument is assumed to be an IATA code, fetch serials for given IATA
    serials=$(curl -s "https://${API_USER}:${API_PASS}@airfi-disco.herokuapp.com/api/devices/customerCode/${iata}?fields=serial" | jq -r '.[].serial')
fi

# Prepare output CSV
output="pax0_report.csv"
echo "SERIAL,PAX0,IATA,NUM_LOGS_30DAYS" > "$output"

for serial in $serials; do
    logdir="/logs/$serial"
    [[ ! -d $logdir ]] && continue

    # Find airfi logs modified within last 30 days, 
    box_all_zero_30days=true
    iata_found=""
    logs_count=0
    first_log_for_fallback=""

    while IFS= read -r -d '' log; do
        ((logs_count++))
        [[ -z "$first_log_for_fallback" ]] && first_log_for_fallback="$log"

        # Cache Display lines for this log
        display_lines=$(zcat "$log" | grep "Display:" || true)

        # If no Display lines, treat as NOT all-zero (be strict)
        if [[ -z "$display_lines" ]]; then
            box_all_zero_30days=false
            break
        fi

        # If any non-zero PAX occurs in this log, then this box is NOT all-zero across 30 days
        if echo "$display_lines" | grep -Eiq 'PAX[[:space:]]+([1-9][0-9]?)'; then
            box_all_zero_30days=false
            break
        fi

        # If we never see "PAX 0" in this log (unlikely, but be strict), also fail
        if ! echo "$display_lines" | grep -Eq 'PAX[[:space:]]+0\b'; then
            box_all_zero_30days=false
            break
        fi

        # Extract IATA from Display line if not yet set 
        if [[ -z "$iata_found" ]]; then
            iata_found=$(echo "$display_lines" | head -1 | sed -E 's/.*Display:[[:space:]]*([A-Za-z0-9]{2,3})[[:space:]].*/\1/')
        fi
    done < <(find "$logdir" -type f -name "logfile-airfi-*.gz" -mtime -30 -print0)

    # Fallback IATA extraction (in case Display-based parse failed)
    if [[ -z "$iata_found" && -n "$first_log_for_fallback" ]]; then
        iata_found=$(zcat "$first_log_for_fallback" | grep -m1 "IATA='" | sed -E "s/.*IATA='([^']+)'.*/\1/")
    fi

    # Report results as per requirements
    if [[ "$logs_count" -eq 0 ]]; then
        echo "$serial,no logs,${iata_found},0" >> "$output"
    elif $box_all_zero_30days && [[ "$logs_count" -gt 0 ]]; then
        echo "$serial,since 30 days,${iata_found},${logs_count}" >> "$output"
    fi
done

echo "Report generated: $output"