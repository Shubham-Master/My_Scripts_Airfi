import requests

# Function to read IP addresses from a file
def read_ip_addresses(file_path):
    with open(file_path, 'r') as file:
        return [line.strip() for line in file.readlines()]

# Function to update firmware
def update_firmware(ip, new_fw):
    base_url = "https://airfi-disco.herokuapp.com/api/device/"
    username = "script-user"
    password = "ug34AD_1TfYajg-23_aMeQt"
    url = "{}{}".format(base_url, ip)
    response = requests.patch(url, json={"assignedFirmware": new_fw}, auth=(username, password))
    if response.status_code == 200:
        print("Successfully updated firmware for {} to {}".format(ip, new_fw))
    else:
        print("Failed to update firmware for {}. Status code: {}, Response: {}".format(ip, response.status_code, response.text))

# Main function
def main():
    file_path = 'developer_boxes.txt'
    ip_addresses = read_ip_addresses(file_path)

    new_fw = input("Enter the firmware version to assign: ")

    for ip in ip_addresses:
        update_firmware(ip, new_fw)

if __name__ == "__main__":
    main()