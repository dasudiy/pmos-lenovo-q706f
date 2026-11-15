#!/bin/bash
# Prepare the sm8250-7.2.0 tree with Q706F patches + merged kconfig.
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
if [ -z "${KERNEL_SRC:-}" ] && [ -d "$(dirname "$repo")/cache_git/linux-sm8250-7.2.0" ]; then
	KERNEL_SRC="$(dirname "$repo")/cache_git/linux-sm8250-7.2.0"
fi
src="${KERNEL_SRC:?set KERNEL_SRC to a sm8250 7.2.0 tree}"
out="${PREPARED_DIR:-$repo/out/linux-prepared}"
cfg="$repo/kernel-config/config-postmarketos-qcom-sm8250-7.2.0.aarch64"
patches="$repo/patches/7.2.0"

[ -d "$src/.git" ] || [ -f "$src/Makefile" ] || {
	echo "kernel source missing: $src" >&2
	exit 1
}
[ -f "$cfg" ] || { echo "missing $cfg" >&2; exit 1; }

rm -rf "$out"
mkdir -p "$(dirname "$out")"
cp -a "$src" "$out"
rm -rf "$out/.git"
cp "$cfg" "$out/.config"

shopt -s nullglob
for p in "$patches"/*.patch; do
	echo "==> patch $(basename "$p")"
	patch -d "$out" -p1 --forward --batch < "$p"
done

mkdir -p "$repo/out"
tar -C "$(dirname "$out")" -czf "$repo/out/linux-prepared.tar.gz" "$(basename "$out")"
echo "==> $repo/out/linux-prepared.tar.gz"
