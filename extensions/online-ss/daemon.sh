#!/bin/sh

URL="http://10.3.141.182:8000/dashboard.png?city=Oslo"
WIFI_SSID="krispy"
WIFI_CONNECT_TIMEOUT=30
WIFI_CONNECT_ATTEMPTS=2
DEST="/mnt/us/screensavers/current.png"
TMP="/mnt/us/screensavers/current.tmp"
INTERVAL=60  # Lowest practical rtcwake interval (seconds)
PIDFILE="/var/run/online_ss.pid"
RTC_DEV="/dev/rtc0"
[ -e /dev/rtc1 ] && RTC_DEV="/dev/rtc1"

log() {
    LOG_SEVERITY="$1"
    shift

    LOG_TIMESTAMP=$(TZ="CET-1CEST,M3.5.0,M10.5.0/3" date "+%Y-%m-%d %H:%M:%S")
    LOG_MESSAGE="$*"
    printf '%s\n' "$LOG_MESSAGE" | while IFS= read -r LOG_LINE; do
        printf '[%s] [%s] %s\n' "$LOG_TIMESTAMP" "$LOG_SEVERITY" "$LOG_LINE"
    done
}

log_debug() {
    log "DEBUG" "$@"
}

log_info() {
    log "INFO" "$@"
}

log_warn() {
    log "WARN" "$@"
}

log_error() {
    log "ERROR" "$@"
}

# Prevent multiple instances of this script from running simultaneously
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    exit 0
fi
echo $$ > "$PIDFILE"

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" 2>/dev/null && pwd) || {
    log_error "Unable to resolve daemon directory"
    exit 1
}

FBINK_BIN="$SCRIPT_DIR/bin/fbink_hf"

if [ ! -x "$FBINK_BIN" ]; then
    log_error "FBInk binary not found, cannot render dashboard"
    exit 1
fi

run_lipc_set_prop() {
    log_debug "Running lipc-set-prop: $*"

    LIPC_OUTPUT=$(lipc-set-prop "$@" 2>&1)
    LIPC_STATUS=$?
    if [ -n "$LIPC_OUTPUT" ]; then
        log_debug "lipc-set-prop output:"
        log_debug "$LIPC_OUTPUT"
    else
        log_debug "lipc-set-prop output: <none>"
    fi
    log_debug "lipc-set-prop exit status: $LIPC_STATUS"
    return "$LIPC_STATUS"
}

# Stop framework/powerd interference while dashboard mode is active
if ! run_lipc_set_prop com.lab126.powerd preventScreenSaver 1; then
    log_error "Failed to prevent the framework screensaver"
fi

render_error() {
    ERR_MSG="$1"
    # Use Europe/Oslo (CET/CEST) for accurate local timestamps
    NOW=$(TZ="CET-1CEST,M3.5.0,M10.5.0/3" date "+%Y-%m-%d %H:%M:%S")
    if [ -x "$FBINK_BIN" ]; then
        "$FBINK_BIN" -q -c -m -M -y -2 "DASHBOARD FETCH FAILED"
        "$FBINK_BIN" -q -m -M -y 0 "$ERR_MSG"
        "$FBINK_BIN" -q -m -M -y 2 "Time: $NOW"
        "$FBINK_BIN" -q -m -M -y 4 "URL: $URL"
    fi
}

render_init() {
    MSG="$1"
    if [ -x "$FBINK_BIN" ]; then
        "$FBINK_BIN" -q -c -m -M -y -2 "INITIALIZING DASHBOARD"
        "$FBINK_BIN" -q -m -M -y 0 "$MSG"
        
        "$FBINK_BIN" -q -m -M -y 2 "DEFAULT WIFI: $WIFI_SSID"
        "$FBINK_BIN" -q -m -M -y 4 "WIFI STATE: $(lipc-get-prop com.lab126.wifid cmState 2>/dev/null || echo unknown)"
        "$FBINK_BIN" -q -m -M -y 6 "URL: $URL"
    fi
}

enable_wifi() {
    if ! run_lipc_set_prop com.lab126.cmd wirelessEnable 1; then
        log_error "Failed to request Wi-Fi radio enable"
    fi
    if ! run_lipc_set_prop -i com.lab126.wifid enable 1; then
        log_error "Failed to enable the Wi-Fi connection manager"
    fi
    if ! run_lipc_set_prop -s com.lab126.cmd ensureConnection "wifi:$WIFI_SSID"; then
        log_error "Failed to request connection to the saved Wi-Fi profile"
    fi
}

disable_wifi() {
    if ! run_lipc_set_prop -i com.lab126.wifid enable 0; then
        log_error "Failed to disable the Wi-Fi connection manager"
    fi
    if ! run_lipc_set_prop com.lab126.cmd wirelessEnable 0; then
        log_error "Failed to request Wi-Fi radio disable"
    fi
}

fetch_dashboard() {
    ATTEMPT=1
    WIFI_ERROR=1
    while [ "$ATTEMPT" -le "$WIFI_CONNECT_ATTEMPTS" ]; do
        log_info "Wi-Fi reconnect attempt $ATTEMPT/$WIFI_CONNECT_ATTEMPTS"
        enable_wifi

        WAIT=0
        LAST_WIFI_STATE=""
        while [ "$WAIT" -lt "$WIFI_CONNECT_TIMEOUT" ]; do
            WIFI_STATE=$(lipc-get-prop com.lab126.wifid cmState 2>/dev/null)
            if [ "$WIFI_STATE" != "$LAST_WIFI_STATE" ]; then
                log_debug "Wi-Fi connection state: ${WIFI_STATE:-unknown}"
                LAST_WIFI_STATE="$WIFI_STATE"
            fi
            if [ "$WIFI_STATE" = "CONNECTED" ] && ip route | grep -q default; then
                log_info "Wi-Fi connected with default route: $(ip route)"
                break
            fi
            log_debug "Waiting for Wi-Fi association and route... ($WAIT/$WIFI_CONNECT_TIMEOUT)"
            sleep 1
            WAIT=$((WAIT + 1))
        done

        if [ "$WAIT" -lt "$WIFI_CONNECT_TIMEOUT" ]; then
            WIFI_ERROR=0
            log_info "Fetching dashboard image from $URL..."
            HTTP_CODE=$(curl -s -L --connect-timeout 5 --max-time 10 -w "%{http_code}" "$URL" -o "$TMP")
            CURL_EXIT=$?
            if [ "$CURL_EXIT" -eq 0 ] && [ "$HTTP_CODE" = "200" ] && [ -s "$TMP" ]; then
                return 0
            fi
            log_error "Dashboard fetch failed (cURL: $CURL_EXIT, HTTP: $HTTP_CODE)"
            if [ "$CURL_EXIT" -eq 0 ]; then
                return 2
            fi
        else
            CURL_EXIT=1
            HTTP_CODE="Wi-Fi not connected"
            WIFI_ERROR=1
            log_error "Wi-Fi did not connect after $WIFI_CONNECT_TIMEOUT seconds (cmState: ${WIFI_STATE:-unknown})"
        fi

        if [ "$ATTEMPT" -lt "$WIFI_CONNECT_ATTEMPTS" ]; then
            log_warn "Cycling Wi-Fi radio and connection manager before retry"
            disable_wifi
            sleep 2
        fi
        ATTEMPT=$((ATTEMPT + 1))
    done
    return 1
}

render_init "Attempting to fetch dashboard from url"

CYCLE=0
while true; do
    log_info "Starting dashboard fetch cycle ($CYCLE)"
    fetch_dashboard
    FETCH_STATUS=$?
    if [ "$FETCH_STATUS" -ne 0 ]; then
        rm -f "$TMP"
        if [ "$FETCH_STATUS" -eq 2 ] && [ "$HTTP_CODE" = "200" ]; then
            render_error "Empty dashboard response"
        elif [ "$FETCH_STATUS" -eq 2 ]; then
            render_error "HTTP Error (Status: $HTTP_CODE)"
        elif [ "$WIFI_ERROR" -eq 1 ]; then
            render_error "Wi-Fi association failed (cmState: ${WIFI_STATE:-unknown})"
        else
            render_error "Network/cURL Error (Code: $CURL_EXIT)"
        fi
        run_lipc_set_prop com.lab126.powerd preventScreenSaver 0
        log_warn "Dashboard fetch failed, sleeping for 5 seconds before retry"
        sleep 5
        continue
    fi

    # Full waveform refresh (-f) every 10 cycles to clear e-ink ghosting
    REFRESH_FLAG=""
    CYCLE=$((CYCLE + 1))
    if [ $((CYCLE % 10)) -eq 0 ]; then
        REFRESH_FLAG="-f"
    fi

    # Shut Wi-Fi down cleanly before suspend to avoid stale driver state on resume
    disable_wifi

    mv "$TMP" "$DEST"
    if [ -x "$FBINK_BIN" ]; then
        sleep 3
        "$FBINK_BIN" -q $REFRESH_FLAG -g file="$DEST",w=1236,h=1586,halign=center,valign=top,y=72
    fi

    # Brief pause so Wi-Fi and framebuffer shutdown finish before suspending CPU
    sleep 5

    # Suspend to RAM and wake after INTERVAL seconds
    if rtcwake -d "$RTC_DEV" -m mem -s "$INTERVAL"; then
        log_info "System suspended for $INTERVAL seconds"
    else
        RTCWAKE_STATUS=$?
        log_error "Failed to suspend system (rtcwake exit code: $RTCWAKE_STATUS)"
        run_lipc_set_prop com.lab126.powerd preventScreenSaver 0
        sleep 2
    fi
done
