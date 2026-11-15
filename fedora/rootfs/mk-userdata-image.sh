#!/bin/bash
# Sparse ext4 image for fastboot flash userdata (replaces pmOS root).
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
tarball="${1:-$repo/out/q706f-fedora-44-rootfs.tar.gz}"
out="${2:-$repo/out/userdata.img}"
size_gib="${USERDATA_GIB:-12}"
uuid="8a7c1e10-706f-4444-9a00-000000000001"

[ -f "$tarball" ] || { echo "missing $tarball" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
img="$tmp/userdata.raw"
truncate -s "${size_gib}G" "$img"
mkfs.ext4 -F -L fedora -U "$uuid" -m 1 "$img"
mnt="$tmp/mnt"
mkdir -p "$mnt"
mount -o loop "$img" "$mnt"
tar -C "$mnt" -xzf "$tarball"
sync
umount "$mnt"

if command -v img2simg >/dev/null; then
	img2simg "$img" "$out"
elif command -v android-sparse-image >/dev/null; then
	android-sparse-image "$img" "$out"
else
	cp "$img" "$out"
	echo ">>> img2simg missing; wrote raw ext4 (fastboot -S 4G flash userdata)" >&2
fi
echo ">>> $out"
