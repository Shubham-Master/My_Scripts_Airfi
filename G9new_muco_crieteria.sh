#!/bin/bash

# Script Information
################################################################################################
#     Author: SK2                                                                              #
#     Date: 28-02-2024                                                                         #
#     Purpose: Check for the Muco's criteria  of the boxes sent to airarabia on 24th FEB       #
################################################################################################

detailed_output="./detailed-data.csv"
count_output="./count-data.csv"

get_voltage(){
  local line=$1
  echo $(echo $line | grep -oP 'voltage=-?\w+.?[\w\s]+(\(\K[\d]+)?' | awk -F"=" '{print $2}')
}

get_current(){
  local line=$1
  echo $(echo $line | grep -oP 'current=-?\w+.?[\w\s]+(\(\K[\d]+)?' | awk -F"=" '{print $2}')
}

get_charge(){
  local line=$1
  echo $(echo $line | grep -oP 'charge=-?\w+.?[\w\s]+(\(\K[\d]+)?')
}

#1. Charging - Maintenance Mode
#  * 100%
#  * Voltage >= 3.6 - The voltage should be above or e=qual to 3.6 V
#  * Current < +ve 2 Amp - The current should be less than 2 Amps
#2. The very next Log Cycle (AirFi Mode)
#  * When the box charge is above 90%
#    * Voltage > 3.1 - Voltage should not be less than 3.1 V
#  * When the box is above 50% Charge
#    * Voltage > 2.9 - Voltage should not be less than 2.9 V

echo "Box,Maintenance_Mode_Criteria_Count,AirFi_Mode_Criteria_Count,All_Logfiles_which_see_the_issue_in_both_cases,total_maintenance_logs,total_airfi_logs" > $count_output
echo "Box,Mode,LogFile,Charge,Voltage,Current" > $detailed_output

while read -r box; do
  echo "Processing box: $box"
  total_maintenance_count=0
  total_airfi_count=0
   maintenance_condition_count=0
   airfi_condition_count=0
   seen_maintenance_once=0
   seen_in_both_count=0
   seen_in_maintenance="false"
   max_charge_maintenance=0
    while read -r log;do
      echo "Processing log: $log"
      mode=$(echo $log | awk -F"-" '{print $2}')
      if [[ $mode == 'maintenance' ]];then
        zcat $log 2>/dev/null | grep -B 10000000 "High voltage charger got disconnected" | grep "charge=" > relevant_data
        total_maintenance_count=$((total_maintenance_count + 1))
        last_charge=$(get_charge "$(cat relevant_data | tail -1)")
        if [[ $last_charge -lt 99 ]];then
          echo "Skipping log: last charge less than 99"
          seen_maintenance_once=0
          continue
        fi
        echo "Found log with full charge cycle: $log"
        seen_maintenance_once=$((seen_maintenance_once + 1))
        tac relevant_data | while read -r line;do
          charge=$(get_charge "$line")
          if [[ $charge -eq $last_charge ]];then
            voltage=$(get_voltage "$line")
            current=$(get_current "$line")
            echo "Maintenance: Charge: $charge, Voltage: $voltage, Current: $current"
            if [[ $(echo "$current < 0 " | bc -l) -eq 1 ]]; then
              continue
            fi 
            if [[  $charge -eq 100 && $(echo "$voltage >= 3.6" | bc -l) -eq 1 && $(echo "$current > 2" | bc -l) -eq 1 ]];then
              echo "Found maintenance log with matched criteria: $log"
              max_charge_maintenance=$charge
              maintenance_condition_count=$((maintenance_condition_count + 1))
              echo $box,$mode,$log,$charge,$voltage,$current,"" >> $detailed_output
              seen_in_maintenance="true"
              break
            fi
          break
          fi
        done 
      else
        zcat $log 2>/dev/null | grep "charge=" > relevant_data
        total_airfi_count=$((total_airfi_count+1))
        first_charge=$(get_charge "$(cat relevant_data | head -1)")
        if [[ $first_charge -lt 50 || $seen_maintenance_once -eq 0 ]];then
          echo "Skipping log: first charge is less than 50 or did not seen in maintenance mode atleast one time"
          continue
        fi
        while read -r line;do
          charge=$(get_charge "$line")
          voltage=$(get_voltage "$line")
          if [[ ($charge -gt 90 && $(echo "$voltage < 3.1" | bc -l) -eq 1) || ($charge -gt 50 && $(echo "$voltage < 2.9" | bc -l) -eq 1) ]];then
            echo "Found airfi log with matched criteria: $log"
            echo "AirFi: Charge: $charge, Voltage: $voltage"
            echo $box,$mode,$log,$charge,$voltage,$current,$max_charge_maintenance >> $detailed_output
            airfi_condition_count=$((airfi_condition_count + 1))
            if [[ $seen_in_maintenance == "true" ]];then
              seen_in_both_count=$((seen_in_both_count + 1))
              seen_in_maintenance="false"
            fi
            break
          fi
        done < relevant_data
      fi
   done < <(ls -1 /logs/$box/logfile-*-$(date -d "yesterday" +%Y%m%d)*.gz 2>/dev/null | sort -t'-' -k3,3 2>/dev/null)
    echo $box,$maintenance_condition_count,$airfi_condition_count,$seen_in_both_count,$total_maintenance_count,$total_airfi_count >> $count_output
done < G9_24feb_boxes.txt
