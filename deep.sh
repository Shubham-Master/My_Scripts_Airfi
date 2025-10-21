#!/bin/bash

BUCKET="airserver-backups"
OUT_TXT="deep_archive_objects.txt"

rm -f "$OUT_TXT"
echo "Fetching first batch..."

aws s3api list-objects-v2 \
  --bucket "$BUCKET" \
  --output json > /tmp/page.json

jq -r '.Contents[] | select(.StorageClass=="DEEP_ARCHIVE") | .Key' /tmp/page.json >> "$OUT_TXT"
NEXT_TOKEN=$(jq -r '.NextContinuationToken' /tmp/page.json)

while [ "$NEXT_TOKEN" != "null" ]; do
  echo "Fetching next batch..."
  aws s3api list-objects-v2 \
    --bucket "$BUCKET" \
    --continuation-token "$NEXT_TOKEN" \
    --output json > /tmp/page.json

  jq -r '.Contents[] | select(.StorageClass=="DEEP_ARCHIVE") | .Key' /tmp/page.json >> "$OUT_TXT"
  NEXT_TOKEN=$(jq -r '.NextContinuationToken' /tmp/page.json)
done

echo "✅ Done. Deep Archive object list saved in $OUT_TXT"
