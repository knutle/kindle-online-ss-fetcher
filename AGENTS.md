# Agent notes

Living document. Add lessons from each task; fix anything that turns out wrong.

## Kindle runtime

- The daemon and scriptlets in `documents/` are `/bin/sh` scripts for a Kindle Paperwhite 5. Keep them compatible with the device's shell and utilities; desktop validation cannot substitute for testing on the Kindle.
- The two start scriptlets select daemon modes by passing `1` (backlight on) or `0` (RTC suspend); an omitted argument defaults to `1`. Keep scriptlet names, arguments, and README usage consistent.
- Mode `1` waits awake with the frontlight on and leaves Wi-Fi enabled between fetches. Mode `0` disables Wi-Fi before `rtcwake -m mem` and reconnects for the next fetch. A real memory suspend cannot reliably keep the frontlight illuminated; do not treat a brightness or `preventScreenSaver` setting as a substitute for avoiding suspend.
- The URL must return an image, not HTML. The daemon downloads it to a temporary file and invokes the executable `bin/fbink_hf` resolved relative to `daemon.sh`; fail clearly if it is missing or not executable.
- Keep the start and stop scriptlets consistent with the daemon's PID file, Wi-Fi lifecycle, and `preventScreenSaver` handling.
- The scriptlets append daemon output to `/mnt/us/extensions/online-ss/daemon.log`. Use the daemon's timestamped severity log helpers and `run_lipc_set_prop` for LIPC setters so failures and exit statuses remain visible.

## Wi-Fi and suspend

- Enabling the radio alone is not proof of connectivity. The daemon enables both `com.lab126.cmd wirelessEnable` and `com.lab126.wifid enable`, requests the saved SSID with `ensureConnection`, then waits for `cmState` to be `CONNECTED` and for a default route.
- During troubleshooting, the radio enabled successfully but `cmState` remained `PENDING` after wake, sometimes requiring a device restart. Successful LIPC exit codes do not prove association completed. The current suspend mode disables the manager and radio before suspend; treat this as a device-specific workaround, not a proven universal fix.
- Preserve bounded connection attempts and diagnostics. Do not treat an HTTP error as evidence that Wi-Fi needs cycling. Avoid repeatedly power-cycling the radio while an association is still in progress.
- Do not log or request Wi-Fi passwords. Logs and configuration may contain network names, URLs and addresses; redact them when sharing diagnostics.

## Display and verification

- On the PW5, preserve the status-bar offset (`y=72`, rendered height `1586`) and the documented 1236 x 1601 image format and padding unless intentionally changing the layout. The daemon uses a full waveform refresh every ten successful cycles to mitigate ghosting.
- Rendering and Wi-Fi shutdown have deliberate delays around initialization and suspend. Do not remove them without on-device verification; the Kindle UI can draw over the initialization screen.
- For shell changes, run `sh -n` on the affected scripts and ShellCheck if available. On-device, test start and stop, a successful fetch, a failed fetch, and multiple suspend/wake/reconnect cycles in the relevant modes; inspect the daemon log and screen. State explicitly when device testing was not possible.
