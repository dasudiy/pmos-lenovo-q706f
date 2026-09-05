#!/bin/bash
set -euo pipefail

DEVICE="${DEVICE:-asuka@172.16.42.1}"
PMOS_WORK="${PMOS_WORK:-/home/asuka/pmOS}"
PMOS_CFG="${PMOS_CFG:-/home/asuka/.config/pmbootstrap_v3.cfg}"
REPO="${REPO:-/home/asuka/pmOS/q706f-pmos-fixes}"
PMAP="${PMAP:-$PMOS_WORK/cache_git/pmaports}"
PKG=linux-postmarketos-qcom-sm8250
PKGVER=6.17.0
APKBUILD="$REPO/patches/APKBUILD.linux-postmarketos-qcom-sm8250"
PKGREL="$(grep '^pkgrel=' "$APKBUILD" | cut -d= -f2)"
APK_NAME="${PKG}-${PKGVER}-r${PKGREL}.apk"
APK_DIR="$PMOS_WORK/packages/v25.12/aarch64"
DST="$PMAP/device/community/$PKG"

echo "==> Sync kernel patches + APKBUILD into pmaports (pkgrel=$PKGREL)"
cp "$APKBUILD" "$DST/APKBUILD"
cp "$REPO"/patches/000*.patch "$DST/"

echo "==> Build kernel APK (needs sudo for pmbootstrap chroot)"
cd "$PMOS_WORK"
pmbootstrap -c "$PMOS_CFG" checksum "$PKG"
pmbootstrap -c "$PMOS_CFG" build --arch aarch64 "$PKG"

APK="$APK_DIR/$APK_NAME"
if [[ ! -f "$APK" ]]; then
  APK="$(ls -t "$APK_DIR"/${PKG}-${PKGVER}-r*.apk | head -1)"
fi
echo "==> Using APK: $APK"

echo "==> Copy APK to device"
scp "$APK" "$DEVICE:/tmp/$APK_NAME"

echo "==> Install on device (doas password may be required on tablet)"
ssh -t "$DEVICE" "doas apk add --allow-untrusted /tmp/$APK_NAME && rm -f /tmp/$APK_NAME && uname -r"

echo "==> Done. Reboot the tablet when ready: ssh -t $DEVICE doas reboot"
