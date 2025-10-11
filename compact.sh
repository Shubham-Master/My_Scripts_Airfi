#!/bin/bash

# Script Information
################################################################################################
#     Author: SK2                                                                              #
#     Date: 19-07-2024                                                                         #
#     Purpose: Compact CouchDB databases on AirFi boxes                                        #
################################################################################################

# Function to connect to the AirFi box using SSH and compact CouchDB databases
compact_couchdb() {
    local box_id=$1
    local real_box_ip=$(cat /etc/openvpn/clients/$box_id 2>/dev/null)
    if [[ -z "$real_box_ip" ]]; then
        local PB=$(curl -s "https://script-user:ug34AD_1TfYajg-23_aMeQt@airfi-disco.herokuapp.com/api/device/$box_id" | jq -r '.proxy.serial')
        if [[ -z "$PB" ]]; then
            echo "Proxy box serial not found for $box_id"
            return 1
        fi
        local real_pb=$(cat /etc/openvpn/clients/$PB)
        local output=$(ssh -o StrictHostKeyChecking=no root@$real_pb "cat /tmp/dnsmasq*.leases /tmp/dhcp*.leases 2>/dev/null | grep $box_id")
        real_box_ip=$(echo $output | awk '{print $3}')
        # Use proxy to SSH to the real box and check for .compact and compact databases if necessary
        ssh -o "ProxyCommand=ssh -q -W %h:%p root@$real_pb" -o StrictHostKeyChecking=no root@$real_box_ip '
            if [ -e /media/couchdb/databases/.compact ]; then
                echo "Compact file is present on '$box_id'"
            else
                echo "Compact file is not present on '$box_id', compacting databases..."
                for file_path in /media/couchdb/databases/*couch; do
                    db_name=$(basename "${file_path%.*}")
                    curl -X POST -H "Content-Type: application/json" "http://admin:V3ryS3cur3@localhost:5984/$db_name/_compact"
                done
            fi
        '
    else
        # Direct SSH to the box and check for .compact and compact databases if necessary
        ssh -o StrictHostKeyChecking=no root@$real_box_ip '
            if [ -e /media/couchdb/databases/.compact ]; then
                echo "Compact file is present on '$box_id'"
            else
                echo "Compact file is not present on '$box_id', compacting databases..."
                for file_path in /media/couchdb/databases/*couch; do
                    db_name=$(basename "${file_path%.*}")
                    curl -X POST -H "Content-Type: application/json" "http://admin:V3ryS3cur3@localhost:5984/$db_name/_compact"
                done
            fi
        '
    fi
}

# Fetch the serials from the API
serials=$(curl -s 'https://script-user:ug34AD_1TfYajg-23_aMeQt@airfi-disco.herokuapp.com/api/devices?config=false&contentSyncStuck=false&hideOffline=true&onlyProduction=false&pagination=true&tags=false&sorts=W3siZGVzYyI6dHJ1ZSwiaWQiOiJ2aWV3Q291bnQifV0=&filters=W3siaWQiOiJzbm9vemVkIiwidmFsdWUiOmZhbHNlfSx7ImlkIjoiY3VycmVudEN1c3RvbWVyIiwidmFsdWUiOiJZNCJ9XQ==&page=0&pageSize=50' | jq -r '.rows[].serial')

# Iterate over each serial and perform the required actions
for serial in $serials; do
    echo "Connecting to box: $serial"
    compact_couchdb $serial
done

echo "Done"
