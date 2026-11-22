# AGENTS.md

Guidance for agents working on this repository (a POSIX `sh` daemon that runs on a Kindle Paperwhite 5).

## Lessons learned

* **Shell portability**: scripts run under BusyBox `sh` on the Kindle. Use POSIX constructs only (no bashisms, arrays or `[[ ]]`), and avoid tools that may not exist on-device.
* **FBInk binary**: the daemon renders with the bundled `extensions/online-ss/bin/fbink_hf`. Check that it is executable (`-x`) before use and abort with a logged error if not. Don't replace it without being asked.
* **Image geometry**: the PW5 image is 1236 × 1601 px grayscale PNG, rendered at `w=1236,h=1586,y=72`. This keeps content below the status bar and pushes padding past the footer. Keep README and `daemon.sh` in sync if these values change.
* **Ghosting**: use a full waveform refresh (`-f`) every 10 cycles.
* **Wi-Fi handling**: wait for `cmState` = `CONNECTED` *and* a default route before fetching. On retry, only cycle the radio in RTC-suspend mode (`KEEP_BACKLIGHT_ON=0`). Disable Wi-Fi cleanly before suspending to avoid stale driver state on resume.
* **Power modes**: `KEEP_BACKLIGHT_ON=1` stays awake with Wi-Fi on; `0` uses `rtcwake` RTC suspend. The RTC device is `/dev/rtc1` if present, else `/dev/rtc0`. Re-enable `preventScreenSaver` handling carefully when suspend or fetch fails.
* **Fetch safety**: download to a temp file and `mv` into place only after cURL exit 0, HTTP 200 and non-empty output, so a failed fetch never corrupts the current screensaver.
* **Single instance**: the daemon uses a PID file (`/var/run/online_ss.pid`) to prevent duplicates; keep the Stop scriptlet consistent with it.
* **Logging**: use the `log_debug/info/warn/error` helpers (timestamped, Europe/Oslo TZ) rather than raw `echo`. On-screen status goes through FBInk (`render_init`, `render_error`).
* **Docs**: update `README.md` whenever settings, scriptlets or image format change. `screensavers/sample.png` is an example only and is not copied to the device.
* **Testing**: there is no automated test suite; validate with `sh -n extensions/online-ss/daemon.sh` (and `shellcheck` if available).
