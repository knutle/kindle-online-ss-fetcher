# Kindle Online Screensaver Fetcher

Periodically fetch a screensaver image from any url and render it on your kindle (tested on Paperwhite 5) as a screensaver.

## Installation

Copy the `documents` and `extensions` folders to the root of the Kindle (`/mnt/us`), then edit the settings in `extensions/online-ss/config/daemon.conf`:

* `URL`: image to fetch
* `WIFI_SSID`: Wi-Fi network to connect to
* `INTERVAL`: seconds between fetches
* `WIFI_CONNECT_TIMEOUT` / `WIFI_CONNECT_ATTEMPTS`: Wi-Fi reconnect behaviour

The daemon renders images with the bundled FBInk binary (`extensions/online-ss/bin/fbink_hf`). It must be executable; if it is missing or not executable, the daemon logs an error and aborts.

## Usage

Start one of the scriptlets from the Kindle library (`documents/`):

* `Online Screensaver (Backlight On)` (`documents/knutle_online_ss_backlight_on.sh`): keeps the frontlight on and waits awake instead of using RTC suspend. Wi-Fi stays enabled between fetches. Uses more battery.
* `Online Screensaver (RTC Suspend)` (`documents/knutle_online_ss_rtc_suspend.sh`): low-power RTC suspend. The frontlight is off and Wi-Fi is disabled between fetches.
* `Stop Online Screensaver` (`documents/knutle_online_ss_stop.sh`): stops the daemon.
* `Update Online Screensaver (Local ZIP)` (`documents/knutle_online_ss_update_local.sh`): updates the extension only from package ZIP files already in `/mnt/us`.
* `Update Online Screensaver (Latest Release)` (`documents/knutle_online_ss_update_auto.sh`): connects to Wi-Fi, downloads the ZIP asset from the latest published GitHub Release, and installs it.

You can also run the daemon manually from kterm: `sh /mnt/us/extensions/online-ss/daemon.sh`.

## Updating

Place one or more ZIP packages matching `upd_knutle_online_ss_pkg*.zip` in `/mnt/us`, then run `Update Online Screensaver (Local ZIP)` from the Kindle library. To download and install the newest published release automatically, run `Update Online Screensaver (Latest Release)` instead. A package should contain the `documents/` and `extensions/` directories to install. Existing package scriptlets are identified by the `knutle_online_ss_` filename prefix, so renamed or deleted scriptlets are removed during updates.

The updater preserves assignments already in `extensions/online-ss/config/daemon.conf` (and legacy `daemon.sh`) and appends assignments from the package's default config if they do not exist. Successfully processed package ZIPs are removed.

The local mode does not access the network. Packages are selected in filename order, so the lexically last matching package replaces earlier matches.

The automatic mode reads `WIFI_SSID` from the installed daemon config, enables the Wi-Fi manager, and waits up to 30 seconds for both `cmState=CONNECTED` and a default route. It then queries `https://api.github.com/repos/knutle/kindle-online-ss-fetcher/releases/latest`. Only the published latest release is considered: draft releases are excluded by the API, and only an HTTPS asset named `upd_knutle_online_ss_pkg-MAJOR.MINOR.PATCH.zip` is accepted.

The automatic updater validates that the download is non-empty and a valid ZIP before handing it to the local updater. It uses `jq` when available and falls back to a POSIX `sed` parser on Kindle shells. Both updater modes write timestamped entries to `/mnt/us/extensions/online-ss/update.log`.

Example package layout:

```text
upd_knutle_online_ss_pkg-1.2.3.zip
  documents/knutle_online_ss_backlight_on.sh
  documents/knutle_online_ss_rtc_suspend.sh
  documents/knutle_online_ss_stop.sh
  documents/knutle_online_ss_update_local.sh
  documents/knutle_online_ss_update_auto.sh
  extensions/online-ss/daemon.sh
  extensions/online-ss/bin/fbink_hf
  extensions/online-ss/config/daemon.conf
```

## Releases

Merge this release workflow into the default branch before creating the first release branch. GitHub may reject release operations performed with `GITHUB_TOKEN` when the release commit introduces or changes workflow files relative to the default branch.

Create and push a branch named `release/vMAJOR.MINOR.PATCH`, for example `release/v1.2.3`. Versions use stable SemVer numeric components without leading zeroes. The release workflow packages the tracked `documents/` and `extensions/` files from that commit, creates the matching `v1.2.3` tag and draft GitHub Release, and attaches `upd_knutle_online_ss_pkg-1.2.3.zip`.

Further pushes refresh the draft's tag and ZIP. Publish a draft manually only after its latest release workflow run succeeds; do not publish while the workflow is updating the tag or release. Once published, the release and tag must not be changed by this workflow: use a new version branch for the next release. Existing tags or releases not owned by the workflow cause it to fail instead of being overwritten. If release creation fails after the tag is pushed, inspect and manually remove the orphan tag before retrying.

The workflow requires GitHub Actions to have `contents: write` permission. The automatic updater discovers the tag and versioned ZIP asset using GitHub's published latest-release API; drafts are not returned by that endpoint.
## Image format

Export your server's image as an 8-bit grayscale PNG at 1236 × 1601 pixels for the fastest rendering and sharpest text on the PW5 screen. The reduced height (instead of the full 1648) lets the image render below the Kindle status bar, avoiding clutter on display updates. The daemon renders the image at a height of 1586 pixels from y=72, so the extra bottom rows (blank padding) overflow past the screen edge, ensuring no rendering artifacts appear below the footer. `screensavers/sample.png` in this repo is only an example and does not need to be copied to the Kindle.

## Troubleshooting

* Logs: the run scriptlets append daemon output to `/mnt/us/extensions/online-ss/daemon.log`, and both updater scriptlets write timestamped severity logs to `/mnt/us/extensions/online-ss/update.log` while also printing to the console. Check recent activity with `tail -n 100 /mnt/us/extensions/online-ss/daemon.log` and `tail -n 100 /mnt/us/extensions/online-ss/update.log`.
* RTC device: on most PW5 units the real-time clock is `/dev/rtc0` or `/dev/rtc1` (the daemon prefers `rtc1` if present). If `rtcwake` doesn't wake the device on schedule, check `ls /dev/rtc*` in kterm and set `RTC_DEV` in `config/daemon.conf`.
* Fetch failures and Wi-Fi status are shown on screen via FBInk ("DASHBOARD FETCH FAILED" / "INITIALIZING DASHBOARD").
