#!/bin/bash

#########################################################################################################################
#                                                                                                                       #
#       Author  : SK2                                                                                                   #
#       Date    : 29/07/2024                                                                                            #
#       Purpose : The script emails the battery and other problems related details in the following format.             #
#                  box,iata,log,firstCharge,lastCharge,duration,shutdown_reason                                         #
#                                                                                                                       #
#########################################################################################################################

output="/home/logs/ROY/IO_dump/soldered_fuse_output_$(date +%Y%m%d).csv"
BatAbrGhoCsv="/home/logs/ROY/IO_dump/bat_abru_ghost.csv"
usbCsv="/home/logs/ROY/IO_dump/usb.csv"

get_charge() {
    local line=$1
    echo $(echo $line | grep -oP 'charge=-?\w+.?[\w\s]+(\(\K[\d]+)?')
}

#Deteting previously created boxes list
if [ -f /home/logs/ROY/IO_dump/soldered_fuses_boxes.txt ]; then
    rm -f /home/logs/ROY/IO_dump/soldered_fuses_boxes.txt
fi

# Delete existing dump csv if the script is re-run on same day
if [ -f /home/logs/ROY/IO_dump/soldered_fuse_output_$(date +%Y%m%d).csv ]; then
    rm -f "$output"
fi

#Fetching all the latest boxes with soldered fuses daily
curl 'https://script-user:ug34AD_1TfYajg-23_aMeQt@airfi-disco.herokuapp.com/api/devices?contentSyncStuck=false&hideOffline=false&onlyProduction=false&pagination=true&tags=,Soldered%20fuse&sorts=W3siZGVzYyI6dHJ1ZSwiaWQiOiJ2aWV3Q291bnQifV0=&filters=W3siaWQiOiJzbm9vemVkIiwidmFsdWUiOmZhbHNlfV0=&page=0&pageSize=3000' | jq -r '.rows[].serial' >/home/logs/ROY/IO_dump/soldered_fuses_boxes.txt

# Date for previouse day's logs
date=$(date -d "yesterday" +%Y%m%d)

while read -r box; do
    while read -r log; do
        lastOctet=$(echo $box | awk -F '.' '{print $NF}')
        # Extract first and last charge lines
        firstChargeline=$(zcat "$log" 2>/dev/null | grep "charge=" | head -n 1)
        lastChargeline=$(zcat "$log" 2>/dev/null | grep "charge=" | tail -n 1)

        #extracting the charges from respective sharge lines
        firstCharge=$(get_charge "$firstChargeline")
        lastCharge=$(get_charge "$lastChargeline")

        # Extract IATA code
        iata=$(zcat "$log" 2>/dev/null | grep ": IATA=" | awk -F "=" '{print $2}')

        # Extract shutdown reason
        shutdown_reason=$(zcat "$log" 2>/dev/null | egrep "$lastOctet /usr/local/airclient/airfi-cmd.sh: \-\-shutdown|$lastOctet /usr/local/airclient/airfi-cmd.sh: \-\-reboot" | tail -n 1 | awk '{print $NF}')

        # Extract start and end times from the filename
        start_time=$(echo "$log" | grep -oP '\d{8}_\d{6}' | head -1)
        end_time=$(echo "$log" | grep -oP '\d{8}_\d{6}' | tail -1)

        # Convert times to a format that can be used with 'date' command for calculation
        start_date=$(date -d "${start_time:0:4}-${start_time:4:2}-${start_time:6:2} ${start_time:9:2}:${start_time:11:2}:${start_time:13:2}" +%s)
        end_date=$(date -d "${end_time:0:4}-${end_time:4:2}-${end_time:6:2} ${end_time:9:2}:${end_time:11:2}:${end_time:13:2}" +%s)

        # Calculate the difference in seconds
        diff_seconds=$(echo "$end_date - $start_date" | bc)

        # Convert the difference in seconds to HH:MM:SS
        hours=$(echo "$diff_seconds / 3600" | bc)
        minutes=$(echo "($diff_seconds % 3600) / 60" | bc)
        seconds=$(echo "$diff_seconds % 60" | bc)

        # Format the duration as HH:MM:SS and store in a variable
        duration=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)

        # Output or process the collected data as needed
        # This handles the case for abrupt shutdowns and ghost shutdowns
        if [ -z $shutdown_reason ]; then
            if !(zcat $log 2>/dev/null | grep -q '/etc/init.d/rcK'); then
                shutdown_reason="ABRUPT_SHUTDOWN"
            fi
            if !(zcat $log 2>/dev/null | egrep -q "$lastOctet /usr/local/airclient/airfi-cmd.sh: \-\-shutdown|$lastOctet /usr/local/airclient/airfi-cmd.sh: \-\-reboot"); then
                shutdown_reason="FORCED_SHUTDOWN"
            fi
        fi

        echo "$box,$iata,$log,$firstCharge,$lastCharge,$duration,$shutdown_reason" >>$output
        echo "$box,$iata,$log,$firstCharge,$lastCharge,$duration,$shutdown_reason"

    done < <(ls -lrth /logs/"$box"/logfile-airfi-"$date"* 2>/dev/null | awk '{print $NF}')
done </home/logs/ROY/IO_dump/soldered_fuses_boxes.txt
cat "$output" | egrep -i "battery|forced|abrupt" >$BatAbrGhoCsv
cat "$output" | egrep -i "usb" >$usbCsv

# Variables
CSV_FILE_BAT="$BatAbrGhoCsv"
CSV_FILE_USB="$usbCsv"
RECIPIENT="priyadarshan.roy@airfi.aero, shubham.kr@airfi.aero, yash.anand@airfi.aero, akhila.kavi@airfi.aero, m.demoor@muco-group.com, marco.dorjee@airfi.aero, d.bogusz@cds-electronics.nl, job.heimerikx@airfi.aero, niels@muco-group.com, p.bartek@cds-electronics.nl, jalal.zriouil@airfi.aero"
SUBJECT="Soldered Fuses Daily report"
TEMP_HTML="/home/logs/ROY/IO_dump/info_tables.html"

# Temporary files to hold HTML content for each table
HTML_FILE1="/home/logs/ROY/IO_dump/bat_csv_table.html"
HTML_FILE2="/home/logs/ROY/IO_dump/usb_csv_table.html"

# Function to convert CSV to HTML table
convert_csv_to_html() {
    local csv_file="$1"
    local html_file="$2"

    awk -v OFS="\t" '
    BEGIN {
        print "<html><head><style>"
        print "body {font-family: Arial, sans-serif;}"
        print "table {width: 100%; border-collapse: collapse; margin: 20px 0;}"
        print "th, td {border: 1px solid #ddd; padding: 12px; text-align: left;}"
        print "th {background: #ff5300; color: white; font-size: 16px; font-weight: 600;}"
        print "tr:nth-child(even) {background-color: #f9f9f9;}"
        print "tr:hover {background-color: #f1f1f1;}"
        print "td {font-size: 14px;}"
        print "caption {font-size: 18px; font-weight: bold; margin: 10px;}"
        print "</style></head><body>"
        print "<table>"
        print "<tr>"
        print "<th>Box</th>"
        print "<th>IATA</th>"
        print "<th>Log</th>"
        print "<th>First Charge</th>"
        print "<th>Last Charge</th>"
        print "<th>Duration</th>"
        print "<th>Shutdown Reason</th>"
        print "</tr>"
    }
    {
        gsub(/"/, "", $0)  # Remove quotes if present
        split($0, fields, ",")
        print "<tr>"
        for (i = 1; i <= length(fields); i++) {
            print "<td>" fields[i] "</td>"
        }
        print "</tr>"
    }
    END {
        print "</table></body></html>"
    }' "$csv_file" >"$html_file"
}

# Check if the CSV files are empty and convert them if not
if [ -s "$CSV_FILE_BAT" ]; then
    convert_csv_to_html "$CSV_FILE_BAT" "$HTML_FILE1"
    TABLE1_PRESENT=true
else
    TABLE1_PRESENT=false
fi

if [ -s "$CSV_FILE_USB" ]; then
    convert_csv_to_html "$CSV_FILE_USB" "$HTML_FILE2"
    TABLE2_PRESENT=true
else
    TABLE2_PRESENT=false
fi

# Combine HTML tables into one email body
{
    echo "<html><body>"

    if [ "$TABLE1_PRESENT" = true ]; then
        echo "<h2 style=\"text-align: center;\">BATTERY ERRORS</h2>"
        cat "$HTML_FILE1"
    fi

    if [ "$TABLE2_PRESENT" = true ]; then
        echo "<h2 style=\"text-align: center;\">RESETS</h2>"
        cat "$HTML_FILE2"
    fi

    echo "</body></html>"
} >"$TEMP_HTML"
# Send the email with both tables in HTML format
cat "$TEMP_HTML" | mailx -a "Content-Type: text/html" -s "$SUBJECT" "$RECIPIENT"

# Clean up temporary files
rm "$HTML_FILE1" "$HTML_FILE2" "$TEMP_HTML" "$BatAbrGhoCsv" "$usbCsv"