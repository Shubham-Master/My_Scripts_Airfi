#!/bin/sh
#####################################################################################################
# Author: SK2                                                                                       #
# Date: 02-Apr-2025                                                                                 #
# Note: Script to test the battery by booting the box in flight mode and starting various tasks     #
#####################################################################################################
. /usr/local/airclient/logger.sh

# ----------------------------
# Skip if proxy box
# ----------------------------
if [ -f "/tmp/we-are-proxybox" ]; then
        echo "[EVETEST-SKIP] Proxy box detected. Exiting..."
        exit 0
fi

COUNTER_FILE="/logs/eve-test-count"
mins=$( uptime -p | awk '{print $3}' )

if [ $mins = "minutes" ]; then
        time=$( uptime -p | awk '{print "00:"$2}' )
elif [ $mins = "day," ]; then
        hours=$( uptime -p | awk '{print $4}' )
        mins=$( uptime -p | awk '{print $6}' )
        hours=$(( 24 + hours ))
        time="$hours:$mins"
else
        time=$( uptime -p | awk '{print $2":"$4}' )
fi

function update_led_display()
{
        test=$(cat /tmp/battery-script-running)

        if [ "x$test" = "x" ]; then
                if [ -f "/tmp/we-are-in-maintenance" ]; then
                        echo AIM > /tmp/battery-script-running
                else
                        echo FLT > /tmp/battery-script-running
                fi
        fi

        /usr/local/airclient/composer-special.sh EVETEST "$test $time"
        if [ $test = "AIM" ]; then
                /usr/bin/powman -l off off blink off
        else
                /usr/bin/powman -l off off on off
                exit 0
        fi
}

function run_aim_test()
{
        echo "[EVETEST-INFO] Maintenance mode detected."

        if [ -f "/tmp/battery-script-running" ]; then
                update_led_display
        else
                echo AIM > /tmp/battery-script-running

                BASECRON=$( ps -eaf | grep rund | grep 'reboot AIRFI_BASE_CRON' | awk '{print $2}' )
                /bin/kill $BASECRON
        fi

        CURRENT=$(grep -i "STM32" /logs/current | tail -n 1 |  sed -n 's/.*cur=\([-0-9]\+\).*/\1/p')
        echo Current=$CURRENT mA

        if [ $CURRENT -lt 500 ] && [ $CURRENT -gt 0 ]; then

                echo "[EVETEST-ACTION] Battery 100% and ext pwr good. Proceeding with config update..."

                # Step 1: Remove media contents
                echo "[EVETEST-INFO] Removing media contents..."
                rm -rf /media/content/*
                if [ $? -eq 0 ]; then
                        echo "[EVETEST-SUCCESS] /media/content/* removed."
                else
                        echo "[EVETEST-WARN] Failed to remove /media/content/*"
                fi

                # Step 2: Remove readiness marker
                echo "[EVETEST-INFO] Removing readiness marker..."
                if rm -f /logs/.we-are-ready; then
                        echo "[EVETEST-SUCCESS] /logs/.we-are-ready removed."
                else
                        echo "[EVETEST-WARN] Failed to remove /logs/.we-are-ready"
                fi

                # Step 3: Extract IATA
                IATA=$(/usr/local/airclient/airfi-cmd.sh --list | grep "IATA=" | cut -d'=' -f2 | sed "s/'//g")
                IATA=$(echo "$IATA" | tr 'A-Z' 'a-z')
                echo $IATA
                if [ -z "$IATA" ]; then
                        echo "[EVETEST-ERROR] IATA value not found!"
                        exit 1
                else
                        echo "[EVETEST-INFO] IATA value found: $IATA"
                fi

                # Step 4: Run the curl command with the extracted IATA value
                echo "[EVETEST-INFO] Deleting installed manifests for IATA: $IATA"
                curl -X DELETE "http://admin:V3ryS3cur3@localhost:5984/installed-manifests-${IATA}"

                # Step 5: Change configs for flight mode
                /usr/local/airclient/airfi-cmd.sh --put UPLINK on --delete DUAL_BAND --put MESH off --put PSK 12!MIairline --put SSID AirFi-office

                # ---------------------
                # Config Verification & Retry (flight mode logic)
                # ---------------------
                echo "[EVETEST-INFO] Verifying configuration..."
                sleep 5
                CONFIG_OUTPUT=$(/usr/local/airclient/airfi-cmd.sh --list)

                if echo "$CONFIG_OUTPUT" | grep -q "UPLINK='on'" &&
                        echo "$CONFIG_OUTPUT" | grep -q "MESH='off'" &&
                        ! echo "$CONFIG_OUTPUT" | grep -q "DUAL_BAND"; then

                        echo "[EVETEST-SUCCESS] Configurations verified. Rebooting into flight mode..."
                        /usr/local/airclient/airfi-cmd.sh --reboot-flight
                        exit 0
                else
                        echo "[EVETEST-WARN] Config not applied yet. Retrying after 30 seconds..."
                        sleep 30
                        CONFIG_OUTPUT=$(/usr/local/airclient/airfi-cmd.sh --list)

                        if echo "$CONFIG_OUTPUT" | grep -q "UPLINK='on'" &&
                                echo "$CONFIG_OUTPUT" | grep -q "MESH='off'" &&
                                ! echo "$CONFIG_OUTPUT" | grep -q "DUAL_BAND"; then
                                echo "[EVETEST-SUCCESS] Configurations verified on retry. Rebooting into flight mode..."
                                /usr/local/airclient/airfi-cmd.sh --reboot-flight BATT_TEST_SCRIPT
                                exit 0
                        else
                                echo "[EVETEST-ERROR] Config still not applied after retry. Aborting reboot."
                                exit 1
                        fi
                fi
        else
                echo "[EVETEST-SKIP] Conditions not met for reboot in maintenance mode. Continuing general maintenance"
        fi
}


function run_discharge_test ()
{
        echo "[EVETEST-SUCCESS] Discharging confirmed. Removing flight marker..."
        rm -rf /logs/.flight

        if [ ! -f $COUNTER_FILE ]; then
                echo 1 > $COUNTER_FILE
        else
                COUNT=$(cat $COUNTER_FILE)
                echo "$(($COUNT + 1))" > $COUNTER_FILE
        fi

        echo "[EVETEST-INFO] Run Count: $COUNT"
        echo FLT > /tmp/battery-script-running

        BASECRON=$( ps -eaf | grep rund | grep 'reboot AIRFI_BASE_CRON' | awk '{print $2}' )
        /bin/kill $BASECRON

        /usr/local/airfi/start-acdc.sh &
        if [ $? -eq 0 ]; then
                echo "[EVETEST-ACTION] ACDC STARTED..."
        fi
        /media/couchLoad.sh &
        if [ $? -eq 0 ]; then
                echo "[EVETEST-ACTION] Couch load STARTED..."
        fi
}

function eval_discharge_test()
{
        echo "[EVETEST-INFO] AIM mode marker NOT detected. We are in FLIGHT! Checking power status..."
        /usr/bin/powman -S 1
        sleep 30

        POWMAN_AFTER=$(powman -f)

        if echo "$POWMAN_AFTER" | grep -q "cur=-"; then
                run_discharge_test
        else
                echo -n "[EVETEST-WARN] Discharge not confirmed. powman output: "
                echo $POWMAN_AFTER

                /usr/bin/powman -S 1
                sleep 30

                POWMAN_RETRY=$(powman -f)

                if echo "$POWMAN_RETRY" | grep -q "cur=-"; then
                        discharge_test
                else
                        echo -n "[EVETEST-WARN] Discharge not confirmed. powman retry output: "
                        echo $POWMAN_RETRY
                        sleep 60
                        eval_discharge_test #recursion
                fi
        fi
}


if [ -f "/tmp/we-are-in-maintenance" ]; then
        run_aim_test
elif [ -f "/tmp/battery-script-running" ]; then
        update_led_display
elif [ -f "/tmp/we-are-online" ]; then
        echo "[EVETEST-INFO] Not in maintenance mode and we are online!"
        eval_discharge_test
else
        echo "[EVETEST-INFO] Flight mode conditions not met. Skipping..."
fi