# Q706F Fedora recovery notes

## Storage and boot slots

This Fedora installation uses an Android-format kernel and initramfs in a `boot` partition and a shared ext4 root filesystem in `userdata`. Its kernel command line selects the root filesystem by UUID, independently of the boot slot.

An Android Recovery message saying that Android cannot load does not establish that the Fedora filesystem is corrupt. Check which slot the bootloader selected before reinstalling anything.

Do not factory-reset, format, erase, or flash `userdata` when preserving the existing installation. The Fedora installation script replaces `userdata`; it is not a recovery script.

## Verified maintenance on 2026-11-15

After the bootloader returned to slot A, selecting B restored Fedora. Over Wi-Fi SSH, both 96 MiB boot partitions were backed up to the maintenance computer, then the working `boot_b` was copied to `boot_a`. A byte-for-byte comparison and SHA-256 verification passed:

```text
111ab20a59de8e74aed4989f867b49f1e56d6754bca72ffafbaef47a2621d9fa
```

The local backups are in `out/backup/slot-sync-20261115/` and are not distributed by this repository. No userdata or boot-slot metadata was changed. Slot A has not yet been boot-tested; matching boot images alone does not verify the remaining slot-specific firmware or bootloader state. The cause of automatic fallback remains unconfirmed.

For future kernel updates, deliberately maintain both boot images or keep one known-good recovery image. This copy operation does not automatically synchronize later updates.

## USB network diagnosis

During the same session, the gadget service was running, `usb0` had `172.16.42.1/16`, and the USB controller was bound in device mode. The interface had no carrier and the controller reported `not attached`, including after a gadget-service restart. USB recovery remains unverified; check a direct data-capable cable connection and USB enumeration before changing network configuration. Wi-Fi SSH was available during maintenance.
