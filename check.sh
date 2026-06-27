#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
RED='\033[0;31m' GREEN='\033[0;32m' NC='\033[0m'
pass() { echo -e "  ${GREEN}[OK]${NC} $*"; }
fail() { echo -e "  ${RED}[FAIL]${NC} $*"; ((ERRORS++)); }
ERRORS=0; echo "=== Self-check $(date) ==="

# 1. Kernel Image
[ -f linux/arch/arm64/boot/Image ] && pass "Kernel Image found" || fail "Kernel Image missing"

# 2. DTB
DTB="linux/arch/arm64/boot/dts/rockchip/rk3588-firefly-aio-3588l.dtb"
[ -f "$DTB" ] && pass "DTB found" || fail "DTB missing"

# 3. GPU enabled in DTB
dtc -I dtb -O dts "$DTB" 2>/dev/null | grep -q "mali-supply" 2>/dev/null && \
  pass "GPU mali-supply in DTB" || fail "GPU not enabled in DTB"

# 4. rootfs.img
ROOTFS="firmware/debian-rootfs.img"
[ -f "$ROOTFS" ] && pass "rootfs.img found" || fail "rootfs.img missing"

# 5. init: check /sbin/init OR init= in bootargs
if debugfs -R "stat /sbin/init" "$ROOTFS" 2>/dev/null | grep -qi "symlink\|regular"; then
  pass "/sbin/init exists"
elif dtc -I dtb -O dts "$DTB" 2>/dev/null | grep -q "init="; then
  pass "init= specified in bootargs"
else
  fail "no init found (will panic)"
fi

# 6. systemd binary
debugfs -R "stat /usr/lib/systemd/systemd" "$ROOTFS" 2>/dev/null | grep -q "regular" && \
  pass "systemd binary exists" || fail "systemd missing"

# 7. /var/run -> /run symlink
debugfs -R "stat /var/run" "$ROOTFS" 2>/dev/null | grep -qi "symlink" && \
  pass "/var/run is symlink" || fail "/var/run is dir (D-Bus will fail)"

# 8. modules installed
debugfs -R "ls /lib/modules/" "$ROOTFS" 2>/dev/null | grep -q "7\.\|6\." && \
  pass "kernel modules found" || fail "no kernel modules"

# 9. rtw89 firmware
debugfs -R "ls /lib/firmware/rtw89/" "$ROOTFS" 2>/dev/null | grep -q "8852b" && \
  pass "rtw89 firmware found" || fail "rtw89 firmware missing"

# 10. Mali firmware
debugfs -R "ls /lib/firmware/arm/mali/" "$ROOTFS" 2>/dev/null | grep -q "arch" && \
  pass "Mali firmware found" || fail "Mali firmware missing"

# 11. modules-load.d
debugfs -R "cat /etc/modules-load.d/wifi.conf" "$ROOTFS" 2>/dev/null | grep -qE "rtw89|panthor" && \
  pass "modules-load.d configured" || fail "modules-load.d missing"

# 12. boot.img
BOOTIMG="linux/boot.img"
[ -f "$BOOTIMG" ] && pass "boot.img found" || fail "boot.img missing"

# 13. FIT image structure
strings "$BOOTIMG" 2>/dev/null | grep -q "U-Boot FIT" && \
  pass "boot.img is valid FIT" || fail "boot.img is not FIT"

# 14. fbcon=map:0 in bootargs
dtc -I dtb -O dts "$DTB" 2>/dev/null | grep -q "fbcon=map:0" && \
  pass "fbcon fix in bootargs" || fail "fbcon fix missing"

# 15. userdata and misc
[ -f firmware/misc.img ] && pass "misc.img found" || fail "misc.img missing"
[ -f firmware/userdata.img ] && pass "userdata.img found" || fail "userdata.img missing"

echo ""
[ $ERRORS -eq 0 ] && echo -e "${GREEN}All checks passed${NC}" || echo -e "${RED}$ERRORS check(s) failed${NC}"
exit $ERRORS
