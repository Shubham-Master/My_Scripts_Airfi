#!/bin/bash

########################################################################################################
#                                                                                                      #
#       Author  : SK2                                                                                  #
#       Date    : 17/02/2025                                                                           #
#       Purpose : The script fetches all proxy details, identifies offline proxies, & mail the report. #
#                                                                                                      #
########################################################################################################

OUTPUT="/home/logs/SK2/Offline_Proxies_Report_$(date +%Y%m%d).csv"
HTML_FILE="/home/logs/SK2/Offline_Proxies_Report.html"
RECIPIENT="shubham.kr@airfi.aero, utkarsh.saxena@airfi.aero, priyadarshan.roy@airfi.aero, rohit.malaviya@airfi.aero"
SUBJECT=" Proxies Daily Report  - $(date +'%Y-%m-%d')"

# Delete old reports if script is rerun on the same day
rm -f "$OUTPUT" "$HTML_FILE"

# Fetch the list of boxes
BOXES=$(curl -s 'https://script-user:ug34AD_1TfYajg-23_aMeQt@airfi-disco.herokuapp.com/api/devices?config=false&contentSyncStuck=false&hideOffline=false&onlyProduction=false&pagination=true&tags=false&sorts=W3siZGVzYyI6dHJ1ZSwiaWQiOiJ2aWV3Q291bnQifV0=&filters=W3siaWQiOiJzbm9vemVkIiwidmFsdWUiOiIwIn0seyJpZCI6InB1cnBvc2UiLCJ2YWx1ZSI6IlByb2R1Y3Rpb24ifSx7ImlkIjoib3BlcmF0aW9uYWxTdGF0dXMiLCJ2YWx1ZSI6IkJveCBpbiB1c2UifSx7ImlkIjoibW9kZSIsInZhbHVlIjoiUFJPWFkifV0=&page=0&pageSize=300' | jq -r '.rows[].serial')

# Get current time
CURRENT_TIME=$(date +%s)

# Function to convert seconds to a human-readable format
human_readable_time() {
    local seconds=$1
    local days=$((seconds / 86400))
    local hours=$(((seconds % 86400) / 3600))

    if ((seconds < 3600)); then
        echo "$((seconds / 60)) min "
    elif ((seconds < 86400)); then
        echo "$hours hrs "
    elif ((days == 1)); then
        echo "1 day "
    elif ((days < 7)); then
        echo "$days days "
    elif ((days == 7)); then
        echo " 1 week "
    elif ((days < 30)); then
        echo "$((days / 7)) week(s) "
    else
        echo "$((days / 30)) month(s) "
    fi
}

# Process each box
echo "Serial,IATA,Last Seen,Last Content Sync,Remarks" >"$OUTPUT"

for BOX in $BOXES; do
    RESPONSE=$(curl -s "https://script-user:ug34AD_1TfYajg-23_aMeQt@airfi-disco.herokuapp.com/api/device/$BOX")

    LAST_SEEN=$(echo "$RESPONSE" | jq -r '.lastSeenTimestamp')
    LAST_SYNC=$(echo "$RESPONSE" | jq -r '.lastContentSyncTimestamp')
    IATA=$(echo "$RESPONSE" | jq -r '.currentCustomer.customerCode')

    # Convert timestamps to seconds
    LAST_SEEN_SEC=$(date -d "$LAST_SEEN" +%s 2>/dev/null || echo 0)
    LAST_SYNC_SEC=$(date -d "$LAST_SYNC" +%s 2>/dev/null || echo 0)

    REMARKS="OK"

    if [ "$LAST_SEEN_SEC" -eq 0 ]; then
        REMARKS="No data available"
    else
        SEEN_DIFF=$((CURRENT_TIME - LAST_SEEN_SEC))
        SYNC_DIFF=$((CURRENT_TIME - LAST_SYNC_SEC))

        if ((SEEN_DIFF > 86400)); then
            REMARKS="Proxy offline since $(human_readable_time "$SEEN_DIFF")"
        elif ((SYNC_DIFF > 86400)); then
            REMARKS="ACDC not completed since $(human_readable_time "$SYNC_DIFF")"
        fi
    fi

    if [[ "$REMARKS" != "OK" ]]; then
        echo "$BOX,$IATA,$(date -d "@$LAST_SEEN_SEC" '+%Y-%m-%d at %H:%M:%S'),$(date -d "@$LAST_SYNC_SEC" '+%Y-%m-%d at %H:%M:%S'),$REMARKS" >>"$OUTPUT"
    fi
done

# Convert CSV to HTML with better contrast
awk -F',' '
BEGIN {
    print "<html><head><style>"
    print "body { font-family: Arial, sans-serif; background-color: #181818; color: white; text-align: center; }"
    print "h2 { text-align: center; font-size: 24px; font-weight: bold; }"
    print "table { width: 80%; margin: 20px auto; border-collapse: collapse; background: #202020; border-radius: 10px; overflow: hidden; }"
    print "th, td { padding: 15px; border: 2px solid #444; text-align: center; }"  # Thicker borders
    print "th { background: #ff5300; color: white; font-size: 16px; font-weight: 600; }"
    print "td { font-size: 14px; color: #ddd; }"
    print "tr:nth-child(even) { background-color: #292929; }"
    print "tr:hover { background-color: #333333; }"
    print ".fail { background: #444; color: white; font-weight: bold; }"
    print ".serial, .iata { color: #fff; font-weight: bold; }" # Ensures Serial & IATA are visible
    print "</style></head><body>"
    print "<h2>⚠️ Proxies Failure Report ⚠️</h2>"
    print "<table><tr><th>Serial</th><th>IATA</th><th>Last Seen</th><th>Last Content Sync</th><th>Remarks</th></tr>"
}
NR > 1 {
    print "<tr>"
    print "<td class=\"serial\">" $1 "</td>"
    print "<td class=\"iata\">" $2 "</td>"
    print "<td class=\"fail\">" $3 "</td>"
    print "<td class=\"fail\">" $4 "</td>"
    print "<td class=\"fail\">" $5 "</td>"
    print "</tr>"
}
END { print "</table></body></html>" }
' "$OUTPUT" >"$HTML_FILE"

# Send the email
mailx -a "Content-Type: text/html" -s "$SUBJECT" "$RECIPIENT" <"$HTML_FILE"

# Clean up
rm -f "$HTML_FILE"

echo "Email sent successfully to $RECIPIENT!"
