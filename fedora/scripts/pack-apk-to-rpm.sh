#!/bin/bash
# Wrap a built linux-postmarketos-qcom-sm8250 7.2.0 APK as linux-q706f.rpm
# so the Fedora rootfs can install the same binary that booted on pmOS.
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
if [ -z "${PMOS_WORK:-}" ] && [ -d "$(dirname "$repo")/packages/v25.12/aarch64" ]; then
	PMOS_WORK="$(dirname "$repo")"
fi
apk="${1:-$(ls -t "${PMOS_WORK:-$repo/out}/packages/v25.12/aarch64"/linux-postmarketos-qcom-sm8250-7.2.0-r*.apk 2>/dev/null | head -1)}"
[ -f "$apk" ] || { echo "missing apk" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/payload"
tar -C "$tmp/payload" -xf "$apk"
rm -f "$tmp/payload"/.PKGINFO "$tmp/payload"/.SIGN* "$tmp/payload"/.pre* "$tmp/payload"/.post* 2>/dev/null || true
mkdir -p "$tmp/rpmbuild/BUILD" "$tmp/rpmbuild/RPMS" "$tmp/buildroot"
cp -a "$tmp/payload"/. "$tmp/buildroot/"

cat > "$tmp/linux-q706f.spec" << 'EOF'
Name: linux-q706f
Version: 7.2.0
Release: 1
Summary: SM8250 7.2.0 kernel for Lenovo Q706F
License: GPL-2.0-only
BuildArch: aarch64
AutoReqProv: no
Provides: kernel-uname-r
%description
Same binary as linux-postmarketos-qcom-sm8250-7.2.0, packaged for Fedora.
%install
true
%files
/boot
/usr/lib/modules
EOF

( cd "$tmp" && rpmbuild --define "_topdir $tmp/rpmbuild" --buildroot "$tmp/buildroot" \
	--target aarch64 --nodeps -bb "$tmp/linux-q706f.spec" )
mkdir -p "$repo/out"
find "$tmp/rpmbuild/RPMS" -name '*.rpm' -exec cp {} "$repo/out/" \;
ls -lh "$repo/out"/linux-q706f*.rpm
