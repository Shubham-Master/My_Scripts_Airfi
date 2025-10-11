#!/bin/bash

#################################################################################################
#                                                                                               #
#    Author: SK2                                                                                #
#    Date: 19-03-2025                                                                           #
#    Notes: This script searches for the keyword supplied in all the logs for a date and IATA   #
#                                                                                               #
#################################################################################################


[[ $# != 3 ]] && {
    echo "Usage: logs-search-with-keyword.sh IATA DATE Keyword"
    echo "Example: logs-search-with-keyword.sh TR 20211109 'Winner shard'"
    exit 1
}

iata=$1
iata=${iata^^}
date=$2
key="$3"

echo "Searching for '$key' in logs for IATA: $iata on Date: $date"

# Get box IP list from DISCO
/usr/local/bin/get-box-ip-from-disco.sh $iata > /tmp/.box-list-$iata

# Validate if the IP list is empty
if [[ ! -s /tmp/.box-list-$iata ]]; then
    echo "Error: No box IPs found for IATA: $iata"
    exit 1
fi

# Loop through the IP list
for ip in $(cat /tmp/.box-list-$iata); do
    echo "Checking logs for box: $ip"
    found=0

    # Validate if there are any matching log files
    log_files=$(ls /logs/$ip/logfile-airfi-*$date*.gz 2>/dev/null)
    if [[ -z "$log_files" ]]; then
        echo "No log files found for IP: $ip on $date"
        continue
    fi

    for logfile in $log_files; do
        match=$(zgrep -i "$key" "$logfile" 2>/dev/null)
        if [[ ! -z "$match" ]]; then
            if [[ $found -eq 0 ]]; then
                echo "✅ Found in box: $ip"
                found=1
            fi
            echo "📄 Logfile: $logfile"
            echo "$match"
        fi
    done

    if [[ $found -eq 0 ]]; then
        echo "❌ Not found in box: $ip"
    fi
done
