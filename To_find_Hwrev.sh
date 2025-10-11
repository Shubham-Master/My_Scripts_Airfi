#!/bin/sh

# update the hardware revision at /etc/cert/hw-rev by finding the component combinations

. /usr/local/airclient/markers.sh
. /usr/local/airclient/gsmfuncs.sh
. /usr/local/airclient/update-led-lights.sh

hw_rev_no='0'

if [ -f ${VENUS} ]; then
	hw_rev_no='3'

	if ! [ -f ${GSM_INIT} ]; then
		gsm_init
		wait_for_gsm_modem
	fi

	if [ -c /dev/ttyUSB4 ]; then
		lsusb | grep "1e0e:9001"
		if [ $? -eq 0 ] || [ -f /tmp/.simcom_4G ]; then
			if lsusb | grep "Bus 001 Device 002: ID 148f:5572" && lsusb | grep "Bus 003 Device 003: ID 0bda:b82c"; then
				# Ralink-module connected to SOM directly, and Realtek-module connected through USB-hub
				if [ -f ${WLAN0_RALINK_TCL} ] && [ -f ${WLAN1_REALTEK_JJPLUS} ]; then
					hw_rev_no='3.14'
				else
					echo "HWREV evaluation fail" >> /tmp/failure_init
					set_led_lights needs-attention
					echo "init-hwrevision: HWREV-Error-Alert in determining hw-rev of VENUS box with Ralink-Realtek WLAN-modules"
				fi
			elif lsusb | grep "Bus 001 Device 002: ID 0bda:b82c" && lsusb | grep "Bus 003 Device 003: ID 148f:5572"; then
				# Realtek-module connected to SOM directly, and Ralink-module connected through USB-hub
				if [ [ -f ${WLAN0_RALINK_OGEMRAY} ]  || [ -f ${WLAN0_RALINK_TCL} ] ] && [ -f ${WLAN1_REALTEK_JJPLUS} ]; then
					hw_rev_no='3.13'
				else
					# When RALINK='off', setting hw-rev=3.13 without further evaluation
					RALINK_STATUS=$(/usr/local/airclient/airfi-cmd.sh --get RALINK)
					if [ "x$RALINK_STATUS" = "xoff" ]; then
						hw_rev_no='3.13'
					else
						echo "HWREV evaluation fail" >> /tmp/failure_init
						set_led_lights needs-attention
						echo "init-hwrevision: HWREV-Error-Alert in determining hw-rev of VENUS box with Realtek-Ralink WLAN-modules"
					fi
				fi
			else
				echo "HWREV evaluation fail" >> /tmp/failure_init
				set_led_lights needs-attention
				echo "init-hwrevision: HWREV-Error-Alert in determining hw-rev of VENUS box with Simcom 4G Modem"
			fi
		elif [ -f /tmp/.quectel_4G ] && [ -f /tmp/.wlan-realtek ]; then
			hw_rev_no='3.12'
		elif [ -f /tmp/.quectel_4G ]; then
			hw_rev_no='3.8'
		else
			echo "HWREV evaluation fail" >> /tmp/failure_init
			set_led_lights needs-attention
			echo "init-hwrevision: HWREV-Error-Alert in determining hw-rev of VENUS box with 4G Modem"
		fi
	elif [ -f /tmp/.quectel_3G ]; then
		hw_rev_no='3.7'
	else
		echo "HWREV evaluation fail" >> /tmp/failure_init
		set_led_lights needs-attention
		echo "init-hwrevision: HWREV-Error-Alert in determining hw-rev of VENUS box with no GSM"
	fi
else
	hw_rev_no='2'
	echo "init-hwrevision: MOON box"
	# also needs logic to distinguish MARS/LEO box
fi

echo "HWrev: $hw_rev_no"

mount -o remount,rw /etc/cert || exit 1
echo "$hw_rev_no" > /etc/cert/hw-rev
sleep 1
sync
mount -o remount,ro /etc/cert