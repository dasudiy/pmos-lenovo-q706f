# libcamera for the Q706F

`0001-libcamera-add-ov8856-and-ov13b10-sensor-helpers-and-properties.patch` adds `CameraSensorHelper` entries for OV8856 and OV13B10: a linear analogue gain with 128 as 1x, and a black level of 64 at 10 bits. It also adds static properties for both sensors: 1.12 µm unit cells, test pattern modes, and sensor delays.

The Fedora package is the `libcamera-0.7.1-2.fc44` SRPM with the patch added as `Patch100` and `Release: 2.q706f1%{?dist}`. The spec change is in `libcamera-0.7.1-2-q706f.spec.diff`. Build it in an aarch64 Fedora 44 container:

```bash
dnf download --source libcamera-0.7.1-2.fc44
rpm -i --define "_topdir $PWD/rpmbuild" libcamera-0.7.1-2.fc44.src.rpm
cp 0001-libcamera-add-ov8856-and-ov13b10-sensor-helpers-and-properties.patch \
   rpmbuild/SOURCES/0100-q706f-ov8856-ov13b10-sensor-helpers-and-properties.patch
patch -d rpmbuild/SPECS -p1 < libcamera-0.7.1-2-q706f.spec.diff
dnf -y builddep rpmbuild/SPECS/libcamera.spec
rpmbuild --define "_topdir $PWD/rpmbuild" -ba rpmbuild/SPECS/libcamera.spec
```

Base the package on `-2` or later. The `-1` spec re-signs the IPA modules from the wrong directory after strip, so their signatures do not verify. The build signs the IPA modules with its own key. Do not copy IPA modules between builds.

On the tablet:

```bash
sudo dnf install ./libcamera-0.7.1-2.q706f1.fc44.aarch64.rpm ./libcamera-ipa-0.7.1-2.q706f1.fc44.aarch64.rpm \
                 ./libcamera-tools-0.7.1-2.q706f1.fc44.aarch64.rpm ./libcamera-qcam-0.7.1-2.q706f1.fc44.aarch64.rpm
sudo dnf versionlock add libcamera libcamera-ipa libcamera-tools libcamera-qcam
```

The kernel cmdline needs `cma=256M` (see `fedora/boot/cmdline`).
