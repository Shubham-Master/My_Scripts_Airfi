#!/bin/sh

ORPHANED_MANIFESTS_FILE=".orphaned-manifests"
LOG_FILE="/logs/current"

echo "Removing orphaned manifests..."

cat $LOG_FILE | grep "Adding status log with status orphaned"|awk '{print $5}'| sort -u > $ORPHANED_MANIFESTS_FILE

count=$(cat $ORPHANED_MANIFESTS_FILE | grep -v "root" | wc -l)

if [ "$count" -eq 0 ];then
  echo "Found no orphaned manifests. Exiting."
  exit 0
fi

echo "Found: $count orphaned manifests"

cat $ORPHANED_MANIFESTS_FILE | grep -v "root" | while read -r man;do
   manifest="$man"
   if ! echo "$manifest" | grep -q "Product";then
     manifest="manifest/$man"
     manifest=$(echo "$manifest" | sed 's/\//%2f/g')
   fi
   echo "Dropping $man"
   rev=$(curl -s "http://admin:V3ryS3cur3@localhost:5984/installed-manifests-6e/$manifest" | grep -o '"_rev":"[^"]*"' | sed 's/"_rev":"\([^"]*\)"/\1/')
   if [ -z "$rev" ];then
     echo "$man not found in database"
     continue
   fi
   curl -X DELETE "http://admin:V3ryS3cur3@localhost:5984/installed-manifests-6e/$manifest?rev=$rev"
done

rm $ORPHANED_MANIFESTS_FILE