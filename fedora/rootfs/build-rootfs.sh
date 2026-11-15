#!/bin/bash
# Build Fedora 44 Workstation aarch64 rootfs for Q706F.
# Run inside an aarch64 Fedora 44 environment:
#   podman run --rm -it --arch arm64 -v "$PWD:/work:Z" -w /work \
#     quay.io/fedora/fedora:44 fedora/rootfs/build-rootfs.sh
set -euo pipefail

fedora_release="${FEDORA_RELEASE:-44}"
build_user="${Q706F_USER:-asuka}"
kernel_rpm="${KERNEL_RPM:-}"
firmware_zip="${FIRMWARE_ZIP:-}"

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$script_dir/../.." && pwd)"
rootfs="${ROOTFS_DIR:-$repo_dir/out/rootfs}"
outdir="${OUT_DIR:-$repo_dir/out}"

echo ">>> Fedora $fedora_release Workstation rootfs for Q706F"
mkdir -p "$rootfs" "$outdir"

echo ">>> Installing rootfs packages"
dnf -y --installroot="$rootfs" --releasever="$fedora_release" \
	--use-host-config --setopt=install_weak_deps=False --setopt=tsflags=nodocs \
	--setopt=retries=15 --setopt=max_parallel_downloads=4 \
	install --skip-unavailable \
	'@^workstation-product-environment' \
	NetworkManager NetworkManager-wifi wpa_supplicant \
	openssh-server openssh-clients sudo chrony zram-generator \
	mesa-dri-drivers mesa-vulkan-drivers \
	pipewire pipewire-pulseaudio wireplumber alsa-ucm alsa-utils \
	e2fsprogs kmod qrtr NetworkManager-tui \
	dbus-daemon systemd-pam
dnf -y --installroot="$rootfs" --releasever="$fedora_release" \
	--use-host-config install --skip-unavailable qcom-firmware || true

dnf -y --installroot="$rootfs" --use-host-config -q remove \
	gnome-initial-setup kernel kernel-core kernel-modules \
	kernel-modules-core linux-firmware || true

echo ">>> Applying device overlay"
cp -a "$repo_dir/fedora/overlay/." "$rootfs/"
chmod 600 "$rootfs/etc/NetworkManager/system-connections/"*.nmconnection 2>/dev/null || true
chmod 440 "$rootfs/etc/sudoers.d/asuka"
chmod 755 "$rootfs/usr/libexec/q706f-usb-gadget"
chmod 755 "$rootfs/usr/lib/device-lenovo-q706f/"*.sh

if [ -f "$rootfs/etc/selinux/config" ]; then
	sed -i 's/^SELINUX=.*/SELINUX=permissive/' "$rootfs/etc/selinux/config"
fi

echo ">>> First user $build_user"
if ! grep -q "^${build_user}:" "$rootfs/etc/passwd"; then
	useradd --root "$rootfs" -m -G wheel,audio,video,dialout,input "$build_user"
fi
echo "${build_user}:asuka" | chpasswd --root "$rootfs"
mkdir -p "$rootfs/home/${build_user}/.ssh"
if [ -f "$repo_dir/fedora/overlay/home/asuka/.ssh/authorized_keys" ]; then
	install -m 700 -d "$rootfs/home/${build_user}/.ssh"
	install -m 600 "$repo_dir/fedora/overlay/home/asuka/.ssh/authorized_keys" \
		"$rootfs/home/${build_user}/.ssh/authorized_keys"
fi
chown -R 1000:1000 "$rootfs/home/${build_user}" || true
# sshd StrictModes refuses keys when the home directory is group-writable.
chmod 755 "$rootfs/home/${build_user}" || true
# Host keys are not arch-specific; generate at image build so first boot
# does not block sshd on tablet entropy / ssh-keygen units.
mkdir -p "$rootfs/etc/ssh"
# Keys are not arch-specific. Generate them on the build host; chroot
# ssh-keygen cannot run an aarch64 binary here.
for t in ed25519 ecdsa rsa; do
	key="$rootfs/etc/ssh/ssh_host_${t}_key"
	if [ ! -f "$key" ]; then
		ssh-keygen -t "$t" -f "$key" -N "" </dev/null
	fi
done

echo ">>> Firmware"
fw_commit="1be73450f1aaa6896c59fc1768a4fc98abe7cbda"
if [ -z "$firmware_zip" ]; then
	firmware_zip="$outdir/firmware-lenovo-q706f.zip"
	if [ ! -f "$firmware_zip" ]; then
		curl -L --fail -o "$firmware_zip" \
			"https://github.com/silime/lenovo-sm8250-q706f-firmware/archive/${fw_commit}.zip"
	fi
fi
fwdir="$(mktemp -d)"
if command -v unzip >/dev/null; then
	unzip -q "$firmware_zip" -d "$fwdir"
else
	python3 -m zipfile -e "$firmware_zip" "$fwdir"
fi
src="$(find "$fwdir" -maxdepth 1 -type d -name 'lenovo-sm8250-q706f-firmware-*' | head -1)"
install -Dm644 "$src"/sm8250/q706f/a650_zap.mbn -t "$rootfs/usr/lib/firmware/qcom/sm8250/q706f/"
install -Dm644 "$src"/sm8250/q706f/adsp* -t "$rootfs/usr/lib/firmware/qcom/sm8250/q706f/" 2>/dev/null || true
install -Dm644 "$src"/sm8250/q706f/cdsp* -t "$rootfs/usr/lib/firmware/qcom/sm8250/q706f/" 2>/dev/null || true
install -Dm644 "$src"/sm8250/q706f/slpi* -t "$rootfs/usr/lib/firmware/qcom/sm8250/q706f/" 2>/dev/null || true
install -Dm644 "$src"/sm8250/q706f/venus.mbn -t "$rootfs/usr/lib/firmware/qcom/sm8250/q706f/" 2>/dev/null || true
install -Dm644 "$src"/cirrus/cs35l45* -t "$rootfs/usr/lib/firmware/cirrus/" 2>/dev/null || true
if [ -f "$rootfs/usr/lib/firmware/cirrus/cs35l45-dsp1-spk-prot-spk1.wmfw" ]; then
	ln -sfn cs35l45-dsp1-spk-prot-spk1.wmfw \
		"$rootfs/usr/lib/firmware/cirrus/cs35l45-dsp1-spk-prot.wmfw"
	ln -sfn cs35l45-dsp1-spk-cali-spk1.wmfw \
		"$rootfs/usr/lib/firmware/cirrus/cs35l45-dsp1-spk-cali.wmfw"
fi
mkdir -p "$rootfs/usr/share/qcom/sm8250/Lenovo"
if [ -d "$src/hexagonfs" ]; then
	cp -a "$src/hexagonfs" "$rootfs/usr/share/qcom/sm8250/Lenovo/q706f"
	rm -rf "$rootfs/usr/share/qcom/sm8250/Lenovo/q706f/acdb" \
		"$rootfs/usr/share/qcom/sm8250/Lenovo/q706f/dsp" || true
fi

if [ -n "$kernel_rpm" ] && [ -f "$kernel_rpm" ]; then
	echo ">>> Installing kernel RPM"
	dnf -y --installroot="$rootfs" --use-host-config --setopt=tsflags=nodocs install "$kernel_rpm"
elif [ -d "${KERNEL_MODS:-$repo_dir/out/modules/7.2.0}" ]; then
	echo ">>> Installing kernel modules from ${KERNEL_MODS:-$repo_dir/out/modules/7.2.0}"
	mkdir -p "$rootfs/usr/lib/modules"
	cp -a "${KERNEL_MODS:-$repo_dir/out/modules/7.2.0}" "$rootfs/usr/lib/modules/"
	mkdir -p "$rootfs/boot/dtbs/qcom"
	if [ -f "$repo_dir/out/vmlinuz-7.2.0" ]; then
		install -Dm644 "$repo_dir/out/vmlinuz-7.2.0" "$rootfs/boot/vmlinuz-7.2.0"
	fi
	if [ -f "$repo_dir/out/sm8250-lenovo-q706f.dtb" ]; then
		install -Dm644 "$repo_dir/out/sm8250-lenovo-q706f.dtb" \
			"$rootfs/boot/dtbs/qcom/sm8250-lenovo-q706f.dtb"
	fi
	depmod -b "$rootfs" 7.2.0 || true
fi

# linux-firmware ships a650_* as .xz; dracut install_items needs the raw blobs.
for f in a650_sqe.fw a650_gmu.bin; do
	xz="$rootfs/usr/lib/firmware/qcom/$f.xz"
	raw="$rootfs/usr/lib/firmware/qcom/$f"
	if [ -f "$xz" ] && [ ! -f "$raw" ]; then
		xz -dkc "$xz" > "$raw"
	fi
done

echo ">>> Enable services"
systemctl --root="$rootfs" enable sshd NetworkManager gdm q706f-usb-gadget.service q706f-adsp.service q706f-bt-addr.service q706f-htpdate.service q706f-typec-sink.service || true
systemctl --root="$rootfs" enable q706f-grow-root.service || true

install -Dm644 "$repo_dir/fedora/boot/dracut.conf.d/q706f.conf" \
	"$rootfs/etc/dracut.conf.d/q706f.conf"

echo ">>> Cleaning"
rm -rf "$rootfs/var/cache/dnf" "$rootfs/var/cache/rpm"
rm -f "$rootfs/etc/machine-id" "$rootfs/var/lib/systemd/random-seed"

rpm -qa --root "$rootfs" --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort \
	> "$outdir/rootfs-manifest.txt"
archive="$outdir/q706f-fedora-${fedora_release}-rootfs.tar.gz"
tar -C "$rootfs" --one-file-system -czf "$archive" .
echo ">>> Done: $archive"
