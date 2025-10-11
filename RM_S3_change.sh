#!/bin/bash
################################################################################################
#     Author: RM                                                                               #
#     Date: 25-05-2025                                                                         #
#     Purpose: Fetches the logs from S3 for the passed date and type                           #
################################################################################################

if [ ${#} -ne 3 ]; then
  echo "Usage: ${0} SERIAL TYPE DATE*"
  echo "Example: ${0} 10.0.25.115 maintenance 2025052"
  exit 0
fi

SERIAL=$1
TYPE=$2
DATE=$3

echo $SERIAL $TYPE $DATE

echo sudo s3cmd get -c /home/ubuntu/.s3cfg -v --stat -H --progress --skip-existing --recursive --rinclude "logfile-${TYPE}-${DATE}*" --exclude '*.gz' s3://airserver-backups/logs/${SERIAL}/ .
sudo s3cmd get -c /home/ubuntu/.s3cfg -v --stat -H --progress --skip-existing --recursive --rinclude "logfile-${TYPE}-${DATE}*" --exclude '*.gz' s3://airserver-backups/logs/${SERIAL}/ .