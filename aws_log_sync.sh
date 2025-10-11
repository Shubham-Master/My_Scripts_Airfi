#!/bin/bash

if [[ -f /tmp/.sync-from-s3 ]]; then
    echo 'Script already running. Exiting...'
    exit 0
fi

touch /tmp/.sync-from-s3

# Get the current month in YYYYMM format
date=$(date +%Y%m)

echo "Syncing logs for current month: $date"

sync_logs() {
    local iata=$1
    echo "Syncing for $iata..."
    while read -r box; do
        echo $box
         aws s3 sync s3://airserver-backups/logs/$box/ /logs/$box/ --exclude "*" --include "logfile-*-${date}*.gz"
    done < <(curl -s "https://${API_USER}:${API_PASS}@airfi-disco.herokuapp.com/api/devices/customerCode/$iata" | jq -r '.[] | select(.isSuperProxy == false and .purpose.name == "Production") | .serial')
    echo "Syncing done for $iata."
}

# Add more IATAs here
for iata in "G9" "XX" "YY" "ZZ"; do
    sync_logs "$iata"
done

rm /tmp/.sync-from-s3
echo "Exiting..."
