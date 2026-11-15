#!/bin/bash
# Install the 7.2.0 kernel APK on the running pmOS rootfs (does not wipe userdata).
set -euo pipefail

DEVICE="${DEVICE:-asuka@172.16.42.1}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
if [ -z "${PMOS_WORK:-}" ] && [ -d "$(dirname "$REPO")/packages/v25.12/aarch64" ]; then
	PMOS_WORK="$(dirname "$REPO")"
fi
APK_DIR="${APK_DIR:-${PMOS_WORK:-$REPO/out}/packages/v25.12/aarch64}"
APK="${1:-$(ls -t "$APK_DIR"/linux-postmarketos-qcom-sm8250-7.2.0-r*.apk | head -1)}"
NAME="$(basename "$APK")"

[ -f "$APK" ] || { echo "missing kernel apk: $APK" >&2; exit 1; }
echo "==> $APK -> $DEVICE"
scp "$APK" "$DEVICE:/tmp/$NAME"
ssh -tt "$DEVICE" "doas apk add --allow-untrusted --network=no --interactive=no --force-missing-repositories /tmp/$NAME && rm -f /tmp/$NAME && uname -a"
echo "==> reboot to load 7.2.0: ssh -tt $DEVICE doas reboot"
