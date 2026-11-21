#!/bin/sh
# Name: Online Screensaver
# Author: knutle
# Icon:

echo "Starting online screensaver daemon"
sleep 3

nohup sh /mnt/us/extensions/online-ss/daemon.sh >>/mnt/us/extensions/online-ss/daemon.log 2>&1 &