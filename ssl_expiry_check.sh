#!/bin/sh

# Configuration
API_KEY="RcVmDT37RnquUzoC9LCuhR4J"
DOMAIN="www.ife.berniq.com"
EXPIRY_FILE="/media/vendors/airfi/patch-nginx/expiry.txt"
REQUESTER_EMAIL="noreply@airfi.aero"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to convert date to seconds since epoch
date_to_seconds() {
    input_date="$1"

    # Extract date components
    year=$(echo "$input_date" | cut -d'-' -f1)
    month=$(echo "$input_date" | cut -d'-' -f2)
    day=$(echo "$input_date" | cut -d'-' -f3)

    # Pad month and day with leading zeros if needed
    month=$(printf "%02d" "$month")
    day=$(printf "%02d" "$day")
    normalized_date="$year-$month-$day"

    # Try different date commands based on system
    if command_exists gdate; then
        # If GNU date is installed on macOS
        gdate -d "$normalized_date" +%s 2>/dev/null
    elif date -j >/dev/null 2>&1; then
        # BSD date (macOS)
        date -j -f "%Y-%m-%d" "$normalized_date" "+%s" 2>/dev/null
    else
        # Busybox date
        date -D "%Y-%m-%d" -d "$normalized_date" +%s 2>/dev/null
    fi
}

# Function to check if SSL certificate is expiring soon
check_ssl_expiry() {
    if [ ! -f "$EXPIRY_FILE" ]; then
        echo "Error: Expiry file $EXPIRY_FILE not found" >&2
        return 1
    fi

    expiry_date=$(cat "$EXPIRY_FILE")
    if [ -z "$expiry_date" ]; then
        echo "Error: Expiry file is empty" >&2
        return 1
    fi

    expiry_seconds=$(date_to_seconds "$expiry_date")
    if [ $? -ne 0 ] || [ -z "$expiry_seconds" ]; then
        echo "Error converting date: $expiry_date" >&2
        return 1
    fi

    current_seconds=$(date +%s)
    seconds_remaining=$((expiry_seconds - current_seconds))
    days_remaining=$((seconds_remaining / 86400))

    echo "$days_remaining"
}

# Function to check if an unresolved incident already exists
check_existing_incident() {
    domain="$1"
    incident_title="SSL Certificate Expiring Soon - $domain"
    cache_file="/media/vendors/airfi/patch-nginx/alerts.json"

    # If cache file exists, assume an incident is already reported
    if [ -f "$cache_file" ]; then
        echo "Found existing unresolved incident for $domain (cached)"
        return 0 # Incident exists
    fi

    # Get list of unresolved incidents from API
    response=$(curl -s -X GET \
        -H "Authorization: Bearer $API_KEY" \
        "https://uptime.betterstack.com/api/v3/incidents?resolved=false")

    # Use jq to check for existing incident by cause field
    exists=$(echo "$response" | jq -r --arg title "$incident_title" \
        '.data[] | select(.attributes.cause == $title) | .id')

    if [ -n "$exists" ]; then
        echo "Found existing unresolved incident for $domain"
        # Cache the response only if an incident exists
        echo "$response" > "$cache_file"

        return 0 # Incident exists
    fi

    return 1 # No incident exists
}
# Function to create incident on Betterstack
create_betterstack_incident() {
    domain="$1"
    days="$2"

    # First check if an incident already exists
    if check_existing_incident "$domain"; then
        echo "Incident already exists for $domain. Skipping creation."
        return 0
    fi

    summary="SSL Certificate Expiring Soon - $domain"
    description="SSL certificate for $domain will expire in $days days. Please take action to renew the certificate before expiration."

    # Create JSON payload using printf for maximum compatibility
    payload=$(printf '{
    "name": "Box SSL Expiry Alert",
    "summary": "%s",
    "requester_email": "%s",
    "description": "%s"
}' "$summary" "$REQUESTER_EMAIL" "$description")

    # Send request to Betterstack API
    response=$(curl -s -X POST \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "https://uptime.betterstack.com/api/v3/incidents")

    # Use basic grep for maximum compatibility
    if [ $? -eq 0 ] && echo "$response" | grep "\"id\":" >/dev/null 2>&1; then
        echo "SSL-Error-Alert: $description"
        echo "Successfully created incident for $domain"
        return 0
    else
        echo "Failed to create incident: $response"
        return 1
    fi
}

# Main execution
main() {
    days_remaining=$(check_ssl_expiry)
    result=$?

    if [ $result -ne 0 ]; then
        exit 1
    fi

    # Create incident if certificate is expiring within 30 days
    if [ "$days_remaining" -lt 30 ]; then
        create_betterstack_incident "$DOMAIN" "$days_remaining"
    else
        echo "Certificate for $DOMAIN is not expiring soon ($days_remaining days remaining)"
    fi
}

# Run main function
main