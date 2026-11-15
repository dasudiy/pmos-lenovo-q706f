#!/bin/bash
# Overlay sm8250-7.2.0 + Q706F patches onto the v25.12 pmaports kernel package
# and build the APK used to prove 7.2.0 on the current pmOS rootfs.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
if [ -z "${PMOS_WORK:-}" ] && [ -d "$(dirname "$REPO")/cache_git/pmaports" ]; then
	PMOS_WORK="$(dirname "$REPO")"
fi
PMOS_WORK="${PMOS_WORK:?set PMOS_WORK to your pmbootstrap work directory}"
PMOS_CFG="${PMOS_CFG:-$HOME/.config/pmbootstrap_v3.cfg}"
PMAP="${PMAP:-$PMOS_WORK/cache_git/pmaports}"
PKG=linux-postmarketos-qcom-sm8250
DST="$PMAP/device/community/$PKG"
SRC_TAR="$PMOS_WORK/cache_distfiles/${PKG}-sm8250-7.2.0.tar.gz"
LOCAL_TAR="${LOCAL_TAR:-$PMOS_WORK/cache_git/linux-sm8250-7.2.0.tar.gz}"

mkdir -p "$DST"
if [ -f "$LOCAL_TAR" ] && [ ! -f "$SRC_TAR" ]; then
	echo "==> seed distfiles from $LOCAL_TAR"
	if [ -w "$(dirname "$SRC_TAR")" ]; then
		cp -a "$LOCAL_TAR" "$SRC_TAR"
	else
		sudo cp -a "$LOCAL_TAR" "$SRC_TAR"
		sudo chown "$(id -u):$(id -g)" "$SRC_TAR" || true
	fi
fi

echo "==> sync 7.2.0 APKBUILD, config, patches into pmaports"
cp "$REPO/patches/APKBUILD.linux-postmarketos-qcom-sm8250-7.2.0" "$DST/APKBUILD"
cp "$REPO/kernel-config/config-postmarketos-qcom-sm8250-7.2.0.aarch64" \
	"$DST/config-postmarketos-qcom-sm8250.aarch64"
rm -f "$DST"/000*.patch
cp "$REPO"/patches/7.2.0/*.patch "$DST/"

echo "==> checksum + build (needs sudo for pmbootstrap chroot)"
cd "$PMOS_WORK"
pmbootstrap -c "$PMOS_CFG" checksum "$PKG"
pmbootstrap -c "$PMOS_CFG" build --arch aarch64 "$PKG"
ls -lh "$PMOS_WORK/packages/v25.12/aarch64/${PKG}-7.2.0-r"*.apk
