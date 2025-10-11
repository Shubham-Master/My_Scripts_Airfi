#!/bin/bash

# Script Information
################################################################################################
#     Author: SK2                                                                              #
#     Date: 14-08-2024                                                                         #
#     Purpose: Running FWupgrade in all the online boxes for specific IATA                     #
################################################################################################

if [ -z "$1" ]; then
    echo "Usage: $0 IATA"
    echo "Example: $0 IU"
    exit 1
fi

IATA="$1"  # Get the IATA code from the command-line argument

fetch_serials() {
    curl -s "https://${API_USER}:${API_PASS}@airfi-disco.herokuapp.com/api/devices/customerCode/$IATA" | \
    jq -r '.[] | select((.isSuperProxy == true or .mode.name == "PROXY") and .purpose.name == "Production") | .serial'
}

connect_and_run_custom_command() {
    local box_id=$1
    local custom_command='/usr/local/airclient//multi-execute-iata.sh "/usr/local/airclient/fwupgrade.sh"'
    local real_box_ip=$(cat /etc/openvpn/clients/$box_id 2>/dev/null)
    if [[ -z "$real_box_ip" ]]; then
        local PB=$(curl -s "https://${API_USER}:${API_PASS}@airfi-disco.herokuapp.com/api/device/$box_id" | jq -r '.proxy.serial')
        if [[ -z "$PB" ]]; then
            echo "Proxy box serial not found for $box_id"
            return 1
        fi
        local real_pb=$(cat /etc/openvpn/clients/$PB)
        local output=$(ssh -o StrictHostKeyChecking=no root@$real_pb "cat /tmp/dnsmasq*.leases /tmp/dhcp*.leases 2>/dev/null | grep $box_id")
        real_box_ip=$(echo $output | awk '{print $3}')
        echo "Using proxy $real_pb to connect to $real_box_ip" >> firmware_multi_results.txt
        # Use proxy to SSH to the real box and execute the custom command in the foreground
        ssh -t -o "ProxyCommand=ssh -q -W %h:%p root@$real_pb" -o StrictHostKeyChecking=no root@$real_box_ip "$custom_command"
    else
        echo "Direct connection to $real_box_ip" >> firmware_multi_results.txt
        # Direct SSH to the box and execute the custom command in the foreground
        ssh -t -o StrictHostKeyChecking=no root@$real_box_ip "$custom_command"
    fi
    echo "Finished execution on $box_id with IP $real_box_ip" >> firmware_multi_results.txt
}

# Step 1: Fetch and Print All Serials
serials=($(fetch_serials))

# Check if serials are found
if [ ${#serials[@]} -eq 0 ]; then
    echo "No valid serials found for IATA $IATA. Please check the IATA code or your API credentials."
    exit 1
fi

echo "Serials to be processed:"
for box in "${serials[@]}"; do
    echo "Serial: $box"
done

# Step 2: Execute SSH Commands with a Delay
for box in "${serials[@]}"; do
    echo "Connecting to box: $box"
    echo "Box: $box" >> firmware_multi_results.txt
    connect_and_run_custom_command "$box" >> firmware_multi_results.txt

    # Sleep for 15 seconds before moving to the next box
    sleep 15
done

echo "Done"