#!/bin/sh
# Name: Stop Online Screensaver
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

echo "Stopping online screensaver daemon..."
disable_wifi
sleep 2

PIDFILE="/var/run/online_ss.pid"

if [ -f "$PIDFILE" ]; then
    PID=$(cat "$PIDFILE")
    case "$PID" in
        ''|*[!0-9]*)
            echo "Invalid online screensaver PID in $PIDFILE"
            exit 1
            ;;
    esac

    if kill -0 "$PID" 2>/dev/null; then
        kill "$PID" || exit 1
    fi
    rm -f "$PIDFILE"
fi

disable_wifi
sleep 3
enable_wifi
sleep 1

lipc-set-prop com.lab126.powerd preventScreenSaver 0
