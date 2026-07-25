# postmarketOS fixes for Lenovo Q706F (Xiaoxin Pad Pro 12.6)

Patches and package overlays for running **postmarketOS** (systemd / GNOME, channel **v25.12**) on the **Lenovo Tab P12 Pro / Xiaoxin Pad Pro 12.6 (Q706F, SM8250)**.

Target kernel package: `linux-postmarketos-qcom-sm8250` **6.17.0** (community SM8250 tree), instead of the old device-specific `linux-lenovo-q706f` 6.11 package.

These changes were developed and verified on a real Q706F with USB-C DisplayPort Alt Mode (AOC 4K monitor), folio keyboard, Wi‑Fi, and speakers.

## Status summary

| Issue | Status |
| --- | --- |
| Cannot wake from sleep | Fixed (`s2idle` + volume-up wakeup) |
| Time resets to 1970 after reboot | Mitigated (RTC driver + swclock; HW RTC not writable) |
| USB-C external display no signal | Fixed (Alt Mode + 4-lane DP) |
| Only Dummy Output / no speakers | Fixed (CS35L45 + firmware symlink) |
| ~90s boot delay waiting for RTC | Fixed (bogus systemd device wait removed) |

## Repository layout

```
patches/                  Kernel patches + reference APKBUILD for linux-postmarketos-qcom-sm8250
kernel-config/            Extra Kconfig options and full config diff vs upstream pmaports
device-lenovo-q706f/      Device package overlays (cmdline, swclock, deviceinfo, APKBUILD)
firmware-lenovo-q706f/    Cirrus firmware package APKBUILD (shared wmfw symlinks)
docs/                     Extra notes
```

Apply these files on top of [pmaports](https://gitlab.postmarketos.org/postmarketOS/pmaports) (v25.12 / systemd channel), then rebuild with `pmbootstrap`.

---

## Problems and fixes

### 1. Cannot wake from sleep

**Symptom:** Tablet goes to sleep and does not wake reliably (or at all) with power / keys.

**Cause:** Default suspend path and missing wakeup source marking for volume-up on this board.

**Fix:**
- Device cmdline: `mem_sleep_default=s2idle`  
  - `device-lenovo-q706f/kernel-cmdline.conf`  
  - `deviceinfo_kernel_cmdline` in `device-lenovo-q706f/deviceinfo`
- DTS patch: mark volume-up as `wakeup-source`  
  - `patches/0001-arm64-dts-qcom-sm8250-lenovo-q706f-vol-up-wakeup.patch`

---

### 2. System time resets to ~1970 after reboot

**Symptom:** After reboot the clock is in 1970 until NTP syncs; cold boot without network is wrong.

**Cause / notes:**
- Community kernel needed `CONFIG_RTC_DRV_PM8XXX=y` so `rtc0` (`rtc-pm8xxx`) appears.
- Hardware RTC **cannot be written** on this device (`RTC_SET_TIME` → `ENODEV`), so the PMIC clock stays in 1970.
- `swclock-offset` stores `system_time - rtc_time` and restores it at boot.

**Fix:**
- Kernel: `CONFIG_RTC_DRV_PM8XXX=y` (see `kernel-config/q706f-extra.config`)
- Device package depends on `swclock-offset`
- Udev: re-run offset when `rtc0` appears  
  - `device-lenovo-q706f/90-swclock-offset-rtc.rules`
- Drop-in for `swclock-offset-boot.service` (see also issue 5 below)

**Limitation:** True hardware timekeeping across power-loss still needs a writable RTC or always-on battery domain; software offset + NTP is the workable path.

---

### 3. USB-C DisplayPort Alt Mode: no signal / black screen

Several layered bugs:

#### 3a. Alt Mode driver not enabled

**Symptom:** No DisplayPort Alt Mode negotiation; DRM `DP-1` stays disconnected.

**Fix:** `CONFIG_TYPEC_DP_ALTMODE=y` (NB7 / FSA4480 muxes already present).

#### 3b. Configure VDM NAK (stuck at `[USB]`, `hpd=0`)

**Symptom:** Partner enters Alt Mode (`active=yes`, SVID `ff01`) but Configure is NAK’d; monitor never gets HPD / video.

**Cause:** Linux 6.17 `typec_displayport` sent **signaling rate = 0** on the first Configure (reads uninitialized `dp->data.conf`). Strict docks (e.g. MediaTek `0e8d:0001`) NAK it.

**Fix:** Backport upstream fix  
- `patches/0002-usb-typec-displayport-fix-signaling-rate-in-Configure.patch`

#### 3c. Only 2 DP lanes → 4K fails / “no signal”

**Symptom:** 1080p works; 4K shows no signal. `dp_debug` shows `num_lanes = 2` while Type-C pin assignment is **C** (4-lane).

**Cause:**
- DTS limited `mdss_dp_out` to `data-lanes = <0 1>`
- QMP combo PHY had orientation-switch but **no mode-switch**, so it stayed in USB+DP combo (2-lane) instead of DP-only (4-lane)

**Fix:**
- Backport QMP Type-C mode-switch series  
  - `patches/0003-phy-qcom-qmp-combo-add-Type-C-mode-switch-for-4-lane-DP.patch`
- DTS: 4 lanes + `mode-switch` on `usb_1_qmpphy`  
  - `patches/0004-arm64-dts-qcom-sm8250-lenovo-q706f-4-lane-DP.patch`

**Verified:** pin **C**, `num_lanes = 4`, HBR2, **3840×2160@60** on an AOC USB-C monitor.

#### 3d. Panel 花屏 after first 6.17 flash

**Symptom:** Corrupted panel after flashing community 6.17 boot image only / with panel as module.

**Fix:** build panel into kernel: `CONFIG_DRM_PANEL_SAMSUNG_AMSA26ZP01=y` (not `=m`), and install matching modules with the boot image.

---

### 4. Audio: only “Dummy Output”

**Symptom:** PulseAudio/PipeWire shows only Dummy Output; `/proc/asound/cards` empty. ADSP remoteproc may still be running.

**Cause:**
1. Community kernel lacked **CS35L45** (board uses four `cirrus,cs35l45` amps; only CS35L41 was enabled) → `snd-sm8250: Primary TDM Playback: codec dai not found`
2. After enabling the driver, `wm_adsp` requests a **shared** firmware name `cirrus/cs35l45-dsp1-spk-prot.wmfw`, but the firmware package only shipped per-speaker files `...-spk1.wmfw` … `...-spk4.wmfw` (identical content)

**Fix:**
- `CONFIG_SND_SOC_CS35L45=m` and `CONFIG_SND_SOC_CS35L45_I2C=m`
- In `firmware-lenovo-q706f` cirrus subpackage, add symlinks:

```text
cs35l45-dsp1-spk-prot.wmfw -> cs35l45-dsp1-spk-prot-spk1.wmfw
cs35l45-dsp1-spk-cali.wmfw -> cs35l45-dsp1-spk-cali-spk1.wmfw
```

See `firmware-lenovo-q706f/APKBUILD`.

**Verified:** all four amps load protection firmware v0.37.0; sink `HiFi__Speaker__sink` appears.

---

### 5. Boot delayed ~90 seconds (“Timed out waiting for … rtc0”)

**Symptom:** Journal: `Timed out waiting for device /sys/subsystem/rtc/devices/rtc0`; userspace startup ~1.5 minutes.

**Cause:** Device drop-in waited for systemd unit `sys-subsystem-rtc-devices-rtc0.device`, but **`/sys/subsystem/rtc/devices/` does not exist**. Real node is `/sys/class/rtc/rtc0` (registered early by the kernel).

**Fix:** Clear the bogus `After=` / `Wants=` in  
`device-lenovo-q706f/swclock-offset-boot-wait-rtc.conf`.  
Late RTC probe (if any) is still handled by the udev rule.

**Verified:** boot ≈ **12.5s** total (kernel + userspace), no RTC wait timeout.

---

### 6. Migration: use community SM8250 kernel

**Change:** `device-lenovo-q706f` depends on `linux-postmarketos-qcom-sm8250` instead of `linux-lenovo-q706f`.

Flash **boot + modules** together (or `apk upgrade` on-device so `mkinitfs` / `boot-deploy` run). Flashing only `boot.img` while rootfs still has 6.11 modules breaks Wi‑Fi / BT / keyboard.

---

## How to apply (outline)

1. Copy overlays into your pmaports tree (paths mirror upstream).
2. Merge `kernel-config/q706f-extra.config` into  
   `device/community/linux-postmarketos-qcom-sm8250/config-postmarketos-qcom-sm8250.aarch64`  
   (or apply `config-postmarketos-qcom-sm8250.aarch64.diff`).
3. Bump `pkgrel`, refresh `sha512sums` (`pmbootstrap checksum …`).
4. Build and install:

```bash
pmbootstrap build --arch aarch64 linux-postmarketos-qcom-sm8250
pmbootstrap build --arch aarch64 device-lenovo-q706f firmware-lenovo-q706f
# on device or via chroot:
apk add --allow-untrusted linux-postmarketos-qcom-sm8250-*.apk \
  device-lenovo-q706f-*.apk firmware-lenovo-q706f-cirrus-*.apk
```

5. Reboot. For DP: use a true **DP Alt Mode** cable/dock; start with 1080p if link training is flaky, then move to 4K once `num_lanes=4`.

## Known remaining limitations

- Hardware RTC is read-only (`RTC_SET_TIME` fails); rely on NTP + `swclock-offset`.
- `CONFIG_BT_RFCOMM` is off in the community config → Bluetooth HFP / some classic profiles fail (`RFCOMM: Protocol not supported`).
- Folio touchpad may log `i2c_hid` incorrect/incomplete reports (usually still usable).
- Early `a650_sqe.fw` load warning then succeeds from an alternate path.

## Upstream

Intended for contribution back to:

- [pmaports](https://gitlab.postmarketos.org/postmarketOS/pmaports)
- [qualcomm-sm8250/linux](https://gitlab.postmarketos.org/soc/qualcomm-sm8250/linux)

Kernel patches 0002/0003 are backports of mainline commits; 0001/0004 are device-specific.

## License

- Kernel patches: GPL-2.0 (same as Linux)
- Device package snippets: MIT (same as `device-lenovo-q706f` in pmaports)
- Firmware packaging: proprietary firmware remains under original terms; this repo only adds packaging/symlinks
