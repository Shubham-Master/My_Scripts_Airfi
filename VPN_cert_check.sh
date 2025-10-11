#!/bin/bash


# Script Information
################################################################################################
#     Author: SK2                                                                              #
#     Date: 29-05-2024                                                                         #
#     Purpose: Check wether VPN cert is installed in the boxes or not                          #
################################################################################################


# Input file containing box IPs
input_file="y4.txt"

# Output file
output_file="vpn_result.txt"

# Temporary files to store box lists
with_cert="with_cert.txt"
without_cert="without_cert.txt"

# Clear output files if they exist
> "$output_file"
> "$with_cert"
> "$without_cert"

# Read each line (box IP) from the input file
while IFS= read -r box_ip; do
    echo "Checking $box_ip..."
    
    # Fetch the content and check for the vpn-certificate
    if curl -s "https://script-user:ug34AD_1TfYajg-23_aMeQt@airfi-disco.herokuapp.com/api/device/$box_ip/content" | jq -e '.[].manifestId' | grep -q 'manifest/app/airfi/vpn-certificate'; then
        echo "$box_ip has vpn-certificate"
        echo "$box_ip" >> "$with_cert"
    else
        echo "$box_ip does not have vpn-certificate"
        echo "$box_ip" >> "$without_cert"
    fi
done < "$input_file"

# Combine results into the output file with clear separators
echo "BOXES with VPN cert present" > "$output_file"
cat "$with_cert" >> "$output_file"
echo -e "\nBOXES without VPN cert" >> "$output_file"
cat "$without_cert" >> "$output_file"

# Cleanup temporary files
rm "$with_cert" "$without_cert"

echo "Results saved to $output_file"
