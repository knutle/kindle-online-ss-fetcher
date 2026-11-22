#!/bin/sh
# Name: Update Online Screensaver (Latest Release)
# Author: knutle
# Icon:

API_URL="https://api.github.com/repos/knutle/kindle-online-ss-fetcher/releases/latest"
CONFIG_FILE="/mnt/us/extensions/online-ss/config/daemon.conf"
LEGACY_CONFIG_FILE="/mnt/us/extensions/online-ss/daemon.sh"
LOCAL_UPDATER="/mnt/us/documents/knutle_online_ss_update_local.sh"
TEMP_JSON="/mnt/us/.knutle_online_ss-release.json"
TEMP_ZIP="/mnt/us/.knutle_online_ss-release.zip"
WIFI_WAIT_SECONDS=30
LOG_DIR="/mnt/us/extensions/online-ss"
LOG_FILE="$LOG_DIR/update.log"

log_update() {
    LOG_SEVERITY="$1"
    shift

    LOG_TIMESTAMP=$(TZ="CET-1CEST,M3.5.0,M10.5.0/3" date "+%Y-%m-%d %H:%M:%S")
    LOG_MESSAGE="$*"
    printf '%s\n' "$LOG_MESSAGE" | while IFS= read -r LOG_LINE; do
        LOG_ENTRY="[$LOG_TIMESTAMP] [$LOG_SEVERITY] $LOG_LINE"
        printf '%s\n' "$LOG_ENTRY"
        if [ -d "$LOG_DIR" ] || mkdir -p "$LOG_DIR" 2>/dev/null; then
            if ! printf '%s\n' "$LOG_ENTRY" >> "$LOG_FILE"; then
                printf '[%s] [WARN] Failed to append to %s\n' "$LOG_TIMESTAMP" "$LOG_FILE" >&2
            fi
        else
            printf '[%s] [WARN] Failed to create %s for updater logs\n' "$LOG_TIMESTAMP" "$LOG_DIR" >&2
        fi
    done
}

log_info() {
    log_update "INFO" "$@"
}

log_error() {
    log_update "ERROR" "$@"
}

enable_wifi() {
    if ! lipc-set-prop com.lab126.cmd wirelessEnable 1; then
        log_error "Failed to request Wi-Fi radio enable"
        return 1
    fi
    if ! lipc-set-prop -i com.lab126.wifid enable 1; then
        log_error "Failed to enable the Wi-Fi connection manager"
        return 1
    fi

    if [ -r "$CONFIG_FILE" ]; then
        # shellcheck disable=SC1090
        . "$CONFIG_FILE"
    elif [ -r "$LEGACY_CONFIG_FILE" ]; then
        # shellcheck disable=SC1090
        . "$LEGACY_CONFIG_FILE"
    fi
    if [ -n "${WIFI_SSID:-}" ]; then
        if ! lipc-set-prop -s com.lab126.cmd ensureConnection "wifi:$WIFI_SSID"; then
            log_error "Failed to request the saved Wi-Fi profile"
            return 1
        fi
    else
        log_error "WIFI_SSID is not configured"
        return 1
    fi
}

wait_for_wifi() {
    WAIT=0
    WIFI_STATE=""
    while [ "$WAIT" -lt "$WIFI_WAIT_SECONDS" ]; do
        WIFI_STATE=$(lipc-get-prop com.lab126.wifid cmState 2>/dev/null)
        if [ "$WIFI_STATE" = "CONNECTED" ] && ip route 2>/dev/null | grep -q default; then
            log_info "Wi-Fi connected with a default route"
            return 0
        fi
        sleep 1
        WAIT=$((WAIT + 1))
    done
    log_error "Wi-Fi did not connect after $WIFI_WAIT_SECONDS seconds (cmState: ${WIFI_STATE:-unknown})"
    return 1
}

if ! command -v curl >/dev/null 2>&1; then
    log_error "curl is not available"
    exit 1
fi

if ! enable_wifi; then
    exit 1
fi
if ! wait_for_wifi; then
    exit 1
fi

rm -f "$TEMP_JSON" "$TEMP_ZIP"
if ! curl -fsSL --connect-timeout 5 --max-time 30 "$API_URL" -o "$TEMP_JSON"; then
    rm -f "$TEMP_JSON"
    log_error "Could not retrieve the latest GitHub release"
    exit 1
fi

DOWNLOAD_URL=""
if command -v jq >/dev/null 2>&1; then
    if jq -e '.assets | type == "array"' "$TEMP_JSON" >/dev/null 2>&1; then
        DOWNLOAD_URL=$(jq -r '.assets[]?
            | select(.name? | type == "string" and test("^upd_knutle_online_ss_pkg-[0-9]+\\.[0-9]+\\.[0-9]+\\.zip$"))
            | .browser_download_url? // empty' "$TEMP_JSON" | head -n 1)
    fi
fi

if [ -z "$DOWNLOAD_URL" ]; then
    DOWNLOAD_URL=$(tr -d '\n' < "$TEMP_JSON" | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\/upd_knutle_online_ss_pkg-[0-9][^"]*\.zip\)".*/\1/p' | sed 's#\\/#/#g' | head -n 1)
fi

if [ -z "$DOWNLOAD_URL" ]; then
    log_info "No download URL found in the release JSON ($TEMP_JSON)"
    log_error "Latest release has no valid upd_knutle_online_ss_pkg-MAJOR.MINOR.PATCH.zip asset"
    exit 1
fi

rm -f "$TEMP_JSON"

case "$DOWNLOAD_URL" in
    https://*) ;;
    *)
        log_error "Latest release download URL is not HTTPS"
        exit 1
        ;;
esac

ZIP_NAME=$(basename "$DOWNLOAD_URL")
case "$ZIP_NAME" in
    upd_knutle_online_ss_pkg-*.zip) ;;
    *)
        log_error "Latest release asset name is invalid"
        exit 1
        ;;
esac

VERSION=${ZIP_NAME#upd_knutle_online_ss_pkg-}
VERSION=${VERSION%.zip}
old_IFS=$IFS
IFS='.'
# shellcheck disable=SC2086
set -- $VERSION
IFS=$old_IFS
if [ "$#" -ne 3 ]; then
    log_error "Latest release asset version is invalid: $VERSION"
    exit 1
fi
for VERSION_PART in "$@"; do
    case "$VERSION_PART" in
        ''|*[!0-9]*)
            log_error "Latest release asset version is invalid: $VERSION"
            exit 1
            ;;
    esac
done

ZIP="/mnt/us/$ZIP_NAME"
if ! curl -fL --connect-timeout 5 --max-time 120 "$DOWNLOAD_URL" -o "$TEMP_ZIP"; then
    rm -f "$TEMP_ZIP"
    log_error "Could not download $ZIP_NAME"
    exit 1
fi

if [ ! -s "$TEMP_ZIP" ]; then
    rm -f "$TEMP_ZIP"
    log_error "Downloaded release package is empty"
    exit 1
fi

if ! command -v unzip >/dev/null 2>&1; then
    rm -f "$TEMP_ZIP"
    log_error "unzip is not available; downloaded package was not installed"
    exit 1
fi
if ! unzip -tq "$TEMP_ZIP" >/dev/null 2>&1; then
    rm -f "$TEMP_ZIP"
    log_error "Downloaded release package is not a valid ZIP"
    exit 1
fi

mv "$TEMP_ZIP" "$ZIP"

if [ ! -x "$LOCAL_UPDATER" ]; then
    rm -f "$ZIP"
    log_error "Local updater is missing or not executable: $LOCAL_UPDATER"
    exit 1
fi

log_info "Installing $ZIP_NAME"
if ! sh "$LOCAL_UPDATER"; then
    log_error "Local updater failed"
    exit 1
fi
