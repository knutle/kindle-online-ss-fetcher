#!/bin/sh
# Name: Update Online Screensaver (Local ZIP)
# Author: knutle
# Icon:

UPDATE_DIR="/mnt/us/.knutle_online_ss-update"
INSTALLED_ROOT="/mnt/us"
DOCUMENTS_DIR="$INSTALLED_ROOT/documents"
EXTENSIONS_DIR="$INSTALLED_ROOT/extensions"
LOG_DIR="$EXTENSIONS_DIR/online-ss"
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

# Stop the daemon before replacing its files.
PIDFILE="/var/run/online_ss.pid"
if [ -f "$PIDFILE" ]; then
    PID=$(cat "$PIDFILE")
    case "$PID" in
        ''|*[!0-9]*)
            log_error "Ignoring invalid daemon PID: $PID"
            ;;
        *)
            if kill -0 "$PID" 2>/dev/null; then
                log_info "Stopping daemon PID $PID"
                kill "$PID" 2>/dev/null || true
                sleep 2
            fi
            rm -f "$PIDFILE"
            ;;
    esac
fi

if ! command -v unzip >/dev/null 2>&1; then
    log_error "unzip is not available"
    exit 1
fi

rm -rf "$UPDATE_DIR"
mkdir -p "$UPDATE_DIR"

# Merge an existing shell-style config with package defaults. Existing assigned
# values win; assignment lines absent from the existing file are appended.
merge_config() {
    MERGE_EXISTING="$1"
    MERGE_DEFAULT="$2"
    MERGE_OUTPUT="$3"

    if [ -f "$MERGE_EXISTING" ]; then
        cp "$MERGE_EXISTING" "$MERGE_OUTPUT"
    elif [ -f "$MERGE_DEFAULT" ]; then
        cp "$MERGE_DEFAULT" "$MERGE_OUTPUT"
        return
    else
        return
    fi

    if [ -s "$MERGE_OUTPUT" ] && [ "$(tail -c 1 "$MERGE_OUTPUT" 2>/dev/null)" != "" ]; then
        printf '\n' >> "$MERGE_OUTPUT"
    fi
    if [ -f "$MERGE_DEFAULT" ]; then
        while IFS= read -r DEFAULT_LINE || [ -n "$DEFAULT_LINE" ]; do
            case "$DEFAULT_LINE" in
                *=*)
                    DEFAULT_KEY=${DEFAULT_LINE%%=*}
                    case "$DEFAULT_KEY" in
                        ''|*[!A-Za-z0-9_]*) continue ;;
                    esac
                    if ! grep -q "^${DEFAULT_KEY}=" "$MERGE_OUTPUT" 2>/dev/null; then
                        printf '%s\n' "$DEFAULT_LINE" >> "$MERGE_OUTPUT"
                    fi
                    ;;
            esac
        done < "$MERGE_DEFAULT"
    fi
}

# Select and unpack in filename order. The lexically last zip may therefore
# replace earlier ones; processed archives are removed after a successful update.
FOUND=0
for ZIP in $(find /mnt/us -maxdepth 1 -type f -name 'upd_knutle_online_ss_pkg*.zip' | sort); do
    FOUND=$((FOUND + 1))
    log_info "Processing $ZIP"

    EXTRACT_DIR="$UPDATE_DIR/package-$FOUND"
    mkdir -p "$EXTRACT_DIR"
    if ! unzip -q "$ZIP" -d "$EXTRACT_DIR"; then
        log_error "Could not unpack $ZIP"
        rm -rf "$EXTRACT_DIR"
        continue
    fi

    PACKAGE_ROOT="$EXTRACT_DIR"
    if [ ! -d "$PACKAGE_ROOT/documents" ] && [ ! -d "$PACKAGE_ROOT/extensions" ]; then
        if [ -d "$PACKAGE_ROOT/mnt/us/documents" ] || [ -d "$PACKAGE_ROOT/mnt/us/extensions" ]; then
            PACKAGE_ROOT="$PACKAGE_ROOT/mnt/us"
        fi
    fi

    if [ ! -d "$PACKAGE_ROOT/documents" ] && [ ! -d "$PACKAGE_ROOT/extensions" ]; then
        log_error "ZIP contains neither documents nor extensions: $ZIP"
        rm -rf "$EXTRACT_DIR"
        continue
    fi

    # Remove only scriptlets owned by this package namespace. Renamed or deleted
    # old scriptlets are therefore also removed before the new set is copied.
    rm -f "$DOCUMENTS_DIR"/knutle_online_ss_*.sh

    if [ -d "$PACKAGE_ROOT/documents" ]; then
        mkdir -p "$DOCUMENTS_DIR"
        cp -R "$PACKAGE_ROOT/documents/." "$DOCUMENTS_DIR/"
    fi

    if [ -d "$PACKAGE_ROOT/extensions" ]; then
        mkdir -p "$EXTENSIONS_DIR"

        # Back up both supported config names before package files overwrite them.
        for CONFIG_NAME in daemon.conf daemon.sh; do
            INSTALLED_CONFIG="$EXTENSIONS_DIR/online-ss/config/$CONFIG_NAME"
            if [ -f "$INSTALLED_CONFIG" ]; then
                cp "$INSTALLED_CONFIG" "$UPDATE_DIR/old-$CONFIG_NAME"
            else
                rm -f "$UPDATE_DIR/old-$CONFIG_NAME"
            fi
        done

        cp -R "$PACKAGE_ROOT/extensions/." "$EXTENSIONS_DIR/"

        for CONFIG_NAME in daemon.conf daemon.sh; do
            INSTALLED_CONFIG="$EXTENSIONS_DIR/online-ss/config/$CONFIG_NAME"
            PACKAGE_CONFIG="$PACKAGE_ROOT/extensions/online-ss/config/$CONFIG_NAME"

            if [ -f "$PACKAGE_CONFIG" ]; then
                merge_config "$UPDATE_DIR/old-$CONFIG_NAME" "$PACKAGE_CONFIG" "$UPDATE_DIR/new-$CONFIG_NAME"
                mkdir -p "$EXTENSIONS_DIR/online-ss/config"
                cp "$UPDATE_DIR/new-$CONFIG_NAME" "$INSTALLED_CONFIG"
            fi
        done
    fi

    rm -rf "$EXTRACT_DIR"
    rm -f "$ZIP"
    log_info "Updated from $ZIP"
done

if [ "$FOUND" -eq 0 ]; then
    log_info "No packages found matching /mnt/us/upd_knutle_online_ss_pkg*.zip"
fi

rm -rf "$UPDATE_DIR"
