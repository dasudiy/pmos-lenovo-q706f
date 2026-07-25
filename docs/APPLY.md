# Applying the Q706F overlays onto pmaports

## Paths

| This repo | pmaports destination |
| --- | --- |
| `patches/000*.patch` | `device/community/linux-postmarketos-qcom-sm8250/` |
| `patches/APKBUILD.linux-postmarketos-qcom-sm8250` | replace or merge into that package’s `APKBUILD` |
| `kernel-config/q706f-extra.config` | merge into `config-postmarketos-qcom-sm8250.aarch64` |
| `device-lenovo-q706f/*` | `device/testing/device-lenovo-q706f/` |
| `firmware-lenovo-q706f/APKBUILD` | `device/testing/firmware-lenovo-q706f/APKBUILD` |

## Checksums

After copying files:

```bash
pmbootstrap checksum linux-postmarketos-qcom-sm8250
pmbootstrap checksum device-lenovo-q706f
# firmware zip checksum unchanged; only packaging logic added
```

## On-device verification snippets

```bash
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
```
