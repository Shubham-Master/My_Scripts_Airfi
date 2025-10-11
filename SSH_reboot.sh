#!/bin/bash

# IP address of the machine
IP="192.168.244.2"

function ssh_and_perform_tasks {
    # Open an SSH session and perform all tasks
    ssh root@$IP <<'EOF'
    echo "Running airfi-cmd.sh --list..."
    # Run the command and check for any output
     if command_output=$(airfi-cmd.sh --list) && [[ -n "$command_output" ]]; then
        echo "Received output from airfi-cmd.sh --list: $command_output"
        
        # Loop until "PAX" is found in the logs
        while true; do
            echo "Checking for 'PAX' in logs..."
            if pax_result=$(cat /logs/current | grep 'PAX') && [[ -n "$pax_result" ]]; then
                echo "Found 'PAX' in logs. Proceeding to schedule a reboot..."
                # Schedule the reboot command to be executed after 60 seconds
                sleep 60 &&  airfi-cmd.sh --reboot-flight &
                break
            else
                echo "'PAX' not found, checking again..."
                sleep 10  # Wait for 10 seconds before checking again
            fi
        done
    else
        echo "No output received from airfi-cmd.sh --list, trying again..."
    fi
EOF
}

function continuous_operation {
    while true; do
        # Ping until the host is reachable
        while ! ping -c 1 $IP &>/dev/null; do
            echo "Pinging $IP until it becomes reachable..."
            sleep 5 # Wait for 5 seconds before pinging again
        done

        # SSH once and perform all tasks
        ssh_and_perform_tasks

        # Wait for 200 seconds after executing the reboot command
        echo "Tasks completed. Sleeping for 200 seconds before restarting the process..."
        sleep 200
    done
}

# Start the continuous operation
continuous_operation
