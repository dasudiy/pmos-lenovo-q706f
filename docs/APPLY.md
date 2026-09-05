# Applying the Q706F overlays onto pmaports

## Paths

| This repo | pmaports destination |
| --- | --- |
| `patches/000*.patch` | `device/community/linux-postmarketos-qcom-sm8250/` |
| `patches/APKBUILD.linux-postmarketos-qcom-sm8250` | replace or merge into that package’s `APKBUILD` |
| `kernel-config/q706f-extra.config` | merge into `config-postmarketos-qcom-sm8250.aarch64` |
| `device-lenovo-q706f/*` | `device/testing/device-lenovo-q706f/` |
| `firmware-lenovo-q706f/APKBUILD` | `device/testing/firmware-lenovo-q706f/APKBUILD` |

Current kernel package reference: `linux-postmarketos-qcom-sm8250` **6.17.0-r10** (patches `0001`–`0006`).

## Checksums

After copying files:

```bash
pmbootstrap checksum linux-postmarketos-qcom-sm8250
pmbootstrap checksum device-lenovo-q706f
# firmware zip checksum unchanged; only packaging logic added
```

## Build kernel only

```bash
cd /path/to/pmbootstrap-workdir
pmbootstrap build linux-postmarketos-qcom-sm8250 --arch=aarch64
```

APK output: `packages/v25.12/aarch64/linux-postmarketos-qcom-sm8250-6.17.0-r<N>.apk`

## Install kernel on device (USB networking)

From this repo (device reachable at `asuka@172.16.42.1` by default):

```bash
# Already built: copy latest r*.apk and install
scripts/install-kernel-apk-ssh.sh

# Or sync patches, build, install, then reboot manually
scripts/install-kernel-ssh.sh
```

Override host/device if needed:

```bash
DEVICE=user@192.168.x.x PMOS_WORK=/home/you/pmOS scripts/install-kernel-apk-ssh.sh
```

On device, `apk add` runs `mkinitfs` / `boot-deploy` and flashes `boot_b`. Reboot after install.

## On-device verification snippets

```bash
# Kernel build (brightness fix needs pkgrel >= 10)
uname -r
# e.g. 6.17.0 #11-postmarketos-qcom-sm8250

# suspend / sleep default
cat /sys/power/mem_sleep

# RTC + offset
cat /sys/class/rtc/rtc0/since_epoch
cat /var/cache/swclock-offset/offset-storage
timedatectl

# DP Alt Mode
cat /sys/class/drm/card0-DP-1/status
cat /sys/class/typec/port0-partner/port0-partner.0/displayport/pin_assignment
# as root:
cat /sys/kernel/debug/dri/ae01000.display-controller/DP-1/dp_debug

# Audio
cat /proc/asound/cards
dmesg | grep cs35l45 | grep -E 'Firmware|Failed'
pactl list short sinks

# Brightness (11-bit panel, max 2047; drag GNOME slider — no glitch / black screen)
ls /sys/class/backlight
cat /sys/class/backlight/*/max_brightness
cat /sys/class/drm/card0-DSI-1/status
cat /sys/class/drm/card0-DSI-1/enabled
# while adjusting brightness, this should stay quiet:
doas dmesg -w | grep -iE 'dsi_err|status=5'
```

Single-step sysfs test (optional; should not corrupt the panel on r10+):

```bash
# echo 1024 | doas tee /sys/class/backlight/*/brightness
```
