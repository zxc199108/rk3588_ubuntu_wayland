#!/bin/bash
set -e
RED='\033[31m' GREEN='\033[32m' NC='\033[0m'
pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }

echo "=== 1. 内核测试 ==="
[ -f linux/arch/arm64/boot/Image ] && pass "内核 Image 存在 ($(du -h linux/arch/arm64/boot/Image | cut -f1))" || fail "内核缺失"
strings linux/arch/arm64/boot/Image | grep -q "Linux version 7" && pass "内核版本 7.0" || fail "内核版本不对"
grep -q "CONFIG_EXT4_FS=y\|CONFIG_DWMAC_ROCKCHIP=y\|CONFIG_DRM_ROCKCHIP=y" linux/.config && pass "关键驱动内建" || fail "驱动配置缺失"

echo "=== 2. DTB测试 ==="
[ -f linux/arch/arm64/boot/dts/rockchip/rk3588-firefly-aio-3588l.dtb ] && pass "DTB存在" || fail "DTB缺失"
dtc -I dtb -O dts linux/arch/arm64/boot/dts/rockchip/rk3588-firefly-aio-3588l.dtb 2>/dev/null | grep -q "Firefly AIO-3588L\|root=/dev/mmcblk" && pass "DTB内容正确" || fail "DTB内容错误"

echo "=== 3. Rootfs测试 ==="
[ -f firmware/debian-rootfs.img ] && pass "Rootfs镜像存在 ($(du -h firmware/debian-rootfs.img | cut -f1))" || fail "Rootfs缺失"
debugfs -R "cat /usr/lib/os-release" firmware/debian-rootfs.img 2>/dev/null | grep -q "Debian" && pass "Debian版本正确" || fail "OS版本不对"
debugfs -R "ls -l /usr/lib/firmware/rtw89/rtw8852b_fw.bin" firmware/debian-rootfs.img 2>/dev/null | grep -q rtw && pass "WiFi固件存在" || fail "WiFi固件缺失"
debugfs -R "cat /etc/modules-load.d/wifi.conf" firmware/debian-rootfs.img 2>/dev/null | grep -q rtw89 && pass "WiFi自启配置" || fail "WiFi自启缺失"

echo "=== 4. 模块测试 ==="
KO_COUNT=$(debugfs -R "ls -l /usr/lib/modules/7.0.12/kernel/drivers/net/wireless/realtek/rtw89" firmware/debian-rootfs.img 2>/dev/null | grep -c ".ko")
[ "$KO_COUNT" -ge 5 ] && pass "WiFi模块: $KO_COUNT ko" || fail "WiFi模块: 只有 $KO_COUNT 个"

echo "=== 5. Initrd测试 ==="
[ -f linux/initramfs.cpio.gz ] && pass "Initrd存在 ($(du -h linux/initramfs.cpio.gz | cut -f1))" || fail "Initrd缺失"
# Check initrd contains init
zcat linux/initramfs.cpio.gz 2>/dev/null | cpio -t 2>/dev/null | grep -q "init" && pass "Initrd含init脚本" || fail "Initrd缺init"
# Check mount binary  
zcat linux/initramfs.cpio.gz 2>/dev/null | cpio -t 2>/dev/null | grep -q "bin/mount" && pass "Initrd含mount" || fail "Initrd缺mount"

# === Critical: Check library dependencies ===
echo "=== 6. 库依赖检查 ==="
TMPI=$(mktemp -d)
cd "$TMPI"
zcat ~/rk3588-mainline/linux/initramfs.cpio.gz 2>/dev/null | cpio -idm 2>/dev/null
for bin in bin/mount bin/sh sbin/switch_root; do
    [ -f "$bin" ] || continue
    NEEDED=$(readelf -d "$bin" 2>/dev/null | grep NEEDED | awk '{print $NF}' | tr -d '[]')
    for lib in $NEEDED; do
        if find . -name "$lib" | grep -q .; then
            pass "  $bin -> $lib"
        else
            fail "  $bin -> $lib MISSING!"
        fi
    done
done
cd / && rm -rf "$TMPI"

echo ""
echo -e "${GREEN}=== 所有检查通过 ===${NC}"
