#!/bin/bash
# Build a dracut initramfs from the Fedora rootfs (needs aarch64 chroot/container).
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
rootfs="${ROOTFS_DIR:-$repo/out/rootfs}"
kver="${KVER:-}"
out="${1:-$repo/out/initramfs.img}"

if [ -z "$kver" ]; then
	kver="$(ls -1 "$rootfs/usr/lib/modules" | head -1)"
fi
[ -d "$rootfs/usr/lib/modules/$kver" ] || {
	echo "no modules in $rootfs/usr/lib/modules" >&2
	exit 1
}

install -Dm644 "$repo/fedora/boot/dracut.conf.d/q706f.conf" \
	"$rootfs/etc/dracut.conf.d/q706f.conf"

for mp in proc sys dev; do
	mkdir -p "$rootfs/$mp"
	if ! mountpoint -q "$rootfs/$mp"; then
		case "$mp" in
			proc) mount -t proc proc "$rootfs/proc" ;;
			sys) mount -t sysfs sys "$rootfs/sys" ;;
			dev) mount --bind /dev "$rootfs/dev" ;;
		esac
	fi
done
trap 'umount "$rootfs/proc" "$rootfs/sys" "$rootfs/dev" 2>/dev/null || true' EXIT

chroot "$rootfs" dracut -f --kver "$kver" /boot/initramfs-"$kver".img
cp "$rootfs/boot/initramfs-$kver.img" "$out"
echo "==> $out"
