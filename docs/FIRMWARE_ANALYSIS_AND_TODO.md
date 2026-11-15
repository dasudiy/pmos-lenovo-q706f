# Lenovo Xiaoxin Pad Pro 12.6 (TB-Q706F)
## Android Firmware Reverse Engineering & Linux Porting Reference

**Target System:** Fedora 44 Workstation, Linux Kernel 7.2.0 (`postmarketos-qcom-sm8250`)  
**Firmware Dump:** `TB-Q706F_USR_S530352_Q00050_ROW`  
**Host / Device Verification:** Verified via live SSH inspection (the tablet)

---

## 1. Executive Summary & Live Device Status

The tablet currently boots stably into Fedora 44 with GNOME on mainline Linux 7.2.0. Display, 4K DP Alt Mode, 4-channel audio amplification, touch, folio keyboard/touchpad, WiFi, and GPU acceleration are operational.

### Hardware Status Matrix

| Subsystem | Live Status | Diagnostic Findings | Firmware / Solution Source |
| :--- | :---: | :--- | :--- |
| **Display & Backlight** | ✅ Working | Samsung AMSA26ZP01 2.5K OLED, 628/2047 brightness | In-tree panel driver + MSM DSI patch |
| **DP Alt Mode** | ✅ Working | QMP Combo PHY 4-lane DisplayPort | Upstream patches + DTS mode-switch |
| **Touchscreen** | ✅ Working | Goodix Berlin on SPI13 (`input12`) | DTS SPI13 CS patch |
| **Folio Keyboard / Touchpad** | ✅ Working | 17EF:6127 (`i2c-3`) & Elan 04F3:31F3 (`i2c-9`) | Android DTBO HID descriptor override |
| **Audio (Output)** | ✅ Working | 4× Cirrus CS35L45 amps, ADSP running | Protection fw loaded (`v0.37.0`), WirePlumber 16-bit sink |
| **GPU & Display Controller** | ✅ Working | Adreno 650, GMU firmware v2.1.8 | In-tree Freedreno / MSM DRM |
| **WiFi (ath11k)** | ✅ Working | QCA6390 hw2.0, connected | Generic firmware loaded; BDF tune available |
| **Battery Fuel Gauge** | ✅ Working | TI bq27541 (`i2c@884000`), voltage, current, cycle | DT bq27541 driver |
| **ADSP Remoteproc** | ✅ Working | Up via `q706f-adsp.service` | Rootfs delayed start |
| **SLPI Remoteproc** | ✅ Working | Early boot still logs `-ENOENT`; the updated unit starts it after local-fs. Firmware booted (`slpi.mbn`). Running on the live tablet | `q706f-adsp.service` |
| **CDSP Remoteproc** | ✅ Working | Same as SLPI. `cdsp.mbn` booted. Running on the live tablet | Same unit |
| **Bluetooth (BlueZ)** | ✅ Working | Controller with a public address, powered. Tablet `persist` has no `bluetooth/` directory; the address is the Wi-Fi MAC + 1 (`XX:XX:XX:XX:XX:XX`), from `/etc/q706f-bt-addr` or derived by the script | `q706f-bt-addr.service` |
| **Bluetooth (Profiles)** | ✅ Working | 7.2.0 `#5` has `rfcomm` and `bnep` loaded (`rfcomm` used by 4, `bnep` by 2) | Flashed `boot_b` with `out/boot-r4.img` |
| **Charging (PM8150B)** | ✅ Working | `pm8150b-charger` supply is online, status Charging, USB. Port role is sink. Battery was already full (100%) | Patch `0012` on kernel `#5` |
| **Sensors (IIO)** | ❌ Missing | No accelerometer, gyro, ALS, or proximity | SLPI firmware + `persist` calibration + `libssc` |
| **Camera (CAMSS)** | ✅ Working (soft ISP) | Front OV8856 (`0016`) and rear OV13B10 (`0017`–`0019`) probe and stream. Kernel `#8` (patches `0001`–`0019`, modules signed by that build) and libcamera `0.7.1-2.q706f1` (OV8856 / OV13B10 sensor helpers) are deployed with `cma=256M`; system `cam` captures from both cameras at about 30 fps (2026-10-13, see 4k). No 3A tuning file yet. Rear aux GC5035/S5K5E9, alt S5K4H7, VCM and EEPROM have no driver | Tuning YAML for the soft ISP; rear VCM driver |
| **PCIe Regulators** | ⚠️ Cosmetic | Unused PCIe2 is already disabled (`0008`). Wi-Fi PCIe0 already has `vdda` supplies | No further map to port |

---

## 2. Firmware Partition Analysis & Value Breakdown

```
TB-Q706F_USR_S530352_Q00050_ROW/image/
├── boot.img          -> Android base kernel & master Device Tree Blob (DTB)
├── dtbo.img          -> Camera sensors, display panels, peripheral DTBO fragments
├── persist.img       -> Device-specific factory calibration (BT MAC, Audio cal, Sensors)
├── NON-HLOS.bin      -> Modem subsystem & board-specific WiFi BDF files (FAT16)
├── dspso.bin         -> Hexagon DSP shared objects (SLPI / ADSP / CDSP) (ext4)
├── BTFM.bin          -> Bluetooth NVM & FM firmware images (FAT16)
└── super_*.img       -> Android Super Partition (vendor/system/product)
```

---

### Tier 1: Immediate & High Value

#### A. `dtbo.img` — Camera Bringup (Primary Missing Feature)
* **What it contains:** Board-specific device tree overlays compiled for Lenovo's board revisions (`hwboardid=783`).
* **Value for Linux:**
  * Slot wiring per connector (role, orientation, actuator / EEPROM / flash links). No part numbers; those are in `vendor` (see E and Step 4).
  * CCI (Camera Control Interface) bus mapping (`cam_cci0`, `cam_cci1`) and CCI master per slot. No I2C `reg`; the addresses come from the vendor CamX modules (Step 4).
  * Power supply regulators (`cam_vio`, `cam_vana`, `cam_vdig`), power sequences, and reset/standby GPIOs.
  * CSI-2 data lane count and lane routing to Qualcomm CSID/CSIPHY.
* **Extraction:**
  ```bash
  # Extract DTB slices from Android DTBO image
  python3 -c "
  import struct, sys
  with open('image/dtbo.img', 'rb') as f:
      magic, total_size, hdr_size, entry_size, version, flags, count = struct.unpack('>4sIIIIII', f.read(28))
      print(f'DTBO Entries: {count}')
      for i in range(count):
          f.seek(hdr_size + i * entry_size)
          dt_size, dt_offset = struct.unpack('>II', f.read(8))
          f.seek(dt_offset)
          data = f.read(dt_size)
          with open(f'dtbo_entry_{i:02d}.dtb', 'wb') as out:
              out.write(data)
          print(f'Wrote dtbo_entry_{i:02d}.dtb ({dt_size} bytes)')
  "
  # Decompile to DTS:
  for f in dtbo_entry_*.dtb; do dtc -I dtb -O dts "$f" -o "${f%.dtb}.dts"; done
  grep -rn "camera" dtbo_entry_*.dts
  ```

#### B. `boot.img` — Charging, PCIe & Missing SoC Peripherals
* **What it contains:** Stock Qualcomm kernel and appended base DTB (`qcom/sm8250.dtb`).
* **Value for Linux:**
  * **PM8150B Charger:** Complete configuration for `qcom,pm8150b-charger` / `qcom,smb1390-charger` (charge currents, thermal mitigation thresholds, OTG VBUS regulators).
  * **PCIe Regulators:** Missing regulator phandles (`vdda`, `vddpe-3v3`) resolving boot log spam.
  * **Type-C / TCPM:** Fast role swap and sink configuration.
* **Extraction:**
  ```bash
  mkdir -p /tmp/stock_boot && cd /tmp/stock_boot
  # Unpack boot.img
  python3 -c "
  import sys
  # Using unpack_bootimg or split by DTB magic 0xd00dfeed
  with open('image/boot.img', 'rb') as f:
      content = f.read()
  pos = 0
  idx = 0
  while True:
      p = content.find(b'\xd0\x0d\xfe\xed', pos)
      if p == -1: break
      size = int.from_bytes(content[p+4:p+8], 'big')
      with open(f'kernel_dtb_{idx:02d}.dtb', 'wb') as out:
          out.write(content[p:p+size])
      pos = p + 4
      idx += 1
  print(f'Extracted {idx} DTB blobs')
  "
  for f in kernel_dtb_*.dtb; do dtc -I dtb -O dts "$f" -o "${f%.dtb}.dts"; done
  grep -rn "pm8150b_charger" kernel_dtb_*.dts
  ```

#### C. `persist.img` — Hardware Calibration & Factory Identity
* **What it contains:** Standard ext4 partition mounted at `/mnt/vendor/persist` in Android.
* **Value for Linux:**
  * **Bluetooth MAC:** Actual factory BDADDR (`bluetooth/.bid` or `bt_nv.bin`). Fixes BlueZ without spoofing.
  * **Audio Speaker Calibration:** Per-channel speaker impedance measurements for the 4× CS35L45 amps.
  * **Sensor Registry:** `sensors/sns.reg` contains accelerometer/gyro/ALS calibration matrices and axes orientation.
  * **WiFi MAC:** Factory MAC for QCA6390.
* **Extraction:**
  ```bash
  mkdir -p /tmp/persist_mnt
  sudo mount -o ro,loop image/persist.img /tmp/persist_mnt
  ls -laR /tmp/persist_mnt/
  # Important files:
  # /tmp/persist_mnt/bluetooth/
  # /tmp/persist_mnt/sensors/
  # /tmp/persist_mnt/audio/
  ```

---

### Tier 2: Medium Value (Tuning & Enhancements)

#### D. `NON-HLOS.bin` — WiFi Board Data File (BDF) Tuning
* **What it contains:** FAT16 filesystem containing Qualcomm modem, WiFi, and GPS firmware.
* **Value for Linux:**
  * `image/bdwlan*` / `WCNSS_qcom_cfg.ini`: Lenovo specific RF calibration and transmit power tables for ath11k.
* **Extraction:**
  ```bash
  mkdir -p /tmp/nonhlos_mnt
  sudo mount -o ro,loop image/NON-HLOS.bin /tmp/nonhlos_mnt
  find /tmp/nonhlos_mnt -iname "*bdwlan*" -o -iname "*wcnss*"
  ```

#### E. `super_*.img` -> `vendor` Partition
* **What it contains:** Android vendor userspace drivers and HAL configurations.
* **Value for Linux:**
  * `vendor/etc/mixer_paths*.xml`: Audio routing sequences for mic paths, speaker modes, and jacks.
  * `vendor/etc/sensors/`: Hardware sensor configuration (I2C address, SPI bus, orientation matrix).
  * `vendor/etc/thermal-engine.conf`: Lenovo's thermal mitigation tables and trip temperatures.
  * `vendor/lib64/camera/`: CamX sensor modules (`com.qti.sensormodule.*.bin`: I2C addresses, chip IDs, power sequences, modes) and tuning (`com.qti.tuned.*.bin`). Decoded in Step 4.
* **Extraction:**
  ```bash
  simg2img image/super_1.img image/super_2.img image/super_3.img \
           image/super_4.img image/super_5.img image/super_6.img /tmp/super.raw
  lpunpack /tmp/super.raw /tmp/super_extracted/
  mkdir -p /tmp/vendor_mnt
  sudo mount -o ro,loop /tmp/super_extracted/vendor.img /tmp/vendor_mnt
  # In this dump super_6.img is already the vendor ext4 image; no root needed:
  debugfs -R 'rdump /lib64/camera /tmp/vendor_camera' image/super_6.img
  ```

---

## 3. Immediate Action Plan

### Step 1: Fix SLPI / CDSP Firmware Boot Delay — installed, DSPs running

`q706f-adsp.service` on the tablet now starts `adsp`, `cdsp`, and `slpi` after `local-fs.target`. Early boot still logs firmware `-ENOENT` for all three. ADSP then comes up from the unit. SLPI and CDSP firmware also boot once started (`slpi.mbn`, `cdsp.mbn`). All three are `running` on the live system. The sound card is `Xiaoxin Pad Pro`.

### Step 2: Fix Bluetooth Controller Activation — config and userspace done

The tablet `persist` partition (`sda2`) has audio calibration and a sensor registry, and no `bluetooth/` directory. `q706f-bt-addr.service` therefore uses `/etc/q706f-bt-addr`. On this device that file holds the Wi-Fi MAC + 1 (`wlp1s0` permanent address + 1, written here as `XX:XX:XX:XX:XX:XX`). Without the file the script derives the same value from `wlp1s0`; see `fedora/overlay/etc/q706f-bt-addr.example`. Checked live on 7.2.0 `#4`: BlueZ shows that public controller, powered, with A2DP UUIDs. The old unit called `btmgmt` before `hci0` existed (`Invalid Index`) and left the controller unconfigured.

The running kernel is 7.2.0 `#5`. `rfcomm` and `bnep` are loaded.

### Step 3: Enable PM8150B Charger in DTS — booted on kernel `#5`

Android's charger node is the downstream `qcom,qpnp-smb5` / `qcom,smb1390-charger-psy` binding. The 7.2.0 driver that matches `qcom,pm8150b-charger` only needs `monitored-battery` and programs the float from `voltage-max-design-microvolt`.

Patch `0012` enables the charger, sets that voltage to `4490000` (`qcom,max-voltage-uv` on PVT1 WIFI, board-id `0x30d08`), and sets `try-power-role = "sink"` on the dual-role connector. The SMB1390 charge pump (9.5 A) has no mainline driver here, so current stays on the PMIC SMB5 path. On the `#5` boot the supply was online and Charging; the battery was already full, so input current sat around 100 mA with `current_max` at 500 mA.

### Step 4: Camera Device Tree Bringup — front OV8856 and rear OV13B10 working with libcamera (2026-10-13)

PVT1 and PVT2 WIFI (`0x30d08` and `0x30f08`) use the same camera slots; the two DTBO entries differ only in `model` and `qcom,board-id`. The DTBO (`dtbo_14`, PVT2) gives the wiring of each slot: CCI controller and master, CSIPHY, MCLK pin, reset GPIO, and rails. It has no part numbers and no I2C `reg`. The part numbers, I2C addresses, chip IDs, power sequences, and sensor modes are in the vendor CamX sensor modules. This section was updated on 2026-10-12 from a decode of those modules.

#### 4a. Source and parsing method

* `super_6.img` in the firmware dump is the `vendor` partition as a plain ext2/ext4 image, not a sparse one. It was read without mounting and without root: `debugfs -R 'rdump /lib64/camera <out>' image/super_6.img`, and the same for `/etc/camera`. `chown` warnings from `debugfs` are harmless.
* `vendor/etc/camera/camxoverridesettings.txt` only has log masks and the output format. It has no addresses.
* `vendor/lib64/camera/com.qti.sensormodule.<vendor>_<sensor>.bin` files are "QTI Chromatix Header" / "Parameter Parser V2.0.0 (1910091319)" binaries. The format is:
  * A symbol table of 0x48-byte entries: id, name, data offset, size.
  * A data area of 8-byte slots. Its start is the u64 at file offset `0xc0`.
  * Strings are stored as `(length, symbol id)` pairs.
* In `sensorDriverData`, the slave info is at data area + `0x18`, in this order: name, `slaveAddress`, `regAddrType`, `regDataType`, `sensorIdRegAddr`, `sensorId`, `sensorIdMask`, `i2cFrequencyMode`, power-up list, power-down list. `actuatorDriver` and `EEPROMDriverData` follow the same pattern.
* Cross-checks:
  * All five sensor IDs match the datasheet and mainline values.
  * The Qualcomm reference module `semco_imx586.bin` decodes as `0x34` (7-bit `0x1A`) with ID `0x0586` at `0x0016`, which is correct for IMX586.
  * The OV13B10 pixel clock gives exactly the 560 MHz link frequency that mainline `ov13b10.c` uses.
* The meanings of the enum values are inferred from CamX naming, not read from the files:
  * `regAddrType`/`regDataType`: 1 = 8-bit, 2 = 16-bit.
  * `i2cFrequencyMode`: 1 is probably FAST, 400 kHz.
  * Power types other than MCLK.
* The parser scripts (`chromatix_*.py`), the exported vendor files, and the raw dumps are in `/tmp/q706f-fw-analysis/` on the build host. That is tmpfs and is lost on reboot. They are not part of this repo.

#### 4b. Slot / chip table

Addresses are given as CamX 8-bit, then Linux 7-bit. File offsets are absolute offsets in the named `.bin` (all under `vendor/lib64/camera/`).

| Slot | Module | Sensor | CCI / mainline bus | Sensor addr 8 / 7-bit | Chip ID reg → value | Actuator | EEPROM / OTP | Flash | Source |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `cam-sensor0` rear main, CSIPHY0 | `ofilm_ov13b10` | OV13B10 | `cam_cci0` master 0 → `cci0_i2c0` | `0x6C` / `0x36` | `0x300B` (16-bit addr, 16-bit read) → `0x0D42` | DW9763 `0x18` / `0x0C` | external EEPROM `0xB0` / `0x58`, 16-bit addr, 8-bit data, reads `0x0000`–`0x1FFF` | PMIC (`pmic`), see below | `com.qti.sensormodule.ofilm_ov13b10.bin`: addr `0xc098`, ID reg `0xc0a8`, ID `0xc0b8`, actuator addr `0xc440`, EEPROM addr `0xc598`, EEPROM read map `0x11ca0` |
| same | `txd_ov13b10` | OV13B10 | same | `0x6C` / `0x36` | `0x300B` → `0x0D43` (see caveats) | GT9768 `0x18` / `0x0C` | external EEPROM `0xB0` / `0x58`, same map | PMIC | `com.qti.sensormodule.txd_ov13b10.bin`: same offsets |
| `cam-sensor1` rear aux, CSIPHY1 | `gcore_gc5035` | GC5035 | `cam_cci0` master 1 → `cci0_i2c1` | `0x7E` / `0x3F` | `0xF0` (8-bit addr, 16-bit read) → `0x5035` | none | sensor OTP at the sensor address `0x7E` | none | `com.qti.sensormodule.gcore_gc5035.bin`: addr `0x1d828`, ID `0x1d848`, EEPROM `0x1db68` |
| same (alternate) | `ofilm_s5k5e9yx04` | S5K5E9 | same | `0x5A` / `0x2D` | `0x0000` (16-bit) → `0x559B` | none | sensor OTP `0x5A` | none | `com.qti.sensormodule.ofilm_s5k5e9yx04.bin`: addr `0x102f8`, ID `0x10318`, EEPROM `0x10638` |
| `cam-sensor2` front, CSIPHY2 | `qtech_ov8856` | OV8856 | `cam_cci1` master 0 → `cci1_i2c0` | `0x6C` / `0x36` | `0x300B` → `0x885A` | none | sensor OTP `0x6C` | none in DT (CamX module config lists `pmic`) | `com.qti.sensormodule.qtech_ov8856.bin`: addr `0xfa88`, ID `0xfaa8`, EEPROM `0xfdc8` |
| `cam-sensor3` front alternate, CSIPHY2 | `txd_s5k4h7rgb` | S5K4H7 | `cam_cci1` master 0 → `cci1_i2c0` | `0x20` / `0x10` | `0x0000` → `0x487B` | none | sensor OTP `0x20` | none | `com.qti.sensormodule.txd_s5k4h7rgb.bin`: addr `0x7f10`, ID `0x7f30`, EEPROM `0x8250` |

What each column is based on:

* **Parsed from firmware:** addresses, chip ID registers and values, actuator and EEPROM addresses, EEPROM read map, module names, and the actuator part per module (`dw9763` for OFilm, `gt9768` for TXD).
* **From DTBO (`dtbo_14.dts`):** slot wiring, CCI controller and master, CSIPHY, MCLK pin, and reset GPIO.
  * `fragment@44` targets `cam_cci0`.
  * `fragment@45` targets `cam_cci1`.
  * Phandle `0x16` is `pm8009@a/pinctrl@c000`.
* **Inferred, not stated in any file:** which module sits in which slot. CamX probes every module on every slot. The pairing above comes from matching:
  * OV8856's power sequence uses MCLK 19.2 MHz, which only `cam-sensor2` has, and its `maxRollDegree` is 270, which matches the front roll of 270.
  * S5K4H7 uses 24 MHz, which matches `cam-sensor3`.
  * OV13B10 is the only 4-lane module with an actuator and flash, so it goes on `cam-sensor0`.
  * The two 5 MP 2-lane modules go on `cam-sensor1`.
* The two front candidates do not collide on `cci1_i2c0` (`0x36` and `0x10`).
* The OFilm and TXD OV13B10 modules share the sensor, actuator, and EEPROM addresses. CamX tells them apart by the expected ID, `0x0D42` or `0x0D43`, and possibly by EEPROM content. How the real part gets matched to the TXD entry is not known.

**Flash:** this is a PMIC flash LED, not an I2C device. `qcom,camera-flash0` points to `pm8150l@4` (SPMI SID 4), `qcom,leds@d300` (`qcom,qpnp-flash-led-v2`): `flash_0` and `flash_1` (max 1000 mA each), `torch_0` and `torch_1`, and `led_switch_2`. In mainline this is `&pm8150l_flash`, already `okay` in our DT and bound on the tablet (see 4e).

Slot wiring from the DTBO:

| Node | Role | CSIPHY | CCI (controller / master) | MCLK | Reset | Rails | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `cam-sensor0` | rear main | 0 | `cam_cci0` / 0 | 24 MHz, TLMM 94 | PM8009 GPIO1 | VIO 1.8 V, VANA 2.8 V, VDIG 1.2 V, VAF 2.8 V | actuator + flash + EEPROM. OV13B10 slot |
| `cam-sensor1` | rear aux | 1 | `cam_cci0` / 1 | 24 MHz, TLMM 95 | PM8009 GPIO3 | VIO 1.8 V, VANA 2.8 V, VDIG 1.2 V | no actuator. GC5035 or S5K5E9 |
| `cam-sensor2` | front | 2 | `cam_cci1` / 0 | 19.2 MHz, TLMM 96 | PM8009 GPIO4 | VIO 1.8 V, VANA 2.8 V, VDIG 1.25 V | roll 270. OV8856 (inferred) |
| `cam-sensor3` | front alternate | 2 | `cam_cci1` / 0 | 24 MHz, TLMM 96 | PM8009 GPIO4 | same as sensor2 | same pins. S5K4H7 (inferred) |
| `cam-sensor4` | rear alternate | 0 | `cam_cci0` / 0 | — | — | extra BOB rail | `status = "disabled"` |
| `cam-sensor5`, `cam-sensor6` | alternates | 1 and 2 | `cam_cci0` / 1, `cam_cci1` / 0 | — | pinctrl / reset phandles unresolved (`0xffffffff`) | | `status = "ok"` but not mapped to any module |

Android supply phandles:

* `pm8009_l7`: `cam_vio` on all slots.
* `pm8009_l5`: `cam_vana` on sensor0.
* `pm8009_l6`: `cam_vana` on sensor1, 2, and 3.
* `pm8009_l1`: `cam_vdig` on sensor0.
* `pm8009_l2`: `cam_vdig` on sensor1.
* `pm8009_l3`: `cam_vdig` on sensor2 and 3.
* `pm8150a_l4`: `cam_vaf` on sensor0.

#### 4c. MCLK, lanes, link frequency

Only the first resolution mode of each module is listed. Link frequency is derived as `outputPixelClock × 10 / lanes / 2`. That is exact for OV13B10 against mainline; the other values are derived only.

| Sensor | MCLK (CamX power-up, matches DTBO) | Lanes | First mode | `outputPixelClock` | Link frequency |
| --- | --- | --- | --- | --- | --- |
| OV13B10 | 24 MHz | 4 | 4208×3120 RAW10, 30 fps (1 mode) | 448 MHz | **560 MHz** (matches mainline) |
| GC5035 | 24 MHz | 2 | 2592×1944 RAW10 (3 modes) | 210.4 MHz | ≈526 MHz (derived) |
| S5K5E9 | 24 MHz | 2 | 2592×1944 RAW10 (4 modes) | 175.2 MHz | ≈438 MHz (derived) |
| OV8856 | 19.2 MHz | 4 | 3264×2448 RAW10, 30 fps | 295.04 MHz | ≈368.8 MHz (derived; mainline 4-lane menu is 360 / 180 MHz) |
| S5K4H7 | 24 MHz | 4 | 3264×2448 RAW10, 30.03 fps | 292.8 MHz | ≈366 MHz (derived) |

All modules have `laneAssign = 0x3210`, which means lanes 0–3 in order.

**Power-up order** (CamX `powerSetting`):

* The MCLK type is confirmed by its frequency value. The other type names (VANA, VDIG, VIO, VAF, RESET) follow the CamX enum and are inferred.
* Delays are raw CamX values; milliseconds is assumed.

| Sensor | Power-up | Power-down |
| --- | --- | --- |
| OV13B10 (both modules) | RESET low (2) → VANA → VDIG → VIO → MCLK 24 MHz (10) → VAF → RESET high (2) | MCLK off → RESET low (2) → VAF → VIO → VDIG → VANA |
| GC5035 | RESET low (1) → VIO (5) → VDIG (5) → VANA (5) → MCLK 24 MHz (5) → RESET high (1) | — |
| S5K5E9 | RESET low (1) → VANA (1) → VDIG (1) → VIO → MCLK 24 MHz (10) → RESET high (18) | — |
| OV8856 | RESET low (1) → VANA → VDIG → VIO → MCLK 19.2 MHz (1) → RESET high (1) | — |
| S5K4H7 | RESET low (1) → VANA → VDIG → VIO → RESET high (1) → MCLK 24 MHz (1) | — |

**Actuator init writes:** DW9763 and GT9768 modules are identical. The device is at `0x18`/`0x0C`, with 8-bit registers and 8-bit data, and 100 µs after each write:

```
0x02 <- 0x02
0x02 <- 0x02
0x06 <- 0x41
0x07 <- 0x3F
0x08 <- 0x00
```

**OV13B10 EEPROM read map:** two reads from `0xB0` (16-bit address, 8-bit data). The first is at address `0x0000` and the second at `0x1000`, each `0x1000` bytes, for 8 KB in total.

#### 4d. Caveats and blockers

* Mainline `ov13b10.c` in the 7.2.0 tree:
  * It rejects any external clock other than 19.2 MHz (`OV13B10_EXT_CLK`, the check in `ov13b10_probe`). Q706F runs the sensor at 24 MHz in both the DTBO and CamX. The fix is either a 24 MHz PLL/register set or trying 19.2 MHz on MCLK0, which is untested. `camcc-sm8250` offers both 19.2 and 24 MHz on the MCLK sources.
  * The driver has only an ACPI match table, no OF table and no `i2c_device_id` table, so a DT node cannot bind as is. `sm8250-xiaomi-elish` has an `"ovti,ov13b10"` node in the same tree, which cannot bind with this driver either.
* `sm8250.dtsi` has `cam_mclk0_default` (gpio94), `cam_mclk1_default` (gpio95), and `cam_mclk3_default` (gpio97). It has no MCLK2-only state for gpio96. Its `cam2_default` muxes gpio96 **and** gpio78 as a reset pin. On Q706F the front reset is PM8009 GPIO4, so `cam2_default` must not be used. Patch `0016` adds `cam_mclk2_default`.
* Do not copy `sm8250-xiaomi-elish` for the front camera. Its OV8856 is on `cci1_i2c1` @ `0x10`, MCLK3, TLMM reset 109, CSIPHY4, 2 lanes. Q706F is `cci1_i2c0` @ `0x36`, MCLK2, PM8009 GPIO4, CSIPHY2, 4 lanes. Only the CAMSS endpoint style (`clock-lanes = <7>`, `bus-type`) and the `vdda-phy`/`vdda-pll` supplies carry over.
* **VDIG mismatch with Android** (rail ranges from our DT, checked live):
  * Rear `vreg_l1f_1p1` is fixed at 1.104 V. The DTBO asks 1.2 V for `cam-sensor0` (OV13B10). L1F is `pmic5_nldo` (0.32–1.304 V in 8 mV steps), so 1.2 V is a valid setting. Not changed yet; the rear camera is not enabled.
  * Front `vreg_l3f_1p1` was 1.056–1.2 V and sat at 1.056 V, because sensor drivers do not set a voltage. OV8856 core is 1.14–1.26 V. The DTBO asks 1.25 V, which is not on the 8 mV grid. Patch `0016` pins L3F to 1.248 V.
* The existing `cam0_rst_pins` (`&pm8009_gpios`, `rst-pins`, gpio1) uses `function = "gpio"` and `drive-strength = <16>`. Neither is valid for SPMI PMIC GPIO (functions are `normal`, `func1`, …; strength is `qcom,drive-strength` 0–3), and dtbs_check flags the node name. Nothing references it today. Do not use it for the rear camera as is. `cam0_default` (TLMM gpio94 at 16 mA) is also unreferenced.
* There are no mainline drivers for GC5035, S5K5E9, S5K4H7, DW9763, or GT9768. `dw9768` and `ak7375` are different parts. That leaves the rear aux camera and the rear autofocus without a driver.
* The TXD OV13B10 module expects ID `0x0D43` at `0x300B`. The chip ID of a real OV13B10 is `0x560D42`, so a 16-bit read at `0x300B` should give `0x0D42`. The reason for `0x0D43` is not known. Nothing in `com.qti.sensor.txd_ov13b10.so` explains it.
* The OV13B10 EEPROM part number is unknown. Only the address `0x58`, the 16-bit addressing, and the 8 KB read range are known.
* `cam-sensor5` and `cam-sensor6` have unresolved pinctrl and reset phandles and no module mapped to them.
* SPMI PMIC GPIO numbering: the DT GPIO specifier is **1-based**. `pinctrl-spmi-gpio.c` subtracts `PMIC_GPIO_PHYSICAL_OFFSET` (1), so `<&pm8009_gpios 4 …>` is GPIO4 and pin names are `"gpio4"`. Only `gpio-line-names` and the Linux line offsets are 0-based: index 0 = GPIO1 (`CAM_REAR_RST`), index 3 = GPIO4 (`CAM_FRONT_RST`). Writing `3` for the front reset would select GPIO3, the rear aux reset.

#### 4e. Online check on the tablet (2026-10-12)

Read-only over SSH on the tablet, kernel `7.2.0 #7-postmarketos-qcom-sm8250`. The live tree was exported from `/sys/firmware/devicetree/base` and compared with the source DTB. Labels come from the source DTS, because the live tree has no `__symbols__`. No module was loaded, nothing was written, and there was no `i2cdetect` scan.

* **CCI / CAMSS:** `cci@ac4f000`, `cci@ac50000` (both with `i2c-bus@0/1`) and `camss@ac6a000` are `disabled`. There are no CCI I2C adapters. `/dev/video0`/`video1` are Venus only, and there is no `/dev/media*`. `camcc` (`clock-controller@ad00000`) is bound to `cam_cc-sm8250` (built in).
* **Modules:** `/lib/modules/7.2.0` has `i2c-qcom-cci.ko.zst`, `qcom-camss.ko.zst`, `ov8856.ko.zst` and `ov13b10.ko.zst`. None are loaded. There is no VCM driver for DW9763/GT9768.
* **Camera rails** (`&apps_rsc`; `regulators-0` is `qcom,pm8009-rpmh-regulators`, pmic-id `f`; `regulators-2` is `qcom,pm8150l-rpmh-regulators`, pmic-id `c`). All are registered, with `num_users` 0, as in the table below. `vreg_l4f` is commented out in our DTS. Supplies: `vdd-l5-l6` = `vreg_bob`, `vdd-l7` = `vreg_s4a_1p8`, `vdd-l2` = `vreg_s8c_1p35`.

| Android | Label (node) | Range in our DT | Live value | Use |
| --- | --- | --- | --- | --- |
| `pm8009_l1` | `vreg_l1f_1p1` (ldo1) | 1.104 V fixed | 1.104 V | VDIG rear main (Android 1.2 V) |
| `pm8009_l2` | `vreg_l2f_1p2` (ldo2) | 1.2 V fixed | 1.2 V | VDIG rear aux |
| `pm8009_l3` | `vreg_l3f_1p1` (ldo3) | 1.056–1.2 V | 1.056 V | VDIG front (Android 1.25 V); `0016` → 1.248 V |
| `pm8009_l5` | `vreg_l5f_2p8` (ldo5) | 2.8–3.0 V | 2.8 V | VANA rear main |
| `pm8009_l6` | `vreg_l6f_2p8` (ldo6) | 2.8 V fixed | 2.8 V | VANA rear aux + front |
| `pm8009_l7` | `vreg_l7f_1p8` (ldo7) | 1.8 V fixed | 1.8 V | VIO all slots |
| `pm8150a_l4` | `vreg_l4c_1p7` (ldo4, `// cam`) | 1.8–2.8 V | 1.8 V | VAF rear main |

* **PM8009 GPIO:** `pm8009_gpios` = `pmic@a/gpio@c000` (gpiochip3), 4 lines, `gpio-line-names = "CAM_REAR_RST", "NC", "CAM_REAR2_RST", "CAM_FRONT_RST"`. That matches the DTBO resets GPIO1/3/4. `pmic@b` is the second PM8009 SID.
* **Flash:** `pmic@5/led-controller@d300` (`qcom,pm8150l-flash-led`) is bound to `leds-qcom-flash`. `/sys/class/leds/white:flash` exists with `flash_brightness`, `flash_strobe` and `flash_timeout`; `led-0` is 200 mA torch, 1 A / 1.28 s flash. It is not linked to a sensor yet.
* **TLMM states present:** `cam_mclk0_default` (gpio94), `cam_mclk1_default` (gpio95), `cam_mclk3_default` (gpio97), `cam0_default` (gpio94, board DTS), `cam2_default`/`cam2_suspend` (gpio78 + gpio96), and `cci0`/`cci1` default/sleep.
* **Remoteprocs:** `slpi`, `cdsp` and `adsp` are `running` (`qcom/sm8250/q706f/*.mbn`). Early boot logs `-2` for all three; `q706f-adsp.service` then starts them.

#### 4f. Draft mainline DTS

The front part is exactly patch `0016` (compiled, dtbs_check clean, not booted). The rear part is still a draft. It is not compiled and is not in any patch.

```dts
/* Front, = patches/7.2.0/0016 */
&camss {
	vdda-phy-supply = <&vreg_l5a_0p88>;	/* as on elish/pipa; 0.88 V */
	vdda-pll-supply = <&vreg_l9a_1p2>;	/* 1.2 V */
	status = "okay";
	ports {
		port@2 {			/* port reg = CSIPHY index */
			csiphy2_ep: endpoint {
				clock-lanes = <7>;
				data-lanes = <0 1 2 3>;
				bus-type = <MEDIA_BUS_TYPE_CSI2_DPHY>;
				remote-endpoint = <&ov8856_front_ep>;
			};
		};
	};
};

&cci1 { status = "okay"; };		/* cci1_default/cci1_sleep come from sm8250.dtsi */

&cci1_i2c0 {
	camera_front: camera@36 {
		compatible = "ovti,ov8856";
		reg = <0x36>;
		clocks = <&camcc CAM_CC_MCLK2_CLK>;
		clock-names = "xvclk";
		assigned-clocks = <&camcc CAM_CC_MCLK2_CLK>;
		assigned-clock-rates = <19200000>;
		reset-gpios = <&pm8009_gpios 4 GPIO_ACTIVE_LOW>;	/* GPIO4, 1-based */
		pinctrl-0 = <&cam_mclk2_default>, <&cam_front_rst_default>;
		pinctrl-names = "default";
		dovdd-supply = <&vreg_l7f_1p8>;
		avdd-supply = <&vreg_l6f_2p8>;
		dvdd-supply = <&vreg_l3f_1p1>;		/* 0016 pins it to 1.248 V */
		orientation = <0>;
		rotation = <270>;			/* Android roll 270, unverified */
		port {
			ov8856_front_ep: endpoint {
				data-lanes = <1 2 3 4>;
				link-frequencies = /bits/ 64 <360000000 180000000>;	/* ov8856 needs both 4-lane menu values */
				remote-endpoint = <&csiphy2_ep>;
			};
		};
	};
};
/* + &tlmm cam_mclk2_default (gpio96, cam_mclk, 4 mA)
 * + &pm8009_gpios cam_front_rst_default (gpio4, function "normal") */

/* Rear main, draft. Blocked on ov13b10.c (no OF match, 19.2 MHz only). */
&vreg_l1f_1p1 {
	regulator-min-microvolt = <1200000>;	/* Android 1.2 V; valid nldo step */
	regulator-max-microvolt = <1200000>;
};

&cci0 { status = "okay"; };

&cci0_i2c0 {
	camera_rear: camera@36 {		/* OV13B10, CamX 0x6C */
		compatible = "ovti,ov13b10";	/* needs an OF table in ov13b10.c */
		reg = <0x36>;
		clocks = <&camcc CAM_CC_MCLK0_CLK>;
		assigned-clocks = <&camcc CAM_CC_MCLK0_CLK>;
		assigned-clock-rates = <24000000>;	/* Android; driver wants 19.2 MHz */
		reset-gpios = <&pm8009_gpios 1 GPIO_ACTIVE_LOW>;	/* CAM_REAR_RST */
		pinctrl-0 = <&cam_mclk0_default>, <&TODO_cam_rear_rst_default>; /* new state, not cam0_rst_pins */
		pinctrl-names = "default";
		dovdd-supply = <&vreg_l7f_1p8>;
		avdd-supply = <&vreg_l5f_2p8>;
		dvdd-supply = <&vreg_l1f_1p1>;
		orientation = <1>;
		/* TODO rotation: Android roll 90, yaw 180 */
		port {
			ov13b10_rear_ep: endpoint {
				data-lanes = <1 2 3 4>;
				link-frequencies = /bits/ 64 <560000000>;
				remote-endpoint = <&csiphy0_ep>;
			};
		};
	};
	/* VCM DW9763/GT9768 @0x0c (VAF vreg_l4c_1p7): no mainline driver.
	 * EEPROM @0x58, 16-bit addr, 8 KB: part unknown (at24 candidate). */
};
/* &camss port@0 { csiphy0_ep: clock-lanes <7>, data-lanes <0 1 2 3>, DPHY } */
/* Flash: &pm8150l_flash is already okay; link it with flash-leds once the rear binds. */
/* Rear aux GC5035@0x3f / S5K5E9@0x2d on cci0_i2c1 + CSIPHY1, 2 lanes: no mainline driver. */
```

#### 4g. Front camera test plan (patch `0016`, 2026-10-12)

Nothing below has been run on the tablet yet. The DTB from `0001`–`0015` + `0016` was built from the pristine `sm8250-7.2.0` tarball (checksum as in the APKBUILD). Without `0016`, the same build is byte-identical to the DTB appended in `out/boot-r4-usbplug.img`. That image carries the running `#7` kernel; its gzip kernel equals `~/tmp/linux-r4/…/arch/arm64/boot/Image.gz` and its ramdisk equals `out/initramfs.img`. So only the DT changes. `make CHECK_DTBS=y` gives the same warning set with and without `0016`, and none of the warnings are camera nodes.

Build a one-off `boot.img` with the new DTB (cmdline from `fedora/boot/cmdline`, the same as the running image):

```bash
fedora/boot/mkbootimg.sh \
  --vmlinuz ~/tmp/linux-r4/linux-sm8250-7.2.0/arch/arm64/boot/Image.gz \
  --dtb <0016 build>/arch/arm64/boot/dts/qcom/sm8250-lenovo-q706f.dtb \
  --initramfs out/initramfs.img \
  --out out/boot-r4-ov8856.img
```

Flash and roll back (Volume Down for fastboot; do **not** use `flash-fedora.sh`, which also writes `userdata`):

```bash
fedora/scripts/backup-partitions.sh          # optional: dump the current boot_b first
fastboot boot out/boot-r4-ov8856.img         # one-shot, if this ABL allows it (untested)
# or
fastboot flash boot_b out/boot-r4-ov8856.img && fastboot reboot
# rollback: the current #7 image
fastboot flash boot_b out/boot-r4-usbplug.img && fastboot reboot
```

On the tablet:

```bash
lsmod | grep -E 'i2c_qcom_cci|qcom_camss|ov8856'   # should autoload from the DT modalias
sudo modprobe -a i2c_qcom_cci qcom_camss ov8856    # only if they did not
sudo dmesg | grep -iE 'cci|camss|ov8856|vreg_l3f'
grep -l vreg_l3f /sys/class/regulator/*/name       # its microvolts should be 1248000
ls /dev/media* /dev/v4l-subdev*
media-ctl -d /dev/media0 -p                        # look for "ov8856 <bus>-0036"
```

* **Expected:** `vreg_l3f_1p1: Setting 1248000-1248000uV`, CCI1 and CAMSS probe, and no `ov8856` error. On DT, `ov8856` powers up and reads chip ID `0x885a` at `0x300a` during probe. A bound subdev means the sensor answered.
* `failed to find sensor: -6/-121`: no ACK. Check rails, MCLK and reset.
* `chip id mismatch`: a different part, for example the S5K4H7 alternate, which sits at `0x10`.
* `external clock rate … is unsupported`: MCLK2 is not 19.2 MHz.

Capture RAW10 (entity names as created by `camss`; check them and the sensor format in `media-ctl -p` first):

```bash
media-ctl -d /dev/media0 --reset
media-ctl -d /dev/media0 -l '"msm_csiphy2":1->"msm_csid0":0[1],"msm_csid0":1->"msm_vfe0_rdi0":0[1]'
media-ctl -d /dev/media0 -V '"ov8856 <bus>-0036":0[fmt:SBGGR10_1X10/3280x2464 field:none],"msm_csiphy2":0[fmt:SBGGR10_1X10/3280x2464 field:none],"msm_csid0":0[fmt:SBGGR10_1X10/3280x2464 field:none],"msm_vfe0_rdi0":0[fmt:SBGGR10_1X10/3280x2464 field:none]'
yavta -B capture-mplane -c10 -I -n 5 -f SBGGR10P -s 3280x2464 -F /dev/videoN   # N = msm_vfe0_video0
# without yavta (v4l-utils only):
v4l2-ctl -d /dev/videoN --set-fmt-video=width=3280,height=2464,pixelformat=pBAA --stream-mmap --stream-count=5 --stream-to=/tmp/ov8856.raw
```

#### 4i. Front camera verified (2026-10-13)

Image: `out/boot-r4-ov8856-v2.img` on `boot_b`, which is the `#7` kernel and initramfs with the DTB from `0001`–`0016`. The first DTB (360 MHz only) failed with `-22`, see 4h. With `<360000000 180000000>` the sensor probes: the chip ID (`0x885a`) is read, `21-0036` binds to `ov8856`, and `vreg_l3f_1p1` is set to 1.248 V. The rails are off when idle.

Pipeline: `ov8856 21-0036` (`/dev/v4l-subdev24`) → `msm_csiphy2` → `msm_csid0` → `msm_vfe0_rdi0` → `msm_vfe0_video0` (`/dev/video0`), `SBGGR10_1X10` 3264x2448. The CCI buses are `i2c-21` (cci1 master 0) and `i2c-22`. The capture ran as the normal user (in the `video` group), without sudo. Only runtime media links and formats were changed.

```bash
media-ctl -d /dev/media0 --reset
media-ctl -d /dev/media0 -l '"msm_csiphy2":1->"msm_csid0":0[1],"msm_csid0":1->"msm_vfe0_rdi0":0[1]'
media-ctl -d /dev/media0 -V '"ov8856 21-0036":0[fmt:SBGGR10_1X10/3264x2448 field:none]'
media-ctl -d /dev/media0 -V '"msm_csiphy2":0[fmt:SBGGR10_1X10/3264x2448 field:none],"msm_csid0":0[fmt:SBGGR10_1X10/3264x2448 field:none],"msm_vfe0_rdi0":0[fmt:SBGGR10_1X10/3264x2448 field:none]'
v4l2-ctl -d /dev/video0 --set-fmt-video=width=3264,height=2448,pixelformat=pBAA \
	--stream-mmap --stream-count=5 --stream-to=/tmp/ov8856.raw
```

Result: 5 frames, 49939200 bytes (5 × 9987840, stride 4080 = 3264 × 10 / 8). The kernel log had no new entries during the capture.

Image stats (10-bit, unpacked on the PC):

| | mean | min | max | std | zeros |
|---|---|---|---|---|---|
| frame 0 | 273.40 | 58 | 1023 | 218.14 | 0 % |
| frame 4 | 273.33 | | | | |

Per channel (frame 4): R 222.3, G 321.9, B 227.2. The frames were debayered to PNG (linear and auto-gain). The user looked at the image and confirmed it looks correct. The raw file was deleted from the tablet afterwards.

Not done yet: checking `rotation` against a known scene, exposure and gain control, and a processed (ISP) path. CAMSS RDI only delivers raw Bayer, so a viewer needs userspace debayering (for example libcamera's software ISP).

#### 4j. Rear camera verified (2026-10-13)

Patches: `0017` (binding `ovti,ov13b10.yaml`), `0018` (OF match table in `drivers/media/i2c/ov13b10.c`), `0019` (DTS: `cci0`, CAMSS `port@0` with 4 data lanes, `camera@36`, PM8009 GPIO1 reset, L1F at 1.2 V, AVDD L5F, DOVDD L7F, `link-frequencies = <560000000>`). All four camera patches (`0016`–`0019`) are now in `source` and `sha512sums` of `patches/APKBUILD.linux-postmarketos-qcom-sm8250-7.2.0`.

**MCLK.** MCLK0 runs at 19.2 MHz, not the Android 24 MHz. The driver accepts only `OV13B10_EXT_CLK` = 19.2 MHz and fails probe on any other rate. Its PLL setting (0x0303 = 0x04, /3; 0x0305 = 0xaf, ×175) gives 19.2 / 3 × 175 = 1120 Mbps per lane, the 560 MHz link frequency. At 24 MHz the same registers would give 1400 Mbps, so 24 MHz would need new PLL tables. camcc MCLK0 can source 19.2 MHz from the TCXO. With 19.2 MHz the chip ID check passed (no error; the `0x0D43` TXD module ID from 4b was not a problem).

**Test image.** `out/boot-r4-ov13b10.img` on `boot_b`: the `#7` `Image.gz` and `out/initramfs.img` with the DTB from `0001`–`0019`. Unpacked and compared with `out/boot-r4-ov8856-v2.img`: header, cmdline and ramdisk are identical, the kernel part is byte-identical to `#7`, only the appended DTB differs.

**Boot log** (relevant lines):

```
vreg_l1f_1p1: Setting 1200000-1200000uV
/soc@0/cci@ac4f000/i2c-bus@0/camera@36: Fixed dependency cycle(s) with /soc@0/camss@ac6a000
/soc@0/cci@ac50000/i2c-bus@0/camera@36: Fixed dependency cycle(s) with /soc@0/camss@ac6a000
fuse: module verification failed: signature and/or required key missing - tainting kernel
```

No ov13b10 or ov8856 errors. A DSI clock `WARN` (`dsi0_phy_pll_out_dsiclk already disabled`) is also in the previous boot and is not camera related.

**I2C bus numbers changed.** With `cci0` enabled, `i2c-21`/`i2c-22` are now `cci@ac4f000` (cci0) masters 0/1 and `i2c-23`/`i2c-24` are `cci@ac50000` (cci1). So the rear sensor is `21-0036` (`ov13b10`, `/dev/v4l-subdev25`) and the front sensor moved from `21-0036` to `23-0036` (`ov8856`, still `/dev/v4l-subdev24`). Both bind. The 4i commands need `"ov8856 23-0036"` from now on.

**Pipeline:** `ov13b10 21-0036` → `msm_csiphy0` → `msm_csid0` → `msm_vfe0_rdi0` → `/dev/video0`. Sensor default format `SGRBG10_1X10/4208x3120`.

```bash
F="SGRBG10_1X10/4208x3120 field:none"
media-ctl -d /dev/media0 --reset
media-ctl -d /dev/media0 -l '"msm_csiphy0":1->"msm_csid0":0[1],"msm_csid0":1->"msm_vfe0_rdi0":0[1]'
media-ctl -d /dev/media0 -V "\"ov13b10 21-0036\":0[fmt:$F]"
media-ctl -d /dev/media0 -V "\"msm_csiphy0\":0[fmt:$F],\"msm_csid0\":0[fmt:$F],\"msm_vfe0_rdi0\":0[fmt:$F]"
v4l2-ctl -d /dev/video0 --set-fmt-video=width=4208,height=3120,pixelformat=pgAA \
	--stream-mmap --stream-count=5 --stream-to=/tmp/ov13b10.raw
```

Result: 5 frames, 82118400 bytes (5 × 16423680, 5264 bytes per line). No kernel errors during the capture.

Image stats (10-bit, unpacked on the PC):

| | mean | min | max | std | zeros | saturated |
|---|---|---|---|---|---|---|
| frame 0 | 121.70 | 37 | 802 | 101.33 | 0 % | 0 % |
| frame 4 | 121.97 | 41 | 799 | 101.76 | 0 % | 0 % |

Per channel (frame 4, GRBG): R 108.8, Gr 135.7, Gb 136.0, B 107.3. Gr ≈ Gb, so the GRBG order is right. The user looked at the debayered image: the orientation is correct (`rotation = <90>` is right) and the image is otherwise fine, but it looks greyish (washed out). That is expected for raw data with the driver default exposure and gain, no black level subtraction, no white balance and no colour correction.

**Module deployment.** `ov13b10` is a module (`CONFIG_VIDEO_OV13B10=m`) and is not in the initramfs, so the DTB alone is not enough; the module needs `0018`. For this test it was replaced by hand on the tablet (done by the user, with root):

```bash
cd /lib/modules/7.2.0/kernel/drivers/media/i2c
cp ov13b10.ko.zst ov13b10.ko.zst.bak
install -m644 /path/to/ov13b10.ko.zst ov13b10.ko.zst   # zstd -19 of the module built with 0016-0019
depmod -a 7.2.0
```

The loaded module has `alias: of:N*T*Covti,ov13b10` and `vermagic: 7.2.0 SMP preempt mod_unload aarch64`. Rollback: flash `out/boot-r4-ov8856-v2.img` to `boot_b` and restore `ov13b10.ko.zst.bak`.

**Taint.** The module was built in a separate tree with its own generated signing key (the `#7` key was not used). `CONFIG_MODULE_SIG=y` without `MODULE_SIG_FORCE`, so it loads, but the kernel logs `module verification failed` and sets the `E` taint (`/proc/sys/kernel/tainted` = 8704 = `E` + `W`). The `W` is the DSI clock warning above. This goes away when the next kernel package is built with `0016`–`0019`: `package()` runs `modules_install`, so `ov13b10.ko` and `ov8856.ko` ship in the package, signed with that build's key.

#### 4k. Kernel `#8`, libcamera package and CMA (2026-10-13)

**Kernel `#8`.** Built from the pristine `sm8250-7.2.0` tarball with `0001`–`0019` and `kernel-config/config-postmarketos-qcom-sm8250-7.2.0.aarch64`. The toolchain and `make` invocation are the same as `#7` (`KBUILD_BUILD_VERSION=8-postmarketos-qcom-sm8250`, `modules_install INSTALL_MOD_STRIP=1`). The release is still `7.2.0`, but the build generates a new module signing key. So `Image.gz`, the initramfs modules and `/usr/lib/modules/7.2.0` have to be replaced together. The 271 modules in the dracut initramfs were swapped for the `#8` builds and `depmod` was rerun. Nothing else in the initramfs changed. `ov8856` and `ov13b10` ship in the module set with their OF aliases. After boot the taint is `512` (`W`, the known DSI clock warning). `E` is gone.

**libcamera `0.7.1-2.q706f1`.** This is the Fedora `libcamera-0.7.1-2.fc44` SRPM plus `patches/libcamera/0001-…` as `Patch100`, with `Release: 2.q706f1%{?dist}`. The spec change is in `patches/libcamera/libcamera-0.7.1-2-q706f.spec.diff`. It must be based on `-2`: the `-1` spec re-signs `%{_libdir}/libcamera/ipa_*.so` after strip, which misses `ipa/`, so the shipped IPA signatures are invalid and the IPA runs isolated. `-2` fixes that path (rhbz#2547048). Against the official `-2` RPMs, the file lists, Requires/Provides, SONAME and NEEDED are unchanged, and all five IPA signatures verify against the key embedded in the new `libcamera.so`. Installed with `dnf install ./…rpm` and pinned with `dnf versionlock add libcamera libcamera-ipa libcamera-tools libcamera-qcam`.

**CMA.** With the system libcamera the soft ISP failed with `DmaBufAllocator dma-heap allocation failure`, and dmesg showed `cma: reserved: alloc failed` (8008 and 12870 pages). The DT has no `linux,cma` or reusable `shared-dma-pool` node. The only CMA area is the global one from `CONFIG_CMA_SIZE_MBYTES=32` (`cma: Reserved 32 MiB at 0xfe000000`), named `reserved`. `cma_heap` exports it twice, as `/dev/dma_heap/default_cma_region` and `/dev/dma_heap/reserved`. libcamera 0.7.1 tries `linux,cma`, then `reserved`, `system` and `udmabuf`, so it picks `reserved` once udev (`70-libcamera.rules`) gives the `video` group access. One rear output buffer is about 50 MB (4208×3120 XRGB). The cmdline comes from the `boot.img` header (`CONFIG_CMDLINE=""`; ABL only appends `androidboot.*`), so `cma=256M` was added to `fedora/boot/cmdline`. The global area moves below 4 GiB (`0xc0000000`–`0xffffffff` is 1 GiB of contiguous RAM), and both heap names stay the same. After boot `CmaTotal` is `262144 kB`. With the system `cam`, the front and rear cameras each captured 30 frames at about 30 fps with no errors. Two cameras at once, or PipeWire holding buffers, may need `384M` or `512M`.

#### 4h. Next steps (camera)

1. **Front OV8856:** done, see 4i. `0016` is now in the APKBUILD (with `0017`–`0019`). Still to do: check `rotation` on a real frame, and decide whether 360 MHz is good enough against the Android ≈368.8 MHz. The first flash (2026-10-13) listed only 360 MHz: `ov8856 21-0036: no link frequency 180000000 supported`, then `probe with driver ov8856 failed with error -22`, before power-up, so no chip ID was read. `0016` now lists `<360000000 180000000>`.
2. **Rear OV13B10:** verified on 2026-10-13, see 4j. Done: kernel `#8` ships the signed module and libcamera works through the soft ISP, see 4k. Still to do: a tuning file and colour / white balance check.
   * Written and built on 2026-10-13: `0017` (binding `ovti,ov13b10.yaml`), `0018` (OF match table in `ov13b10.c`), `0019` (DTS: `cci0`, CAMSS `port@0` 4 lanes, `camera@36`, reset on PM8009 GPIO1 with `function = "normal"`, L1F at 1.2 V, AVDD L5F, DOVDD L7F, `link-frequencies = <560000000>`; no VCM, no EEPROM).
   * MCLK0 runs at 19.2 MHz, not the Android 24 MHz. The driver checks for exactly 19.2 MHz (`OV13B10_EXT_CLK`), and its PLL tables (0x0303 = 0x04, 0x0305 = 0xaf) give 19.2 / 3 × 175 = 1120 Mbps per lane = 560 MHz link. At 24 MHz the same registers give 1400 Mbps, so 24 MHz would need new PLL tables. camcc MCLK0 can do 19.2 MHz.
   * Risks: the TXD module ID `0x0D43` vs the driver chip ID `0x560d42`; `rotation = <90>` is from Android and unchecked.
   * `ov13b10` is a module that is not in the initramfs. Deploy the new `ov13b10.ko.zst` to `/lib/modules/7.2.0/kernel/drivers/media/i2c/` in the rootfs and run `depmod`, and boot the new DTB with the `#7` `Image.gz`.
3. **Rear autofocus:** write or port a DW9763 / GT9768 VCM driver, using the init writes in 4c as a starting point. VAF is `vreg_l4c_1p7`.
4. **Identify the OV13B10 EEPROM part** at `0x58` so it can bind with `at24`, and work out why the TXD module ID is `0x0D43`.
5. **Rear aux GC5035 / S5K5E9 and front-alternate S5K4H7:** these need new sensor drivers. Lower priority.
6. **Flash:** the LED already works (`white:flash`). Link `&pm8150l_flash` `led-0` to the rear sensor with `flash-leds` once the rear sensor binds.
