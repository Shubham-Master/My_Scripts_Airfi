#!/bin/bash

# Script Information
################################################################################################
#     Author: SK2                                                                              #
#     Date: 22-02-2024                                                                         #
#     Purpose: Check for the latest charge and voltage of the test boxes in factory            #
################################################################################################

connect_and_run_command() {
    local box_id=$1
    local grep_command='cat /logs/current | egrep -i "STC3115\[mode"|tail -n 2'
    real_box_ip=$(cat /etc/openvpn/clients/$box_id 2>/dev/null)
    if [[ -z "$real_box_ip" ]]; then
        PB=$(curl -s "https://script-user:ug34AD_1TfYajg-23_aMeQt@airfi-disco.herokuapp.com/api/device/$box_id" | jq -r '.proxy.serial')
        if [[ -z "$PB" ]]; then
            echo "Proxy box serial not found for $box_id"
            return 1
        fi
        real_pb=$(cat /etc/openvpn/clients/$PB)
        output=$(ssh -o StrictHostKeyChecking=no root@$real_pb "cat /tmp/dnsmasq*.leases /tmp/dhcp*.leases 2>/dev/null | grep $box_id")
        real_box_ip=$(echo $output | awk '{print $3}')
        # Use proxy to SSH to the real box and execute the grep command
        ssh -o "ProxyCommand=ssh -q -W %h:%p root@$real_pb" -o StrictHostKeyChecking=no root@$real_box_ip "$grep_command"
    else
        # Direct SSH to the box and execute the grep command
        ssh -o StrictHostKeyChecking=no root@$real_box_ip "$grep_command"
    fi
}

# Main loop to connect to each test box and grep for the specific log pattern
while IFS= read -r box <&3; do
    echo "Connecting to box: $box"
    connect_and_run_command "$box"
done 3< test_boxes
echo "Done"