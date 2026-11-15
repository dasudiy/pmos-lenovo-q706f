#!/bin/bash
# Dump boot_a/boot_b/persist/dtbo and the pmOS /boot partition to the PC.
# Raw UFS nodes need doas on the tablet (password prompt).
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
DEVICE="${DEVICE:-asuka@172.16.42.1}"
DEST="${DEST:-$REPO/out/backup}"
mkdir -p "$DEST"

echo "==> copying world-readable /boot files"
mkdir -p "$DEST/pmos-boot-fs"
for f in boot.img vmlinuz initramfs sm8250-lenovo-q706f.dtb config System.map; do
	scp "$DEVICE:/boot/$f" "$DEST/pmos-boot-fs/$f" 2>/dev/null || true
done

echo "==> dumping raw partitions (doas)"
ssh -tt "$DEVICE" 'set -eu
DEST=/tmp/q706f-part-dump
mkdir -p "$DEST"
for p in boot_a boot_b persist dtbo_a dtbo_b; do
  echo dump $p
  doas dd if=/dev/disk/by-partlabel/$p of="$DEST/$p.img" bs=4M status=progress
done
doas dd if=/dev/disk/by-partlabel/userdata of="$DEST/userdata-gpt-1MiB.bin" bs=1M count=1
doas dd if=/dev/mapper/sda18p1 of="$DEST/pmos-boot-sda18p1.img" bs=4M status=progress
ls -lh "$DEST"
'
scp -r "$DEVICE:/tmp/q706f-part-dump/"* "$DEST/"
echo "==> $DEST"
ls -lh "$DEST"
