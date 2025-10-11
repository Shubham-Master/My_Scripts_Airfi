#!/usr/bin/python

from airfi import AirFi
from time import sleep
from getlogger import getLogger
import sys, traceback
import os
from subprocess import call
import easygui
import socket
import json

DISCO_API_URL = "https://box-heartbeat:cream-jet-tea@airfi-disco.herokuapp.com/api"

logger = getLogger(__file__)
trys = 10
IMEI = ""
MAC = ""
foundGSM = False
noGSMVer = "V1.4"
GSMVer = "V1.5"
watthours = "48"
gramslithium = "5.5"
ip = ""
battery_model = ""  # New variable to store battery model

airfi = AirFi("192.168.244.2")


def registerBoxInDisco(description, ip, MAC, IMEI, battery_model):  # Updated to include battery_model
    logger.info(description)
    if not MAC:
        logger.warning("warning: Registering the box in DISCO without MAC")

    if not IMEI:
        logger.warning("warning: Registering the box in DISCO without IMEI")

    boxInfo = {"boxId": ip, "MAC": MAC, "IMEI": IMEI, "BatteryModel": battery_model}  # Added BatteryModel
    registerCommand = "curl -s -X POST -H 'content-type: application/json' " + DISCO_API_URL + \
        "/boxHeartbeat -d " + "'" + str(json.dumps(boxInfo)) + "'"
    retVal, stdout, stderr = airfi.run(registerCommand)

    if retVal != 0 or "Successfully updated" not in stdout:
        logger.error("Box registration failed " + stdout)
    else:
        logger.info("Box registration was successful " + stdout)


def click_to_continue(message):
    retval = easygui.buttonbox(message, title="AirFi Sticker Printer", choices=('Verder', ''), cancel_choice='youdontwannadothat')
    if retval is 'Verder':
        logger.info("GUI: On message: " + message + " - user clicked Continue")
        return(True)
    else:
        logger.info("GUI: " + "User closed the window")
        click_to_continue(message)
    return(True)


def click_to_fail(message):
    easygui.buttonbox(message, title="AirFi Sticker Printer", choices=('Verder', ''), cancel_choice='youdontwannadothat')
    logger.info("GUI: On message: " + message + " - user clicked Continue")


def ask_battery_type():
    # Ask the user to select the battery type
    battery_type = easygui.buttonbox("Select the battery type:", title="Battery Type", choices=('EVE', 'HEADWAY'))
    logger.info(f"User selected battery type: {battery_type}")
    return battery_type


# Ask the user to connect the USB cable
click_to_continue("Koppel de USB-kabel aan de AirFi.")

# Ask the user to select the battery type
battery_model = ask_battery_type()

# Rest of the script remains the same until GSMVer is determined

logger.info("connecting...")
times = 0;
while 1:
	times += 1;
	if airfi.connect():
		try:
			logger.info("connected")
			retval, stdout, stderr = airfi.run("ifconfig wlan1")
			if retval == 0:
				values = stdout[0].split(" ")
				MAC = values[values.index('HWaddr')+1]
			else:
				logger.error("No wifi module wlan1, can't print sticker")
				click_to_fail("Noteer deze code: -3\nEr wordt geen sticker geprint!")
				sys.exit(-3)
				airfi.disconnect()
			retval, stdout, stderr = airfi.run("cat /tmp/MY-IP")
			if retval == 0:
				ip = stdout[0].strip()
				try:
					socket.inet_aton(ip)
				except:
					ip = None
			if not ip:
				logger.error("Cannot get the serial number")
				click_to_fail("Noteer deze code: -30\nEr wordt geen sticker geprint!")
				sys.exit(-30)
				airfi.disconnect()
			airfi.run("killall gsmmon.sh")
			airfi.run("echo 1 > /sys/class/gpio/export")
			airfi.run("killall gsmmon.sh")
			airfi.run("echo 1 > /sys/class/gpio/export")
			airfi.run("echo out > /sys/class/gpio/gpio1_pa2/direction")

			airfi.run("echo 2 > /sys/class/gpio/export")
			airfi.run("echo out > /sys/class/gpio/gpio2_pa3/direction")
			airfi.run("echo 1 > /sys/class/gpio/gpio2_pa3/value")

			airfi.run("echo 15 > /sys/class/gpio/export")
			airfi.run("echo out > /sys/class/gpio/gpio15_pa0/direction")
			airfi.run("echo 1 > /sys/class/gpio/gpio15_pa0/value")
			x = 0
			sleep(5)
			while 1:
                            gsm_dev_node = "/dev/ttyACM3"  # For 3G Device
                            retval, stdout, stderr = airfi.run("ls -l " + gsm_dev_node)
                            x+=1
                            if(retval == 0):
                                foundGSM = True
                                logger.info("3G Modem found")
                                GSMVer = "V3.1"
                                break
                            else:
                                gsm_dev_node = "/dev/ttyUSB4"  # For 4G Device
                                retval, stdout, stderr = airfi.run("ls -l " + gsm_dev_node)
                                if(retval == 0):
                                    foundGSM = True
                                    logger.info("4G Modem found")
                                    GSMVer = "V3.2"
                                    break

			    if x > trys:
				break
			    sleep(1)

			x = 0
			toFind = "AT+GSN"
			if foundGSM:
				#os.system("scp -i /home/embed/.ssh/logs-airserver_id_rsa imei.chat "+airfi.username+"@"+airfi.ip+":/root/")
				#os.system("scp -i /home/embed/.ssh/logs-airserver_id_rsa getIMEI.sh "+airfi.username+"@"+airfi.ip+":/root/")
				os.system("scp imei.chat "+airfi.username+"@"+airfi.ip+":/root/")
				os.system("scp getIMEI.sh "+airfi.username+"@"+airfi.ip+":/root/")				
				sleep(1)
				airfi.run("chmod +x /root/getIMEI.sh")
				sleep(1)
				while 1:
					retval, stdout, stderr = airfi.run("/root/getIMEI.sh " + gsm_dev_node)
					x += 1
					#logger.info( stdout)
					if toFind in stdout:
						logger.info( stdout[stdout.index(toFind)+1])
						try:
							test = int(stdout[stdout.index(toFind)+1])
							IMEI = stdout[stdout.index(toFind)+1]
							logger.info("IMEI found")
							#logger.info( "found imei in times:")
							#logger.info( x
							break
						except:
							pass
							#logger.info( "oops, no imei")
					if x > trys:
						click_to_fail("Noteer deze code: -1\nEr wordt geen sticker geprint!")
						logger.error("error in script, this is not working")
						logger.error("exiting")
						logger.error(retval)
						logger.error(stdout)
						logger.error(stderr)
						airfi.disconnect()
						sys.exit(-1)

		except Exception as ex:
			click_to_fail("Noteer deze code: -4\nEr wordt geen sticker geprint!")
			logger.error("unexpected error:")
			logger.error(type(ex))
			logger.error(traceback.logger.info(_exc(limit = 5)))
			airfi.disconnect()
			sys.exit(-4)

		break

	else:
		if times > trys:
			logger.info("AirFi not found, try reconnecting the cable")
			times = 0;
		sleep(0.5)

retval, stdout, stderr = airfi.run("test `powman -v` -ge 3")
if retval == 0:
    if not foundGSM:
        click_to_fail("Noteer deze code: -5\nEr wordt geen sticker geprint!")
        logger.error("unexpected error:")
        airfi.disconnect()
        sys.exit(-5)


    #Headway specific battery details
    gramslithium = "11"
    watthours = "96"


logger.info("model version:")
if foundGSM:
    logger.info(GSMVer)
    logger.info("IMEI for sticker:")
    logger.info(IMEI)
else:
    logger.info(noGSMVer)
    logger.info("NO GSM box")

#retval, stdout, stderr = airfi.run("ls -al /tmp/wlan_realtek")
#if retval == 0:
 #   GSMVer = "V3.2"

# Update GSMVer, gramslithium, and watthours based on battery model
if battery_model == "EVE":
    GSMVer = "V3.3"  # Always set to V3.3 for EVE
    gramslithium = "12"  # Update grams lithium
    watthours = "128"  # Update watt hours

airfi.runCommandOrDie("mount -o remount,rw /dev/nand2")
airfi.runCommandOrDie("echo" +str(GSMVer)+" > /etc/cert/hwver")
airfi.runCommandOrDie("mount -o remount,ro /dev/nand2")


logger.info("MAC for sticker:")
logger.info(MAC)
logger.info("ip for sticker:")
logger.info(ip)
logger.info("done")

# Generate and print the sticker
with open('../sticker/sticker.zpl', 'r') as f:
    sticker = f.read()
    if foundGSM:
        sticker = sticker[0:sticker.index("$$NOGSM PART$$")] + sticker[sticker.index("$$END NOGSM PART$$"):]
        sticker = sticker.replace("$$END NOGSM PART$$", "")
        sticker = sticker.replace("$$GSM PART$$", "")
        sticker = sticker.replace("$$END GSM PART$$", "")
        sticker = sticker.replace("$$versie$$", GSMVer)
        sticker = sticker.replace("$$gramslithium$$", gramslithium)
        sticker = sticker.replace("$$watthours$$", watthours)
        sticker = sticker.replace("$$IMEI$$", IMEI)
    else:
        sticker = sticker[0:sticker.index("$$GSM PART$$")] + sticker[sticker.index("$$END GSM PART$$"):]
        sticker = sticker.replace("$$END GSM PART$$", "")
        sticker = sticker.replace("$$NOGSM PART$$", "")
        sticker = sticker.replace("$$END NOGSM PART$$", "")
        sticker = sticker.replace("$$versie$$", noGSMVer)

    sticker = sticker.replace("$$MAC$$", MAC)
    sticker = sticker.replace("$$ip$$", ip)

    os.system("echo '" + sticker + "' >> /tmp/tempsticker.zpl")
    os.system("/usr/bin/lpr -P Zebra_Technologies_ZTC_ZT220-200dpi_ZPL -o raw /tmp/tempsticker.zpl")
    os.system("rm /tmp/tempsticker.zpl")

# Register the box in DISCO with battery model
registerBoxInDisco("Registering box in DISCO with serial, MAC, IMEI, and battery model", ip, MAC, IMEI, battery_model)