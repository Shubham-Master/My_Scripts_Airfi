#!/bin/bash

# Script Information
################################################################################################
#     Author: SK2                                                                              #
#     Date: 02-07-2024                                                                         #
#     Purpose: Check whether manifest is installed in the boxes or not                         #
################################################################################################

# Input file containing box IPs
input_file="mra_boxes.txt"

# Output file
output_file="mra_result.txt"

# Temporary files to store box lists
with_manifest="with_manifest.txt"
without_manifest="without_manifest.txt"

# Clear output files if they exist
> "$output_file"
> "$with_manifest"
> "$without_manifest"

# Read each line (box IP) from the input file
while IFS= read -r box_ip; do
    echo "Checking $box_ip..."

    # Fetch the content and check for the manifest
    if curl -s "https://script-user:ug34AD_1TfYajg-23_aMeQt@airfi-disco.herokuapp.com/api/device/$box_ip/content" | jq -e '.[].manifestId' | grep -q 'manifest/mars/video/rayaandthelastdragon'; then
        echo "$box_ip has manifest"
        echo "$box_ip" >> "$with_manifest"
    else
        echo "$box_ip does not have manifest"
        echo "$box_ip" >> "$without_manifest"
    fi
done < "$input_file"

# Combine results into the output file with clear separators
echo "BOXES with manifest present" > "$output_file"
cat "$with_manifest" >> "$output_file"
echo -e "\nBOXES without manifest" >> "$output_file"
cat "$without_manifest" >> "$output_file"

# Cleanup temporary files
rm "$with_manifest" "$without_manifest"

echo "Results saved to $output_file"
