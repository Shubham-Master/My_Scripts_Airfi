#!/bin/bash

###########################################
# Author: Rohit Malaviya
# Date: 10-June-2021
# Note: Script to:
#     1. Fetch PB and STA list from DISCO
#     2. Check their last online time 
#     3. Send status mails
###########################################

# populate PB/STA list
/usr/local/bin/update-pb-sta-list.sh

date=`date '+%Y-%m-%d'`

# fetch PB device info from DISCO
/usr/local/bin/pb-last-online-on-disco.sh PBs > /tmp/.daily-pb-last-seen-on-disco.log

mail -a 'Content-Type: text/html' -s "Daily PB Status for $date" csm-content@airfi.aero,airserver@airfi.aero < /tmp/.daily-pb-last-seen-on-disco.log

# fetch STA device info from syslogs
#/usr/local/bin/pb-last-online-on-disco.sh STAs > /tmp/.daily-sta-last-seen-on-disco.log
#mail -a 'Content-Type: text/html' -s "Daily STA Status for $date" rohit@airfi.aero < /tmp/.daily-sta-last-seen-on-disco.log