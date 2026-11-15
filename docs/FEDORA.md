# Kernel 7.2.0 and Fedora 44 on the Lenovo Q706F

This tree boots **Fedora 44 Workstation** on the Lenovo Tab P12 Pro / Xiaoxin Pad Pro 12.6 (Q706F, SM8250) with the same **7.2.0** mainline SM8250 kernel used for postmarketOS. The bootloader is Android ABL: the kernel and initramfs live in `boot.img` on slot B, and the root filesystem is the `userdata` partition. There is no UEFI.

The image is a development build. The default account is `asuka` / `asuka`, with passwordless sudo. Change that before treating the tablet as a normal computer. Put an SSH public key at `fedora/overlay/home/asuka/.ssh/authorized_keys` before building if you want key login; that path is gitignored.

USB gadget networking comes up as `usb0` at `172.16.42.1/16`. The host should use `172.16.42.2/16`.

## Kernel 7.2.0

Package: `linux-postmarketos-qcom-sm8250` **7.2.0-r6**, rebased onto the postmarketOS SM8250 tree (`sm8250-7.2.0`).

| File | Role |
| --- | --- |
| `patches/APKBUILD.linux-postmarketos-qcom-sm8250-7.2.0` | APKBUILD for this rebase |
| `patches/7.2.0/*.patch` | Series applied on top of the 7.2.0 tag |
| `kernel-config/config-postmarketos-qcom-sm8250-7.2.0.aarch64` | Full merged config |
| `kernel-config/q706f-extra.config` | Fragment also used by the 6.17 package |

Patches `0002` (DP Configure signalling) and `0003` (QMP combo Type-C mode switch) are already in the 7.2.0 tree and are not repeated. The series that is applied:

| Patch | Why |
| --- | --- |
| `0001` | Volume-up is a wakeup source |
| `0004` | 4-lane DisplayPort on the Type-C port |
| `0005` | Panel brightness writes no longer glitch the DSC scanout |
| `0006` | Do not reclock the DSI link on every runtime DCS write |
| `0007` | SPI13 chip-select GPIO so the Goodix touchscreen probes |
| `0008` | Disable unused PCIe2 and the PM8009 PON key |
| `0009` | Delay folio touchpad probe until the Elan part is ready |
| `0010` | Override the Elan `04F3:31F3` HID descriptor from the Android DTBO |
| `0011` | Elan `31F3` `BAD_INPUT_SIZE` |
| `0012` | Enable the PM8150B charger and prefer USB-C sink |
| `0013` | Drop the USB gadget pullup when Type-C reports no role, so `usb0` goes down after unplug |
| `0014` | Apply that pullup while the USB controller is already awake, and drive the VBUS-valid bit from the new role |
| `0015` | Do not report the battery full while current is negative |

Build against a pmbootstrap work directory (the parent of this repo is used when it already contains `cache_git/pmaports`):

```bash
PMOS_WORK=/path/to/pmOS fedora/scripts/apply-kernel-7.2-pmaports.sh
```

Prove that kernel on a running postmarketOS install before replacing the root filesystem:

```bash
fedora/scripts/flash-kernel-pmos.sh
```

`fedora/kernel/prepare.sh` copies a local `sm8250-7.2.0` tree, applies `patches/7.2.0/`, and installs the merged config. Set `KERNEL_SRC` if the tree is not next to this repo.

## Fedora rootfs and boot image

| Path | Role |
| --- | --- |
| `fedora/q706f.ks` | Package set. Not fed to Anaconda. |
| `fedora/rootfs/build-rootfs.sh` | `dnf --installroot` for aarch64 Fedora 44 |
| `fedora/overlay/` | Device units, UCM, USB gadget, Plymouth, logind |
| `fedora/boot/mkinitramfs.sh` | dracut initramfs. Run it as root inside an aarch64 Fedora tree |
| `fedora/boot/mkbootimg.sh` | ABL `boot.img` (gzip kernel, appended DTB, dracut ramdisk) |
| `fedora/boot/cmdline` | Kernel command line baked into `boot.img` |
| `fedora/scripts/flash-fedora.sh` | `fastboot flash boot_b` and `userdata` |

`dnf` is configured with `excludepkgs=kernel*`. Do not install a Fedora `kernel*` package; it will not boot this board.

Build, after the 7.2.0 kernel artifacts exist under `out/`:

```bash
# rootfs (aarch64 container; do not tar the rootfs from inside qemu)
podman run --rm -it --arch arm64 --privileged \
  -v "$PWD:/work:Z" -w /work quay.io/fedora/fedora:44 \
  bash fedora/rootfs/build-rootfs.sh
sudo tar -C out/rootfs --one-file-system -cf - . | pigz -1 > out/q706f-fedora-44-rootfs.tar.gz

# initramfs must be packed as root. A user-owned cpio makes setuid mount fail
# and drops the boot into the emergency shell.
podman run --rm --arch arm64 --privileged \
  -v "$PWD:/work" -w /work quay.io/fedora/fedora:44 \
  bash fedora/boot/mkinitramfs.sh
fedora/boot/mkbootimg.sh \
  --vmlinuz out/vmlinuz-7.2.0 \
  --dtb out/sm8250-lenovo-q706f.dtb \
  --initramfs out/initramfs.img

sudo USERDATA_GIB=12 fedora/rootfs/mk-userdata-image.sh
```

Flash only after 7.2.0 has already booted on this hardware. `flash-fedora.sh` replaces `boot_b` and `userdata`. Set `BACKUP` to a saved pmOS `boot.img` if you want the script to refuse to run without one. Enter fastboot with Volume Down; a software reboot does not stay in the bootloader on this device. Large `userdata` images need `fastboot -S 256M`.

Plymouth uses the Fedora **spinner** theme (`quiet splash` on the command line). The default BGRT theme looks for an ACPI firmware logo this tablet does not have.

## What had to be fixed for GNOME to come up

- **GDM.** The rootfs is built with weak dependencies off, so `dbus-daemon` and `systemd-pam` (`pam_systemd`) were missing. Both are explicit packages now. Without them the session bus and the user systemd instance never start, and the display stays black after the greeter text.
- **Sound card.** ADSP, SLPI, and CDSP firmware is requested before the root filesystem is mounted, so those remoteprocs fail with `-ENOENT` and the sound card never probes. `q706f-adsp.service` starts `adsp`, then `cdsp`, then `slpi` after local filesystems. The HiFi UCM mic device is defined only when `ADC1_MIXER Switch` exists. If that device is always present and the codec controls are missing, PipeWire drops the whole HiFi profile and GNOME shows Dummy Output.
- **Speaker level.** PipeWire opened the card as `S24_LE`. The sm8250 TDM backend is fixed to `S16_LE`, and that conversion made the speakers quiet; pushing the slider past 100% then distorted. WirePlumber forces `S16LE` on the speaker sink, which matches postmarketOS PulseAudio. Amp firmware, UCM, and the Analog/Digital PCM defaults are the same as postmarketOS.
- **Bluetooth.** The QCA6390 NVM address is the chip default `00:00:00:00:5A:AD`, so the kernel leaves `hci0` unconfigured until userspace sets one. On this tablet `persist` has no `bluetooth/` directory. `/etc/q706f-bt-addr` holds the Wi-Fi MAC plus one (`XX:XX:XX:XX:XX:XX`); without that file `q706f-bt-addr.sh` derives the same address from the permanent `wlp1s0` MAC. On kernel `#5`, `bluetoothctl` shows that public controller, and `rfcomm` and `bnep` are loaded.
- **Clock.** The PMIC RTC cannot be set (`RTC_SET_TIME` returns `ENODEV`) and reads back as 1970. `q706f-htpdate.service` sets the clock from the HTTP `Date` header of `1.1.1.1` once the network is up. `dnf` will reject RPM signatures until that happens.
- **Home directory mode.** sshd `StrictModes` ignores `authorized_keys` when the home directory is group-writable. The image build forces mode `755`.
- **USB-C power role.** The connector is dual-role. `try-power-role = "sink"` (patch `0012`) asks the port to try sink first. `q706f-typec-sink.service` still prefers sink at boot when a partner is already attached as source and no USB peripheral has enumerated. Forcing sink on every source attach makes a USB stick disconnect in a loop.
- **Boot animation and logind.** Plymouth is the spinner theme. logind ignores the power key so an early firmware event does not power the machine off during first boot. Closing the folio keyboard is the hall-effect lid switch and suspends; opening it wakes, because that GPIO is already a wakeup source.

## Still missing

- **Camera.** Front OV8856 and rear OV13B10 work with kernel `#8` (patches `0016`–`0019`) and the local libcamera package `0.7.1-2.q706f1` (simple pipeline + soft ISP, see `patches/libcamera/`). The cmdline needs `cma=256M`: the default 32 MiB CMA cannot hold the soft ISP buffers. Rear aux, the front-alternate sensor, autofocus and EEPROM have no driver. Details are in `FIRMWARE_ANALYSIS_AND_TODO.md`, Step 4.
- **Charger current.** On kernel `#5`, `pm8150b-charger` is online and reports USB Charging. With the battery already full it was drawing about 100 mA, and `current_max` was 500 mA. The downstream SMB1390 charge pump (9.5 A) is still not driven by this kernel.
- **Factory Bluetooth address** is not on the tablet `persist` partition (no `bluetooth/` directory). The working address is Wi-Fi MAC + 1, stored in `/etc/q706f-bt-addr`.
