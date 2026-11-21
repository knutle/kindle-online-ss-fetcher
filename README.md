# Kindle Online Screensaver Fetcher

Periodically fetch a screensaver image from any url and render it on your kindle as a screensaver.

## Notes

* RTC Device Check: On most PW5 units, the real-time clock is /dev/rtc0 or /dev/rtc1. If rtcwake doesn't wake it on schedule during testing, check ls /dev/rtc* in kterm and update -d /dev/rtc0 accordingly.

* Image Format: Export your server's image as an 8-bit grayscale PNG at 1236 × 1648 pixels for the fastest rendering and sharpest text on the PW5 screen.

* Use the `Online Screensaver (Backlight On)` scriptlet to keep the frontlight on; this waits awake instead of using RTC suspend, keeps Wi-Fi enabled between fetches, and uses more battery. Use `Online Screensaver (RTC Suspend)` for low-power RTC suspend, which turns the frontlight off and disables Wi-Fi between fetches.

* The Online Screensaver scriptlet appends daemon output to
`/mnt/us/extensions/online-ss/daemon.log`. Check the latest reconnect attempts with
`tail -n 100 /mnt/us/extensions/online-ss/daemon.log`.

You can also trigger the daemon manually from kterm: `sh /mnt/us/extensions/online-ss/daemon.sh`.

## Todo

* Abort on missing fbink
