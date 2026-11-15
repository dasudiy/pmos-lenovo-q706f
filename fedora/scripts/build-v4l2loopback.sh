#!/bin/bash
# Build v4l2loopback out of tree against the kernel #8 tree; sign + zstd via modules_install.
set -euo pipefail
K=${KERNEL_TREE:?set KERNEL_TREE to the prepared device kernel tree}
SRC=${V4L2LB_SRC:?set V4L2LB_SRC to the v4l2loopback source tree}
OUT=${OUT:-$(mktemp -d)}
M="make -C $K ARCH=arm64 LLVM=1 RUSTC=/nonexistent HOSTCC=gcc HOSTCXX=g++ HOSTLD=ld HOSTAR=ar KBUILD_BUILD_VERSION=8-postmarketos-qcom-sm8250 M=$SRC"
$M -j8 modules
$M modules_install INSTALL_MOD_PATH="$OUT" INSTALL_MOD_STRIP=1 INSTALL_MOD_DIR=extra DEPMOD=true
echo BUILD_OK
