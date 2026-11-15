#!/bin/bash
# Android boot.img for Q706F ABL: gzip kernel + appended DTB + dracut ramdisk.
# Offsets from device-lenovo-q706f/deviceinfo.
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
vmlinuz=""
dtb=""
initramfs=""
cmdline_file="$repo/fedora/boot/cmdline"
out="$repo/out/boot.img"

while [ $# -gt 0 ]; do
	case "$1" in
		--vmlinuz) vmlinuz="$2"; shift 2 ;;
		--dtb) dtb="$2"; shift 2 ;;
		--initramfs) initramfs="$2"; shift 2 ;;
		--cmdline) cmdline_file="$2"; shift 2 ;;
		--out) out="$2"; shift 2 ;;
		*) echo "unknown arg: $1" >&2; exit 1 ;;
	esac
done

[ -n "$vmlinuz" ] && [ -n "$dtb" ] && [ -n "$initramfs" ] || {
	echo "usage: mkbootimg.sh --vmlinuz F --dtb F --initramfs F [--cmdline F] [--out F]" >&2
	exit 1
}

mkbootimg_bin="$(command -v mkbootimg || true)"
if [ -z "$mkbootimg_bin" ]; then
	echo "mkbootimg not found (android-tools)" >&2
	exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

kernel="$vmlinuz"
case "$(file -b "$vmlinuz")" in
	*PE32*|*EFI*)
		echo ">>> stripping zboot EFI wrapper" >&2
		python3 - "$vmlinuz" "$tmp/Image.gz" << 'PY'
import sys
data = open(sys.argv[1], "rb").read()
idx = data.find(b"\x1f\x8b")
if idx < 0:
    raise SystemExit("no gzip payload in vmlinuz")
open(sys.argv[2], "wb").write(data[idx:])
PY
		kernel="$tmp/Image.gz"
		;;
esac

cat "$kernel" "$dtb" > "$tmp/Image.gz-dtb"
cmdline=$(tr '\n' ' ' < "$cmdline_file" | sed 's/[[:space:]]*$//')

"$mkbootimg_bin" \
	--kernel "$tmp/Image.gz-dtb" \
	--ramdisk "$initramfs" \
	--cmdline "$cmdline" \
	--base 0x00000000 \
	--kernel_offset 0x00008000 \
	--ramdisk_offset 0x01000000 \
	--second_offset 0x00f00000 \
	--tags_offset 0x00000100 \
	--pagesize 4096 \
	--header_version 0 \
	-o "$out"

echo ">>> $out ($(stat -c %s "$out") bytes)"
