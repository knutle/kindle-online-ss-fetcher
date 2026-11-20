#!/bin/sh

URL="http://10.3.141.182:8000/dashboard.png?city=Oslo"
DEST="/mnt/us/screensavers/current.png"
TMP="/mnt/us/screensavers/current.tmp"
INTERVAL=60  # Lowest practical rtcwake interval (seconds)
PIDFILE="/var/run/online_ss.pid"
RTC_DEV="/dev/rtc0"
[ -e /dev/rtc1 ] && RTC_DEV="/dev/rtc1"

FBINK=$(find /mnt/us/extensions/custom-screensaver -name "fbink*" -type f 2>/dev/null | head -n 1)

# Prevent multiple instances of this script from running simultaneously
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    exit 0
fi
echo $$ > "$PIDFILE"

# Stop framework/powerd interference while dashboard mode is active
lipc-set-prop com.lab126.powerd preventScreenSaver 1 >/dev/null 2>&1

render_error() {
    ERR_MSG="$1"
    # Use Europe/Oslo (CET/CEST) for accurate local timestamps
    NOW=$(TZ="CET-1CEST,M3.5.0,M10.5.0/3" date "+%Y-%m-%d %H:%M:%S")
    if [ -x "$FBINK" ]; then
        "$FBINK" -q -c -m -M -y -2 "DASHBOARD FETCH FAILED"
        "$FBINK" -q -m -M -y 0 "$ERR_MSG"
        "$FBINK" -q -m -M -y 2 "Time: $NOW"
        "$FBINK" -q -m -M -y 4 "URL: $URL"
    fi
}

fetch_dashboard() {
    ATTEMPT=1
    while [ "$ATTEMPT" -le 3 ]; do
        echo "Wi-Fi reconnect attempt $ATTEMPT/3"
        if ! lipc-set-prop com.lab126.cmd wirelessEnable 1 >/dev/null 2>&1; then
            echo "Failed to request Wi-Fi enable"
        fi

        WAIT=0
        while [ "$WAIT" -lt 15 ]; do
            if ip route | grep -q default; then
                echo "Default route available: $(ip route)"
                break
            fi
            echo "Waiting for default route... ($WAIT/15)"
            sleep 1
            WAIT=$((WAIT + 1))
        done

        if [ "$WAIT" -lt 15 ]; then
            echo "Fetching dashboard image from $URL..."
            HTTP_CODE=$(curl -s -L --connect-timeout 5 --max-time 10 -w "%{http_code}" "$URL" -o "$TMP")
            CURL_EXIT=$?
            if [ "$CURL_EXIT" -eq 0 ] && [ "$HTTP_CODE" = "200" ] && [ -s "$TMP" ]; then
                return 0
            fi
            echo "Dashboard fetch failed (cURL: $CURL_EXIT, HTTP: $HTTP_CODE)"
            if [ "$CURL_EXIT" -eq 0 ]; then
                return 2
            fi
        else
            CURL_EXIT=1
            HTTP_CODE="No default route"
            echo "No default route after 15 seconds"
        fi

        if [ "$ATTEMPT" -lt 3 ]; then
            echo "Cycling Wi-Fi before retry"
            if ! lipc-set-prop com.lab126.cmd wirelessEnable 0 >/dev/null 2>&1; then
                echo "Failed to request Wi-Fi disable"
            fi
            sleep 2
        fi
        ATTEMPT=$((ATTEMPT + 1))
    done
    return 1
}

CYCLE=0
while true; do
    echo "Starting dashboard fetch cycle ($CYCLE) at $(date "+%Y-%m-%d %H:%M:%S")"
    fetch_dashboard
    FETCH_STATUS=$?
    if [ "$FETCH_STATUS" -ne 0 ]; then
        rm -f "$TMP"
        if [ "$FETCH_STATUS" -eq 2 ] && [ "$HTTP_CODE" = "200" ]; then
            render_error "Empty dashboard response"
        elif [ "$FETCH_STATUS" -eq 2 ]; then
            render_error "HTTP Error (Status: $HTTP_CODE)"
        elif [ "$HTTP_CODE" = "No default route" ]; then
            render_error "Wi-Fi reconnect failed after 3 attempts"
        else
            render_error "Network/cURL Error (Code: $CURL_EXIT)"
        fi
        sleep 5
        continue
    fi

    # Full waveform refresh (-f) every 10 cycles to clear e-ink ghosting
    REFRESH_FLAG=""
    CYCLE=$((CYCLE + 1))
    if [ $((CYCLE % 10)) -eq 0 ]; then
        REFRESH_FLAG="-f"
    fi

    mv "$TMP" "$DEST"
    if [ -x "$FBINK" ]; then
        "$FBINK" -q $REFRESH_FLAG -g file="$DEST",w=1236,h=1648,halign=center,valign=center
    fi

    # Brief pause so framebuffer flush finishes before suspending CPU
    sleep 2

    # Suspend to RAM and wake after INTERVAL seconds
    rtcwake -d "$RTC_DEV" -m mem -s "$INTERVAL" >/dev/null 2>&1 || sleep "$INTERVAL"
done
