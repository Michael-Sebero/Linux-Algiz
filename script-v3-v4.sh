#!/usr/bin/env bash
set -euo pipefail

# Locate the linux-cachyos directory relative to where this script lives
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PKGDIR="$SCRIPT_DIR/linux-cachyos"

cd "$PKGDIR"

# 1) Snapshot current modules (for localmodconfig tailoring)
lsmod > .host-lsmod

# 2) Patch PKGBUILD toggles
sed -i 's/_build_zfs:=no/_build_zfs:=yes/' PKGBUILD
sed -i 's/_build_nvidia:=no/_build_nvidia:=yes/' PKGBUILD
sed -i 's/_build_nvidia_open:=no/_build_nvidia_open:=yes/' PKGBUILD
sed -i 's/_use_auto_optimization:=yes/_use_auto_optimization:=no/' PKGBUILD
sed -i 's/_use_llvm_lto:=thin/_use_llvm_lto:=none/' PKGBUILD

# 3) Patch prepare() in PKGBUILD for trimming (safe insert)
if ! grep -q "localmodconfig" PKGBUILD; then
    sed -i '/^prepare()/,/^}/ s@^}.*@    yes "" | make olddefconfig\n    make LSMOD="$srcdir"/../.host-lsmod localmodconfig || true\n\n    ./scripts/config --disable DEBUG_INFO \\\n                     --disable DEBUG_KERNEL \\\n                     --disable KALLSYMS_ALL || true\n    ./scripts/config --enable KALLSYMS || true\n    ./scripts/config --enable TRIM_UNUSED_KSYMS || true\n    ./scripts/config --enable KERNEL_ZSTD \\\n                     --set-val  KERNEL_ZSTD_LEVEL 1 \\\n                     --enable MODULE_COMPRESS \\\n                     --enable MODULE_COMPRESS_ZSTD || true\n}# PATCHED@' PKGBUILD
fi

# 4) Ask user for build type
echo "Which kernel variant do you want to build?"
echo "1) GENERIC_V3 (wider compatibility)"
echo "2) GENERIC_V4 (optimized for newer CPUs)"
read -rp "Enter 1 or 2: " choice

if [[ "$choice" == "1" ]]; then
    proc_opt="GENERIC_V3"
    repo_suffix="v3"
elif [[ "$choice" == "2" ]]; then
    proc_opt="GENERIC_V4"
    repo_suffix="v4"
else
    echo "Invalid choice, exiting."
    exit 1
fi

# 5) Apply processor option
sed -i "s/_processor_opt:=.*/_processor_opt:=${proc_opt}/" PKGBUILD

# 6) Build kernel (use local build dir to avoid permission issues)
export BUILDDIR="$PKGDIR/build"
mkdir -p "$BUILDDIR"

MAKEFLAGS="-j$(nproc)" \
CC="ccache gcc" \
CXX="ccache g++" \
makepkg -si --noconfirm

# 7) Move built package into repo directory
mkdir -p "$SCRIPT_DIR/repo/x86_64_${repo_suffix}/cachyos-${repo_suffix}/"
mv ./*-x86_64_${repo_suffix}.pkg.tar.zst* \
   "$SCRIPT_DIR/repo/x86_64_${repo_suffix}/cachyos-${repo_suffix}/" || true

echo "✅ Kernel build complete for ${proc_opt}"
