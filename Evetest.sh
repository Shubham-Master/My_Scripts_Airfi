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
        echo "[C33TEST-SKIP] Proxy box detected. Exiting..."
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
                test=$(cat /tmp/battery-script-running)
        fi

        /usr/local/airclient/composer-special.sh C33TEST "$test $time"
        if [ $test = "AIM" ]; then
                /usr/bin/powman -l off off blink off
        else
                /usr/bin/powman -l off off on off
                exit 0
        fi
}

function run_aim_test()
{
        echo "[C33TEST-INFO] Maintenance mode detected."

        if [ -f "/tmp/battery-script-running" ]; then
                update_led_display
        else
                echo AIM > /tmp/battery-script-running

                BASECRON=$( ps -eaf | grep rund | grep 'reboot AIRFI_BASE_CRON' | awk '{print $2}' )
                /bin/kill $BASECRON
        fi

        CHG_LOG=$(grep -i "chg" /logs/current)

        if echo "$CHG_LOG" | grep -q "chg=100%" &&
                echo "$CHG_LOG" | grep -q "ext pwr good" &&
                echo "$CHG_LOG" | grep -q "enabled"; then

                echo "[C33TEST-ACTION] Battery 100% and ext pwr good. Proceeding with config update..."

                # Step 1: Remove media contents
                echo "[C33TEST-INFO] Removing media contents..."
                rm -rf /media/content/*
                if [ $? -eq 0 ]; then
                        echo "[C33TEST-SUCCESS] /media/content/* removed."
                else
                        echo "[C33TEST-WARN] Failed to remove /media/content/*"
                fi

                # Step 2: Remove readiness marker
                echo "[C33TEST-INFO] Removing readiness marker..."
                if rm -f /logs/.we-are-ready; then
                        echo "[C33TEST-SUCCESS] /logs/.we-are-ready removed."
                else
                        echo "[C33TEST-WARN] Failed to remove /logs/.we-are-ready"
                fi

                # Step 3: Extract IATA
                IATA=$(/usr/local/airclient/airfi-cmd.sh --list | grep "IATA=" | cut -d'=' -f2 | sed "s/'//g")
                IATA=$(echo "$IATA" | tr 'A-Z' 'a-z')
                echo $IATA
                if [ -z "$IATA" ]; then
                        echo "[C33TEST-ERROR] IATA value not found!"
                        exit 1
                else
                        echo "[C33TEST-INFO] IATA value found: $IATA"
                fi

                # Step 4: Run the curl command with the extracted IATA value
                echo "[C33TEST-INFO] Deleting installed manifests for IATA: $IATA"
                curl -X DELETE "http://admin:V3ryS3cur3@localhost:5984/installed-manifests-${IATA}"

                # Step 5: Change configs for flight mode
                /usr/local/airclient/airfi-cmd.sh --put UPLINK on --delete DUAL_BAND --put MESH off --put PSK 12!MIairline --put SSID AirFi-office

                # ---------------------
                # Config Verification & Retry (flight mode logic)
                # ---------------------
                echo "[C33TEST-INFO] Verifying configuration..."
                sleep 5
                CONFIG_OUTPUT=$(/usr/local/airclient/airfi-cmd.sh --list)

                if echo "$CONFIG_OUTPUT" | grep -q "UPLINK='on'" &&
                        echo "$CONFIG_OUTPUT" | grep -q "MESH='off'" &&
                        ! echo "$CONFIG_OUTPUT" | grep -q "DUAL_BAND"; then

                        echo "[C33TEST-SUCCESS] Configurations verified. Rebooting into flight mode..."
                        /usr/local/airclient/airfi-cmd.sh --reboot-flight
                        exit 0
                else
                        echo "[C33TEST-WARN] Config not applied yet. Retrying after 30 seconds..."
                        sleep 30
                        CONFIG_OUTPUT=$(/usr/local/airclient/airfi-cmd.sh --list)

                        if echo "$CONFIG_OUTPUT" | grep -q "UPLINK='on'" &&
                                echo "$CONFIG_OUTPUT" | grep -q "MESH='off'" &&
                                ! echo "$CONFIG_OUTPUT" | grep -q "DUAL_BAND"; then
                                echo "[C33TEST-SUCCESS] Configurations verified on retry. Rebooting into flight mode..."
                                /usr/local/airclient/airfi-cmd.sh --reboot-flight BATT_TEST_SCRIPT
                                exit 0
                        else
                                echo "[C33TEST-ERROR] Config still not applied after retry. Aborting reboot."
                                exit 1
                        fi
                fi
        else
                echo "[C33TEST-SKIP] Conditions not met for reboot in maintenance mode. Continuing general maintenance"
        fi
}


function run_discharge_test ()
{
        echo "[C33TEST-SUCCESS] Discharging confirmed. Removing flight marker..."
        rm -rf /logs/.flight

        if [ ! -f $COUNTER_FILE ]; then
                echo 1 > $COUNTER_FILE
        else
                COUNT=$(cat $COUNTER_FILE)
                echo "$(($COUNT + 1))" > $COUNTER_FILE
        fi

        echo "[C33TEST-INFO] Run Count: $COUNT"
        echo FLT > /tmp/battery-script-running

        BASECRON=$( ps -eaf | grep rund | grep 'reboot AIRFI_BASE_CRON' | awk '{print $2}' )
        /bin/kill $BASECRON

        /usr/local/airfi/start-acdc.sh &
        if [ $? -eq 0 ]; then
                echo "[C33TEST-ACTION] ACDC STARTED..."
        fi
        /media/couchLoad.sh &
        if [ $? -eq 0 ]; then
                echo "[C33TEST-ACTION] Couch load STARTED..."
        fi
}

function eval_discharge_test()
{
        echo "[C33TEST-INFO] AIM mode marker NOT detected. We are in FLIGHT! Checking power status..."
        /usr/bin/powman -S 1
        sleep 30

        POWMAN_AFTER=$(powman -f)

        if echo "$POWMAN_AFTER" | grep -q "cur=-"; then
                run_discharge_test
        else
                echo -n "[C33TEST-WARN] Discharge not confirmed. powman output: "
                echo $POWMAN_AFTER

                /usr/bin/powman -S 1
                sleep 30

                POWMAN_RETRY=$(powman -f)

                if echo "$POWMAN_RETRY" | grep -q "cur=-"; then
                        discharge_test
                else
                        echo -n "[C33TEST-WARN] Discharge not confirmed. powman retry output: "
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
        echo "[C33TEST-INFO] Not in maintenance mode and we are online!"
        eval_discharge_test
else
        echo "[C33TEST-INFO] Flight mode conditions not met. Skipping..."
fi