#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source env.sh

echo "=== Build Ubuntu Noble rootfs ($(date)) ==="

ROOTFS_WORK="/tmp/ubuntu-build-$$"
TOOLS="$SCRIPT_DIR/tools"
FW="$SCRIPT_DIR/firmware"
OUT="$SCRIPT_DIR/output"
KERNEL="$SCRIPT_DIR/linux"
ROOTFS_IMG="$FW/debian-rootfs.img"

# Firefly SDK path (set env var FIREFLY_SDK or edit below)
FIREFLY_SDK="${FIREFLY_SDK:-/home/zxc/Linux6.1_SDK/Linux6.1_SDK/Firefly_SDK}"

# Copy vendor firmware from SDK if available
copy_from_sdk() {
    local src="$1" dst="$2"
    if [ -f "$src" ]; then
        cp "$src" "$dst" && echo "  $dst (from SDK)" || true
    else
        echo "  WARNING: $src not found, keep existing $dst"
    fi
}

if [ -d "$FIREFLY_SDK" ]; then
    echo "=== SDK found at $FIREFLY_SDK ==="
    copy_from_sdk "$FIREFLY_SDK/u-boot/uboot.img" "$FW/uboot.img"
    # MiniLoaderAll.bin: try pre-built, then boot_merger output
    for src in \
        "$FW/MiniLoaderAll.bin" \
        "$FIREFLY_SDK/rkbin/RKBOOT/RK3588MINIALL_MiniLoaderAll.bin" \
        "$FIREFLY_SDK/u-boot/MiniLoaderAll.bin" \
        ; do
        if [ -f "$src" ]; then
            [ "$src" != "$FW/MiniLoaderAll.bin" ] && cp "$src" "$FW/"
            echo "  MiniLoaderAll.bin OK"
            break
        fi
    done
fi

cleanup() { rm -rf "$ROOTFS_WORK" 2>/dev/null; }
trap cleanup EXIT

# 1. Fresh extract
echo "[1/9] Extracting Ubuntu cloud rootfs..."
rm -rf "$ROOTFS_WORK"
mkdir -p "$ROOTFS_WORK"
tar xf "$SCRIPT_DIR/ubuntu-noble-rootfs.tar.xz" -C "$ROOTFS_WORK/" 2>/dev/null || true

# 2. /sbin/init
echo "[2/9] Creating /sbin/init..."
ln -sf /usr/lib/systemd/systemd "$ROOTFS_WORK/sbin/init"

# 3. Root password
echo "[3/9] Setting root password..."
python3 "$SCRIPT_DIR/setpass.py" "$ROOTFS_WORK/etc/shadow" 2>/dev/null || true
echo "ttyS2" >> "$ROOTFS_WORK/etc/securetty" 2>/dev/null || true

# 4. Kernel modules + firmware + modules-load.d
echo "[4/9] Installing kernel modules + firmware..."
rm -rf "$ROOTFS_WORK/lib/modules"
cp -a "$SCRIPT_DIR/linux/kmod-install/lib/modules" "$ROOTFS_WORK/lib/" 2>/dev/null || {
    # Build modules if not cached
    echo "  Building kernel modules..."
    cd "$SCRIPT_DIR/linux"
    make ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" -j$(nproc) modules 2>&1 | tail -1
    rm -rf "$SCRIPT_DIR/linux/kmod-install"
    make ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" modules_install INSTALL_MOD_PATH="$SCRIPT_DIR/linux/kmod-install" 2>&1 | tail -1
    cp -a "$SCRIPT_DIR/linux/kmod-install/lib/modules" "$ROOTFS_WORK/lib/"
}
mkdir -p "$ROOTFS_WORK/lib/firmware/rtw89/"
cp "$SCRIPT_DIR/firmware/rtw89/"*.bin "$ROOTFS_WORK/lib/firmware/rtw89/" 2>/dev/null || true
mkdir -p "$ROOTFS_WORK/lib/firmware/arm/mali/arch10.8/"
MALI_FW="/home/zxc/Linux6.1_SDK/Linux6.1_SDK/Firefly_SDK/external/libmali/firmware/g610/mali_csffw.bin"
if [ -f "$MALI_FW" ]; then
    mkdir -p "$ROOTFS_WORK/lib/firmware/arm/mali/arch10.8"
    cp "$MALI_FW" "$ROOTFS_WORK/lib/firmware/arm/mali/arch10.8/"
    echo "  Mali firmware: OK"
else
    echo "  WARNING: Mali firmware not found at $MALI_FW"
fi
mkdir -p "$ROOTFS_WORK/etc/modules-load.d/"
printf 'rtw89_8852be\npanthor\n' > "$ROOTFS_WORK/etc/modules-load.d/wifi.conf"

# 5. Wi-Fi tools (binary only, no dbus activation)
echo "[5/9] Installing Wi-Fi tools..."
DEB_CACHE="$SCRIPT_DIR/cache"
mkdir -p "$DEB_CACHE"

# iw - extract with tar to avoid directory clearing
IW_DEB="$DEB_CACHE/iw.deb"
if [ ! -f "$IW_DEB" ]; then
    wget -q "https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/pool/main/i/iw/iw_5.16-1build1_arm64.deb" -O "$IW_DEB" 2>/dev/null || true
fi
if [ -f "$IW_DEB" ]; then
    mkdir -p /tmp/iw-extract-$$
    dpkg-deb --fsys-tarfile "$IW_DEB" 2>/dev/null | tar xf - -C /tmp/iw-extract-$$/
    find /tmp/iw-extract-$$ -name "iw" -type f -exec cp {} "$ROOTFS_WORK/sbin/" \;
    rm -rf /tmp/iw-extract-$$
    echo "  iw: OK"
else
    echo "  WARNING: iw deb not found, skip"
fi
# wpa_supplicant + wpa_cli + wpa_passphrase
WPA_DEB="$DEB_CACHE/wpa.deb"
WPA_DIR="$DEB_CACHE/wpa-extract"
if [ ! -f "$WPA_DEB" ]; then
    wget -q "https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/pool/main/w/wpa/wpasupplicant_2.10-21ubuntu0.4_arm64.deb" -O "$WPA_DEB" 2>/dev/null || true
fi
if [ -f "$WPA_DEB" ] && [ ! -d "$WPA_DIR" ]; then
    mkdir -p "$WPA_DIR"
    dpkg-deb --fsys-tarfile "$WPA_DEB" 2>/dev/null | tar xf - -C "$WPA_DIR/"
fi
if [ -d "$WPA_DIR" ]; then
    cp "$WPA_DIR/usr/sbin/wpa_supplicant" "$ROOTFS_WORK/usr/sbin/" 2>/dev/null
    cp "$WPA_DIR/usr/sbin/wpa_cli" "$ROOTFS_WORK/usr/sbin/" 2>/dev/null
    cp "$WPA_DIR/usr/bin/wpa_passphrase" "$ROOTFS_WORK/usr/bin/" 2>/dev/null
    echo "  wpa_supplicant: OK"
else
    echo "  WARNING: wpa_supplicant not found, skip"
fi
# libpcsclite
PCS_DEB="$DEB_CACHE/libpcsclite1.deb"
if [ ! -f "$PCS_DEB" ]; then
    wget -q "https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/pool/main/p/pcsc-lite/libpcsclite1_2.5.1-1_arm64.deb" -O "$PCS_DEB" 2>/dev/null || true
fi
if [ -f "$PCS_DEB" ]; then
    dpkg-deb --fsys-tarfile "$PCS_DEB" 2>/dev/null | tar xf - -C "$ROOTFS_WORK/"
    echo "  libpcsclite: OK"
else
    echo "  WARNING: libpcsclite not found, skip"
fi

# 6. Disable networkd-wait-online
echo "[6/9] Disabling networkd-wait-online..."
rm -f "$ROOTFS_WORK/etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service"
rm -f "$ROOTFS_WORK/etc/systemd/system/sockets.target.wants/systemd-networkd.socket"

# 6.5. Set Tsinghua mirror
echo "[6.5/9] Setting apt mirror to Tsinghua..."
sed -i 's|http://ports.ubuntu.com/ubuntu-ports|https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports|g' "$ROOTFS_WORK/etc/apt/sources.list.d/ubuntu.sources" 2>/dev/null || true

# 6.6. Create firefly user + disable gnome-initial-setup
echo "[6.6/9] Creating firefly user..."
PASS_HASH=$(python3 -c "import crypt; print(crypt.crypt('firefly', crypt.mksalt(crypt.METHOD_SHA512)))" 2>/dev/null)
if [ -n "$PASS_HASH" ]; then
    echo "firefly:x:1001:1001::/home/firefly:/bin/bash" >> "$ROOTFS_WORK/etc/passwd"
    echo "firefly:*:19973:0:99999:7:::" >> "$ROOTFS_WORK/etc/shadow"
    sed -i "s|^firefly:\*:|firefly:$PASS_HASH:|" "$ROOTFS_WORK/etc/shadow"
    echo "firefly:x:1001:" >> "$ROOTFS_WORK/etc/group"
    mkdir -p "$ROOTFS_WORK/home/firefly"
    cp -r "$ROOTFS_WORK/etc/skel/." "$ROOTFS_WORK/home/firefly/" 2>/dev/null
fi
# Allow root GUI login (sddm)
mkdir -p "$ROOTFS_WORK/etc/sddm.conf.d"
cat > "$ROOTFS_WORK/etc/sddm.conf.d/root-login.conf" << 'EOF'
[Users]
MaximumUid=0
EOF
rm -f "$ROOTFS_WORK/usr/share/applications/gnome-initial-setup.desktop" 2>/dev/null
rm -f "$ROOTFS_WORK/etc/xdg/autostart/gnome-initial-setup-first-login.desktop" 2>/dev/null

# 7. Remove snapd (blocks mkfs.ext4)
echo "[7/9] Removing snapd..."
rm -rf "$ROOTFS_WORK/var/lib/snapd"
rm -rf "$ROOTFS_WORK/snap"

# 7.5. Fix critical directory permissions
echo "[7.5/9] Fixing permissions..."
# Sticky bit for temp dirs (apt, systemd need this)
chmod 1777 "$ROOTFS_WORK/tmp"
chmod 1777 "$ROOTFS_WORK/var/tmp"
# Fix system directories (tar extraction may mess these up)
chmod 755 "$ROOTFS_WORK"
chmod 755 "$ROOTFS_WORK/usr" "$ROOTFS_WORK/usr/sbin" "$ROOTFS_WORK/usr/bin"
chmod 755 "$ROOTFS_WORK/lib" "$ROOTFS_WORK/etc"
chmod 700 "$ROOTFS_WORK/root"
chmod 755 "$ROOTFS_WORK/dev" 2>/dev/null
chmod 555 "$ROOTFS_WORK/proc" 2>/dev/null
chmod 555 "$ROOTFS_WORK/sys" 2>/dev/null
chmod 755 "$ROOTFS_WORK/run"
# Fix dpkg directories
chmod 755 "$ROOTFS_WORK/var/lib/dpkg" 2>/dev/null
chmod 755 "$ROOTFS_WORK/var/cache" 2>/dev/null
# Fix /var/run -> /run symlink target
[ -L "$ROOTFS_WORK/var/run" ] || ln -sf /run "$ROOTFS_WORK/var/run" 2>/dev/null
[ -L "$ROOTFS_WORK/var/lock" ] || ln -sf /run/lock "$ROOTFS_WORK/var/lock" 2>/dev/null

# 8. Build rootfs image
echo "[8/9] Building ext4 rootfs..."
# Add first-boot resize2fs + home partition setup
mkdir -p "$ROOTFS_WORK/etc/systemd/system/sysinit.target.wants"

cat > "$ROOTFS_WORK/etc/systemd/system/firstboot.service" << 'EOF'
[Unit]
Description=First boot setup (resize + home + binder)
ConditionPathExists=!/etc/firstboot.done
After=local-fs.target
Before=systemd-remount-fs.service

[Service]
Type=oneshot
ExecStart=/sbin/resize2fs /dev/mmcblk0p6
ExecStart=/sbin/mkfs.ext4 -F /dev/mmcblk0p7
ExecStart=/bin/mount /dev/mmcblk0p7 /home
ExecStart=/bin/cp -a /etc/skel/. /home/root/
ExecStart=/bin/chown -R root:root /home/root
ExecStart=/bin/mkdir -p /home/firefly
ExecStart=/bin/cp -a /etc/skel/. /home/firefly/
ExecStart=/bin/chown -R 1001:1001 /home/firefly
ExecStart=/bin/mkdir -p /dev/binderfs
ExecStart=/bin/mount -t binder binder /dev/binderfs
ExecStart=/bin/ln -sf /dev/binderfs/binder /dev/binder
ExecStart=/bin/ln -sf /dev/binderfs/hwbinder /dev/hwbinder
ExecStart=/bin/ln -sf /dev/binderfs/vndbinder /dev/vndbinder
ExecStart=/bin/touch /etc/firstboot.done
RemainAfterExit=yes

[Install]
WantedBy=sysinit.target
EOF

ln -sf /etc/systemd/system/firstboot.service "$ROOTFS_WORK/etc/systemd/system/sysinit.target.wants/"

# Add /home mount to fstab
mkdir -p "$ROOTFS_WORK/home"
echo '/dev/mmcblk0p7 /home ext4 defaults 0 2' >> "$ROOTFS_WORK/etc/fstab"

SIZE=2048  # Build at 2G, shrink to minimum after
rm -f "$ROOTFS_IMG"
truncate -s "${SIZE}M" "$ROOTFS_IMG"
mkfs.ext4 -E root_owner=0:0 -d "$ROOTFS_WORK" "$ROOTFS_IMG" 2>&1 | tail -1
e2fsck -fy "$ROOTFS_IMG" 2>&1 | tail -1
resize2fs -M "$ROOTFS_IMG" 2>&1
ls -lh "$ROOTFS_IMG"

# 9. Rebuild boot.img + package
echo "[9/9] Rebuilding boot.img + update.img..."
cd "$KERNEL"
rm -f resource.img boot.img rk3588-firefly-aio-3588l.dtb
cp arch/arm64/boot/dts/rockchip/rk3588-firefly-aio-3588l.dtb .
"$TOOLS/resource_tool" rk3588-firefly-aio-3588l.dtb 2>/dev/null
ITS_TMP=$(mktemp)
cp "$FW/bootramdisk.its" "$ITS_TMP"
sed -i -e "s~@KERNEL_DTB@~$KERNEL/rk3588-firefly-aio-3588l.dtb~" \
       -e "s~@KERNEL_IMG@~$KERNEL/arch/arm64/boot/Image~" \
       -e "s~@RESOURCE_IMG@~$KERNEL/resource.img~" "$ITS_TMP"
"$TOOLS/mkimage" -f "$ITS_TMP" -E -p 0x800 boot.img 2>&1 | tail -1
rm -f "$ITS_TMP" rk3588-firefly-aio-3588l.dtb

mkdir -p "$OUT/Image" && rm -f "$OUT/Image/"*
cp "$FW/MiniLoaderAll.bin"  "$OUT/Image/"
cp "$FW/parameter.txt"      "$OUT/Image/"
cp "$FW/uboot.img"          "$OUT/Image/"
cp "$FW/misc.img"           "$OUT/Image/"
cp "$KERNEL/boot.img"       "$OUT/Image/"
cp "$FW/recovery.img"       "$OUT/Image/"
cp -L "$ROOTFS_IMG"         "$OUT/Image/rootfs.img"
cp "$FW/userdata.img"       "$OUT/Image/"

cat > "$OUT/package-file" << PKG
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
"$TOOLS/afptool" -pack ./ Image/update.img 2>&1 | tail -1
"$TOOLS/rkImageMaker" -RK3588 Image/MiniLoaderAll.bin Image/update.img update.img -os_type:androidos 2>&1 | tail -1
ls -lh update.img

echo ""
echo "=== Done: $OUT/update.img ==="
"$SCRIPT_DIR/check.sh"
