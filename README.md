# Kindle Online Screensaver Fetcher

Periodically fetch a screensaver image from any url and render it on your kindle (tested on Paperwhite 5) as a screensaver.

## Installation

Copy the `documents` and `extensions` folders to the root of the Kindle (`/mnt/us`), then edit the settings at the top of `extensions/online-ss/daemon.sh`:

* `URL`: image to fetch
* `WIFI_SSID`: Wi-Fi network to connect to
* `INTERVAL`: seconds between fetches
* `WIFI_CONNECT_TIMEOUT` / `WIFI_CONNECT_ATTEMPTS`: Wi-Fi reconnect behaviour

The daemon renders images with the bundled FBInk binary (`extensions/online-ss/bin/fbink_hf`). It must be executable; if it is missing or not executable, the daemon logs an error and aborts.

## Usage

Start one of the scriptlets from the Kindle library (`documents/`):

* `Online Screensaver (Backlight On)`: keeps the frontlight on and waits awake instead of using RTC suspend. Wi-Fi stays enabled between fetches. Uses more battery.
* `Online Screensaver (RTC Suspend)`: low-power RTC suspend. The frontlight is off and Wi-Fi is disabled between fetches.
* `Online Screensaver Stop`: stops the daemon.

You can also run the daemon manually from kterm: `sh /mnt/us/extensions/online-ss/daemon.sh`.

## Image format

Export your server's image as an 8-bit grayscale PNG at 1236 × 1601 pixels for the fastest rendering and sharpest text on the PW5 screen. The reduced height (instead of the full 1648) lets the image render below the Kindle status bar, avoiding clutter on display updates. The daemon renders the image at a height of 1586 pixels from y=72, so the extra bottom rows (blank padding) overflow past the screen edge, ensuring no rendering artifacts appear below the footer. `screensavers/sample.png` in this repo is only an example and does not need to be copied to the Kindle.

## Troubleshooting

* Logs: the scriptlets append daemon output to `/mnt/us/extensions/online-ss/daemon.log`. Check recent activity with `tail -n 100 /mnt/us/extensions/online-ss/daemon.log`.
* RTC device: on most PW5 units the real-time clock is `/dev/rtc0` or `/dev/rtc1` (the daemon prefers `rtc1` if present). If `rtcwake` doesn't wake the device on schedule, check `ls /dev/rtc*` in kterm and update `RTC_DEV` in `daemon.sh`.
* Fetch failures and Wi-Fi status are shown on screen via FBInk ("DASHBOARD FETCH FAILED" / "INITIALIZING DASHBOARD").
