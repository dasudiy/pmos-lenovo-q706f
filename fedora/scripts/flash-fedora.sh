#!/bin/bash
# Replace pmOS userdata with Fedora. Only run after 7.2.0 has already booted
# this hardware on the current pmOS install.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
DEVICE="${DEVICE:-asuka@172.16.42.1}"
BOOT_IMG="${BOOT_IMG:-$REPO/out/boot.img}"
USERDATA_IMG="${USERDATA_IMG:-$REPO/out/userdata.img}"

[ -f "$BOOT_IMG" ] || { echo "missing $BOOT_IMG" >&2; exit 1; }
[ -f "$USERDATA_IMG" ] || { echo "missing $USERDATA_IMG" >&2; exit 1; }
if [ -n "${BACKUP:-}" ] && [ ! -f "$BACKUP" ]; then
	echo "missing boot backup $BACKUP — abort" >&2
	exit 1
fi
if [ -z "${BACKUP:-}" ]; then
	echo "warning: BACKUP is unset; flashing will replace boot_b and userdata" >&2
fi

if ! command -v fastboot >/dev/null; then
	echo "fastboot not installed" >&2
	exit 1
fi

echo "==> rebooting tablet to bootloader (doas password)"
ssh -tt "$DEVICE" "doas reboot bootloader" || true

echo "==> waiting for fastboot"
for i in $(seq 1 60); do
	if fastboot devices | grep -q .; then
		break
	fi
	sleep 2
done
fastboot devices | grep -q . || { echo "no fastboot device" >&2; exit 1; }

echo "==> flash boot_b + userdata (DESTROYS pmOS root)"
fastboot flash boot_b "$BOOT_IMG"
fastboot flash userdata "$USERDATA_IMG"
fastboot set_active b
fastboot reboot
echo "==> waiting for USB gadget 172.16.42.1"
for i in $(seq 1 90); do
	if ping -c 1 -W 1 172.16.42.1 >/dev/null 2>&1; then
		echo "==> ssh asuka@172.16.42.1"
		exit 0
	fi
	sleep 2
done
echo "USB gadget did not come up; collect dmesg over ssh when it does" >&2
exit 1
