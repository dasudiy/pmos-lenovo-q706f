#!/bin/bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE="${DEVICE:-asuka@172.16.42.1}"
if [ -z "${PMOS_WORK:-}" ] && [ -d "$(dirname "$REPO")/packages/v25.12/aarch64" ]; then
	PMOS_WORK="$(dirname "$REPO")"
fi
APK_DIR="${APK_DIR:-${PMOS_WORK:-$REPO/out}/packages/v25.12/aarch64}"
APK="${1:-$(ls -t "$APK_DIR"/linux-postmarketos-qcom-sm8250-6.17.0-r*.apk | head -1)}"
NAME="$(basename "$APK")"

echo "==> APK: $APK"
scp "$APK" "$DEVICE:/tmp/$NAME"
ssh -t "$DEVICE" "doas apk add --allow-untrusted /tmp/$NAME && rm -f /tmp/$NAME && uname -r"
echo "==> Reboot when ready: ssh -t $DEVICE doas reboot"
