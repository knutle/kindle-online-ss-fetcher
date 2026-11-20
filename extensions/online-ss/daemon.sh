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

CYCLE=0
while true; do
    echo "Starting dashboard fetch cycle ($CYCLE) at $(date "+%Y-%m-%d %H:%M:%S")"
    # Wake Wi-Fi and wait up to 15s for default route
    lipc-set-prop com.lab126.cmd wirelessEnable 1 >/dev/null 2>&1
    WAIT=0
    while [ $WAIT -lt 15 ]; do
        if ip route | grep -q default; then
            echo "Network connectivity established. $(ip route)"
            break
        fi
        echo "Waiting for network connectivity... ($WAIT/15)"
        sleep 1
        WAIT=$((WAIT + 1))
    done

    if [ $WAIT -ge 15 ]; then
        echo "Network connectivity failed after 15s."
        echo "Current IP route: $(ip route)"
        render_error "Network connectivity failed after 15s"
        sleep 5
        continue
    fi

    echo "Fetching dashboard image from $URL..."
    sleep 1  # Brief pause to allow network to stabilize

    HTTP_CODE=$(curl -s -L --connect-timeout 5 --max-time 10 -w "%{http_code}" "$URL" -o "$TMP")
    CURL_EXIT=$?

    # Full waveform refresh (-f) every 10 cycles to clear e-ink ghosting
    REFRESH_FLAG=""
    CYCLE=$((CYCLE + 1))
    if [ $((CYCLE % 10)) -eq 0 ]; then
        REFRESH_FLAG="-f"
    fi

    if [ "$CURL_EXIT" -eq 0 ] && [ "$HTTP_CODE" = "200" ] && [ -s "$TMP" ]; then
        mv "$TMP" "$DEST"
        if [ -x "$FBINK" ]; then
            "$FBINK" -q $REFRESH_FLAG -g file="$DEST",w=1236,h=1648,halign=center,valign=center
        fi
    else
        rm -f "$TMP"
        if [ "$CURL_EXIT" -ne 0 ]; then
            render_error "Network/cURL Error (Code: $CURL_EXIT)"
        else
            render_error "HTTP Error (Status: $HTTP_CODE)"
        fi
    fi

    # Brief pause so framebuffer flush finishes before suspending CPU
    sleep 2

    # Suspend to RAM and wake after INTERVAL seconds
    rtcwake -d "$RTC_DEV" -m mem -s "$INTERVAL" >/dev/null 2>&1 || sleep "$INTERVAL"
done
