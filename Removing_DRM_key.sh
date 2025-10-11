#!/bin/bash

# First, retrieve the list of manifest IDs and store them in a variable
manifest_ids=$(curl -s http://admin:V3ryS3cur3@localhost:5984/installed-manifests-3l/_all_docs | grep drmkey | grep -o '"id":"[^"]*"' | sed 's/"id":"\([^"]*\)"/\1/' | sed 's/\//%2f/g')

# Loop through each manifest ID
echo "$manifest_ids" | while read -r man; do
    echo "Processing manifest: $man"

    # Fetch the revision of the current manifest
    rev=$(curl -s http://admin:V3ryS3cur3@localhost:5984/installed-manifests-3l/$man | grep -o '"_rev":"[^"]*"' | sed 's/"_rev":"\([^"]*\)"/\1/')
    
    # Check if the revision was retrieved successfully
    if [ -n "$rev" ]; then
        # Attempt to delete the document with the retrieved revision
        delete_response=$(curl -s -X DELETE "http://admin:V3ryS3cur3@localhost:5984/installed-manifests-3l/$man?rev=$rev")
        
        # Check the response from the delete request
        if echo "$delete_response" | grep -q '"ok":true'; then
            echo "Successfully deleted manifest: $man"
        else
            echo "Failed to delete manifest: $man. Response: $delete_response"
        fi
    else
        echo "Failed to retrieve revision for manifest: $man"
    fi
done
