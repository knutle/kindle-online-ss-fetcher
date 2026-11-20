# Notes

Step 3: Run & Verify in kterm

Before relying on the library Scriptlet, test it once in kterm so you can catch any typos or network issues:
1. Open kterm and run:sh
sh /mnt/us/extensions/online-ss/daemon.sh &
Use code with caution.
2. Verify that /mnt/us/screensavers/current.png appears (ls -lh /mnt/us/screensavers/).
3. Press the power button to put the Kindle to sleep—you should see your fetched image appear.


• RTC Device Check: On most PW5 units, the real-time clock is /dev/rtc0 or /dev/rtc1. If rtcwake doesn't wake it on schedule during testing, check ls /dev/rtc* in kterm and update -d /dev/rtc0 accordingly.
• Image Format: Export your server's image as an 8-bit grayscale PNG at 1236 × 1648 pixels for the fastest rendering and sharpest text on the PW5 screen.


Quick Test in kterm

1. Verify fbink is found by running:sh
find /mnt/us/extensions/custom-screensaver -name "fbink*"
Use code with caution.
2. Start the script manually once in kterm to watch for any output:sh
sh /mnt/us/extensions/online-ss/daemon.sh &
Use code with caution.
3. Temporarily disconnect 10.3.141.1 (or change the URL to a bad path) to confirm the centered error message and timestamp render cleanly on the screen.

## Sample screensaver
Copy the sample screensaver to the remote server. This uploads it to your home
directory first, then uses `sudo` to install it in the protected web directory
(you'll need sudo access on `piro.local`):

```sh
scp screensavers/sample.png piro.local:dashboard-pw.png &&
ssh piro.local 'sudo install -m 0644 "$HOME/dashboard-pw.png" /var/www/html/files/dashboard-pw.png && rm "$HOME/dashboard-pw.png"'
```
