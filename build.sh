#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

source env.sh

JOBS=${JOBS:-$(nproc)}
TOOLS="$SCRIPT_DIR/tools"
FW="$SCRIPT_DIR/firmware"
OUT="$SCRIPT_DIR/output"
KERNEL="$SCRIPT_DIR/linux"

# ============== kernel ==============
build_kernel() {
    echo "==> Building Linux kernel 7.0 for AIO-3588L..."
    cd "$KERNEL"


    make ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" -j$JOBS Image 2>&1 | tail -3
    make ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" -j$JOBS rockchip/rk3588-firefly-aio-3588l.dtb 2>&1

    echo "    -> Image"
    echo "    -> rk3588-firefly-aio-3588l.dtb"
}

# ============== resource.img ==============
build_resource() {
    echo "==> Creating resource.img..."
    cd "$KERNEL"
    # Always rebuild from scratch
    rm -f resource.img rk3588-firefly-aio-3588l.dtb
    cp arch/arm64/boot/dts/rockchip/rk3588-firefly-aio-3588l.dtb .

    # resource_tool combines DTB + optional logo into resource.img
    "$TOOLS/resource_tool" rk3588-firefly-aio-3588l.dtb 2>/dev/null
    [ -f resource.img ] && echo "    -> resource.img" || echo "    ERROR: resource.img not created"

    rm -f rk3588-firefly-aio-3588l.dtb
}

# ============== FIT boot.img ==============
build_bootimg() {
    echo "==> Creating FIT boot.img..."

    # Always rebuild from scratch
    rm -f "$KERNEL/boot.img"

    local its_template="$FW/bootramdisk.its"
    local tmp_its=$(mktemp)

    # Ensure resource.img exists and is fresh
    if [ ! -f "$KERNEL/resource.img" ]; then
        build_resource
    fi

    cp "$its_template" "$tmp_its"
    sed -i \
        -e "s~@KERNEL_DTB@~$KERNEL/arch/arm64/boot/dts/rockchip/rk3588-firefly-aio-3588l.dtb~" \
        -e "s~@KERNEL_IMG@~$KERNEL/arch/arm64/boot/Image~" \
        -e "s~@RESOURCE_IMG@~$KERNEL/resource.img~" \
        "$tmp_its"

    "$TOOLS/mkimage" -f "$tmp_its" -E -p 0x800 "$KERNEL/boot.img" 2>&1 | tail -3
    rm -f "$tmp_its"

    [ -f "$KERNEL/boot.img" ] && echo "    -> boot.img ($(du -h "$KERNEL/boot.img" | cut -f1))"
}

# ============== package update.img ==============
package_firmware() {
    echo "==> Packaging update.img..."

    # Ensure boot.img exists
    if [ ! -f "$KERNEL/boot.img" ]; then
        build_bootimg
    fi

    mkdir -p "$OUT/Image"
    rm -f "$OUT/Image/"*

    cp "$FW/MiniLoaderAll.bin"  "$OUT/Image/"
    cp "$FW/parameter.txt"      "$OUT/Image/"
    cp "$FW/uboot.img"          "$OUT/Image/"
    cp "$FW/misc.img"           "$OUT/Image/"
    cp "$KERNEL/boot.img"       "$OUT/Image/"
    cp "$FW/recovery.img"       "$OUT/Image/"
    cp -L "$FW/debian-rootfs.img"      "$OUT/Image/rootfs.img"
    cp "$FW/userdata.img"       "$OUT/Image/"

    cat > "$OUT/package-file" << PKG
# NAME		Relative path
package-file	package-file
bootloader	Image/MiniLoaderAll.bin
parameter	Image/parameter.txt
uboot		Image/uboot.img
misc		Image/misc.img
boot		Image/boot.img
recovery	Image/recovery.img
rootfs		Image/rootfs.img
userdata	Image/userdata.img
backup		RESERVED
PKG

    cd "$OUT"
    rm -f Image/update.img update.img

    "$TOOLS/afptool" -pack ./ Image/update.img 2>&1 | tail -3
    "$TOOLS/rkImageMaker" -RK3588 Image/MiniLoaderAll.bin Image/update.img update.img -os_type:androidos 2>&1 | tail -3

    echo ""
    echo "  ==> update.img is ready at: $OUT/update.img ($(du -h "$OUT/update.img" | cut -f1))"
    echo ""
    # Run self-check
    "$SCRIPT_DIR/check.sh"
}

# ============== all ==============
build_all() {
    build_kernel
    build_resource
    build_bootimg
    package_firmware
}

# ============== usage ==============
usage() {
    echo "Usage: $0 {kernel|resource|bootimg|firmware|all}"
    echo "  kernel    - Build Linux 6.12 kernel + DTB"
    echo "  resource  - Create resource.img"
    echo "  bootimg   - Create FIT boot.img"
    echo "  firmware  - Package update.img"
    echo "  all       - Build everything"
}

case "${1:-all}" in
    kernel)    build_kernel ;;
    resource)  build_resource ;;
    bootimg)   build_bootimg ;;
    firmware)  package_firmware ;;
    all)       build_all ;;
    -h|--help) usage ;;
    *)         usage; exit 1 ;;
esac
