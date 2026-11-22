#!/bin/sh
# Name: Online Screensaver (RTC Suspend)
# Author: knutle
# Icon:

enable_wifi() {
    if ! lipc-set-prop com.lab126.cmd wirelessEnable 1; then
        echo "Failed to request Wi-Fi radio enable"
    fi
    if ! lipc-set-prop -i com.lab126.wifid enable 1; then
        echo "Failed to enable the Wi-Fi connection manager"
    fi
}

disable_wifi() {
    if ! lipc-set-prop -i com.lab126.wifid enable 0; then
        echo "Failed to disable the Wi-Fi connection manager"
    fi
    if ! lipc-set-prop com.lab126.cmd wirelessEnable 0; then
        echo "Failed to request Wi-Fi radio disable"
    fi
}

echo "Starting online screensaver daemon"
echo " > RTC Suspend Mode"

disable_wifi
sleep 3
enable_wifi
sleep 3

nohup sh /mnt/us/extensions/online-ss/daemon.sh 0 >>/mnt/us/extensions/online-ss/daemon.log 2>&1 &
