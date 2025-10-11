#!/bin/bash

# Script Information
################################################################################################
#     Author: SK2                                                                              #
#     Date: 20-03-2024                                                                         #
#     Purpose: Check if MongoDB port is open for the proxy boxes in U2                         #
################################################################################################

connect_and_check_mongo_port() {
    local box_id=$1
    local check_command='curl --connect-timeout 5 afl-shard-00-02.tal51.mongodb.net:27017'
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
        # Use proxy to SSH to the real box and execute the check command
        ssh -o "ProxyCommand=ssh -q -W %h:%p root@$real_pb" -o StrictHostKeyChecking=no root@$real_box_ip "$check_command"
    else
        # Direct SSH to the box and execute the check command
        ssh -o StrictHostKeyChecking=no root@$real_box_ip "$check_command"
    fi
}

# Main loop to connect to each test box and check if MongoDB port is open
while IFS= read -r box <&3; do
    echo "Connecting to box: $box"
    # Appending both the box id and the connection result to the file
    echo "Box: $box" >> mongodb_port_check_results.txt
    connect_and_check_mongo_port "$box" >> mongodb_port_check_results.txt
done 3< U2proxies.txt
echo "Done"
