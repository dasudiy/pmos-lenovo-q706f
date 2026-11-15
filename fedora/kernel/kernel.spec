# linux-q706f: SM8250 7.2.0 kernel for Lenovo Q706F.
# Built from an already-prepared tree (fedora/kernel/prepare.sh).
%define flavor q706f
%define debug_package %{nil}
%define kversion 7.2.0

Name: linux-%{flavor}
Version: 7.2.0
Release: 1%{?dist}
Summary: Mainline Linux kernel for Lenovo Q706F (SM8250)
License: GPL-2.0-only
URL: https://gitlab.postmarketos.org/soc/qualcomm-sm8250/linux
BuildArch: aarch64
ExclusiveArch: aarch64
Provides: kernel-uname-r
Obsoletes: kernel kernel-core kernel-modules
AutoReqProv: no

Source0: linux-prepared.tar.gz

%description
sm8250-%{kversion} plus Q706F device patches (volume-up wakeup, 4-lane DP,
AMSA26ZP01 brightness, DSI link-clock skip). Distinct from Fedora kernel
packages so dnf cannot replace it.

%prep
%setup -q -n linux-prepared

%build
unset LDFLAGS
make ARCH=arm64 LLVM=1 %{?_smp_mflags} \
	KBUILD_BUILD_VERSION="%{release}-postmarketos-qcom-sm8250"

%install
krel=$(make ARCH=arm64 kernelrelease)
make ARCH=arm64 LLVM=1 \
	modules_install dtbs_install \
	INSTALL_MOD_PATH=%{buildroot}/usr \
	INSTALL_DTBS_PATH=%{buildroot}/boot/dtbs \
	INSTALL_MOD_STRIP=1
if [ -e arch/arm64/boot/Image.gz ]; then
	install -Dm0644 arch/arm64/boot/Image.gz %{buildroot}/boot/vmlinuz-$krel
elif [ -e arch/arm64/boot/vmlinuz ]; then
	install -Dm0644 arch/arm64/boot/vmlinuz %{buildroot}/boot/vmlinuz-$krel
fi
install -Dm0644 arch/arm64/boot/dts/qcom/sm8250-lenovo-q706f.dtb \
	%{buildroot}/boot/dtbs/qcom/sm8250-lenovo-q706f.dtb
rm -f %{buildroot}/usr/lib/modules/*/build %{buildroot}/usr/lib/modules/*/source

%files
/boot/*
/usr/lib/modules/*

%changelog
* Thu Oct 8 2026 Asuka <asuka@localhost> - 7.2.0-1
- First Q706F Fedora kernel RPM (sm8250-7.2.0 + device patches).
