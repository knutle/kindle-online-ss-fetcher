#!/bin/sh
# Name: Online Screensaver Stop
# Author: Local Setup
# Icon:
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

lipc-set-prop com.lab126.powerd preventScreenSaver 0
