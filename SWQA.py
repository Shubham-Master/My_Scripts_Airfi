#!/usr/bin/python
import os
from time import sleep

# File path where the AirFi test boxes' IPs are stored
QA_BOXES_FILE = "/home/embed/.airfi-qa-boxes.txt"

# Airline IATA code, used in testing
IATA = "u2"

# URL for the AirFi device management service DISCO
DISCO_URL = "https://box-firmware:sun-reactive-collaboration@airfi-disco.herokuapp.com/api/device/"

# Function to connect the factory laptop to an AirFi Box's WiFi network
def connect_box_in_airfi(boxip):
    ssid = "TEST-" + boxip  # SSID format for the WiFi network
    cmd = "nmcli -w 30 dev wifi connect " + ssid  # Command to connect to the WiFi network
    if os.system(cmd) == 0:  # Check if the command executed successfully
        print("Factory Laptop is successfully connected to the AirFi Box wifi:" + ssid)
        return True
    else:
        print("Factory Laptop failed to connect with the AirFi Box wifi:" + ssid)
        return False

# Function to trigger the software QA test on the AirFi Box
def trigger_sw_qa_test(boxip):
    # Clear the content of the test result file before starting the test
    test_result_file = "/tmp/sw_test_result"
    with open(test_result_file, 'w') as fp:
        pass  # Opening in 'w' mode truncates the file, clearing its content

    print("Running the AirFi SW QA Test for " + boxip)
    cmd = "./start-test.sh " + IATA + " " + boxip + " true" # Command to start the software test
    print(cmd)
    os.system(cmd)  # Execute the command

# List to keep track of tested boxes in one script run
tested_boxes = []

# Main loop to continuously scan and test AirFi Boxes
while True:
    print("===============Scanning the AirFi Test Boxes==============")
    # List available WiFi networks and filter for AirFi test boxes, then save to file
    cmd = "nmcli d wifi | grep TEST-10.0. | awk -F'[ ]+' '{print $3}' > " + QA_BOXES_FILE
    os.system(cmd)  # Execute the command to refresh the list of test boxes

    # Open the file with test box IPs and read the entries
    with open(QA_BOXES_FILE, 'r') as file:
        entries = file.readlines()
        entries = [entry.strip() for entry in entries]  # Clean up entries by removing newline characters

    # Loop through each test box entry
    for entry in entries:
        print(entry)
        test = entry.split("-")
        serial = test[1]  # Extract the box serial number
        print("Box-serial: " + repr(serial))

        # Check if the box has not been tested yet
        if repr(serial) not in tested_boxes:
            if connect_box_in_airfi(serial):  # Attempt to connect to the box's WiFi
                sleep(60)  # Wait for connection to stabilize
                trigger_sw_qa_test(serial)  # Start the software QA test
            else:
                continue  # Skip to the next box if connection fails
        else:
            # Skip testing if the box has already been tested
            print("The box " + repr(serial) + " has already been tested, skipping to the next available box")
            continue

        # Default test result
        result = "FAIL"
        # Check if a test result file exists and read the result
        if os.path.isfile("/tmp/sw_test_result"):
            with open("/tmp/sw_test_result", 'r') as fp:
                result = fp.readline().strip()  # Use strip() to remove any newline characters

        # Process the test result
        if result == "PASS":
            # Mark the hardware as QA passed and initiate reboot
            cmd = "ssh root@172.22.0.1 '/etc/init.d/S96hardware-sanity update_clean QA_OK &'"
            os.system(cmd)
            sleep(10)  # Wait before re-executing the command for reboot
            print("result=PASS, rebooting Box-serial: " + repr(serial) + "\n")
            os.system(cmd)  # Reboot the box
            if repr(serial) not in tested_boxes:
                tested_boxes.append(repr(serial))  # Add the box to the list of tested boxes

            # Update the software QA test result in the DISCO
            cmd = "curl -X PATCH -H \"Content-Type: application/json\" -d '{\"isSwTestPassed\": true }' " + DISCO_URL + serial
            print("PASS-cmd: " + repr(cmd) + "\n")
        else:
            # Handle the test fail scenario
            cmd = "ssh root@172.22.0.1 '/etc/init.d/S96hardware-sanity update_clean QA_FAIL'"
            os.system(cmd)

            # Update the software QA test result as failed
            cmd = "curl -X PATCH -H \"Content-Type: application/json\" -d '{\"isSwTestPassed\": false }' " + DISCO_URL + serial
            print("FAIL-cmd: " + repr(cmd) + "\n")

        # Attempt to reconnect the factory laptop to the office WiFi after testing
        if os.system("nmcli dev wifi connect AirFi-office") == 0:
            print("Factory Laptop is connected to the AirFi-office")

        sleep(3)

        # Execute the command to update the management service with the test result
        if os.system(cmd) == 0:
            print("Updated the SW QA Result to the disco")
        else:
            print("Failed to update the SW QA Result to the disco")
        # If the box passed the test, update its operational status accordingly
        if result == "PASS":
            cmd = "curl -X PATCH -H \"Content-Type: application/json\" -d '{ \"operationalStatus\": \"Box ready to ship\" }' " + DISCO_URL + serial
            if os.system(cmd) == 0:
                print("Updated the Box operational status to \"Box ready to ship\"")
            else:
                print("Failed to Update the Box operational status to \"Box ready to ship\"")

    sleep(60)  # Wait before starting the next scan cycle