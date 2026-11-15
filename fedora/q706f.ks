# Kickstart for Fedora 44 Workstation on Lenovo Q706F (SM8250).
# Not fed to Anaconda: the tablet boots Android ABL, not UEFI.
# rootfs/build-rootfs.sh implements this package set via dnf --installroot.

lang en_US.UTF-8
keyboard us
timezone UTC --utc
selinux --permissive
firewall --enabled --service=ssh
rootpw --lock
user --name=asuka --groups=wheel --plaintext --password=asuka

# Do not install Fedora kernel packages. Boot is our SM8250 7.2.0 tree
# packaged as linux-q706f, flashed as Android boot.img.
%packages
@^workstation-product-environment
NetworkManager
NetworkManager-wifi
wpa_supplicant
openssh-server
mesa-dri-drivers
mesa-vulkan-drivers
pipewire
pipewire-pulseaudio
wireplumber
alsa-ucm
alsa-utils
e2fsprogs
kmod
chrony
zram-generator
-kernel
-kernel-core
-kernel-modules
-kernel-modules-core
-kernel-devel
-linux-firmware
-gnome-initial-setup
%end

%post --erroronfail
dnf config-manager --save --setopt=excludepkgs=kernel,kernel-core,kernel-modules,kernel-modules-core,kernel-devel,kernel-headers
if [ -f /etc/selinux/config ]; then
	sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
fi
echo lenovo-q706f > /etc/hostname
%end
