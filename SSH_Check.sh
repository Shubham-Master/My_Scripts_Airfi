#!/bin/bash

# Script Information
################################################################################################
#     Author: SK2                                                                              #
#     Date: 15-05-2024                                                                         #
#     Purpose: Check if we can SSH into proxies or not                                         #
################################################################################################

# Function to fetch box serials from the API
fetch_box_serials() {
    curl -s "https://script-user:ug34AD_1TfYajg-23_aMeQt@airfi-disco.herokuapp.com/api/devices?config=false&contentSyncStuck=false&hideOffline=true&onlyProduction=false&pagination=true&tags=false&sorts=W3siZGVzYyI6dHJ1ZSwiaWQiOiJsYXN0U2VlblRpbWVzdGFtcCJ9XQ==&filters=W3siaWQiOiJzbm9vemVkIiwidmFsdWUiOmZhbHNlfSx7ImlkIjoibW9kZSIsInZhbHVlIjoiUFJPWFkifV0=&page=0&pageSize=100" | jq -r '.devices[].serial'
}


connect_and_check_() {
    local box_id=$1
    local check_command='airfi-cmd.sh --list'
    local real_box_ip=$(cat /etc/openvpn/clients/$box_id 2>/dev/null)
    if [[ -z "$real_box_ip" ]]; then
        local PB=$(curl -s "https://script-user:ug34AD_1TfYajg-23_aMeQt@airfi-disco.herokuapp.com/api/devices?config=false&contentSyncStuck=false&hideOffline=true&onlyProduction=false&pagination=true&tags=false&sorts=W3siZGVzYyI6dHJ1ZSwiaWQiOiJsYXN0U2VlblRpbWVzdGFtcCJ9XQ==&filters=W3siaWQiOiJzbm9vemVkIiwidmFsdWUiOmZhbHNlfSx7ImlkIjoibW9kZSIsInZhbHVlIjoiUFJPWFkifV0=&page=0&pageSize=100" | jq -r '.proxy.serial')
        if [[ -z "$PB" ]]; then
            echo "Proxy box serial not found for $box_id"
            return 1
        fi
        local real_pb=$(cat /etc/openvpn/clients/$PB)
        local output=$(ssh -o StrictHostKeyChecking=no root@$real_pb "cat /tmp/dnsmasq*.leases /tmp/dhcp*.leases 2>/dev/null | grep $box_id")
        real_box_ip=$(echo $output | awk '{print $3}')
        # Use proxy to SSH to the real box and execute the check command
        ssh -o "ProxyCommand=ssh -q -W %h:%p root@$real_pb" -o StrictHostKeyChecking=no root@$real_box_ip "$check_command"
    else
        # Direct SSH to the box and execute the check command
        ssh -o StrictHostKeyChecking=no root@$real_box_ip "$check_command"
    fi
}

# Fetch box serials from the API
box_serials=$(fetch_box_serials)

# Main loop to connect to each test box and check if MongoDB port is open
for box in $box_serials; do
    echo "Connecting to box: $box"
    echo "Box: $box" >> check_results.txt
    connect_and_check_"$box" >> check_results.txt
done

echo "Done"
