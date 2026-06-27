# RK3588 Ubuntu Wayland Build System

Firefly AIO-3588L board running Linux 7.1.1 + Ubuntu Noble (24.04) + KDE Plasma Wayland.

## Prerequisites

```bash
# Host tools
sudo apt install -y build-essential flex bison bc libssl-dev rsync \
  libncurses-dev python3 wget curl git device-tree-compiler

# Firmware source (optional — auto-copies vendor binaries)
# Set FIREFLY_SDK in env.sh to your Firefly BSP SDK root
export FIREFLY_SDK=/path/to/Firefly_SDK
```

## Build

### 1. Clone and download dependencies

```bash
git clone git@github.com:zxc199108/rk3588_ubuntu_wayland.git
cd rk3588_ubuntu_wayland

# Download Linux 7.1.1 (150M)
wget https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.1.1.tar.xz
tar xf linux-7.1.1.tar.xz && mv linux-7.1.1 linux

# Download Ubuntu Noble cloud rootfs (205M)
wget https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-arm64-root.tar.xz \
  -O ubuntu-noble-rootfs.tar.xz

# Edit env.sh to set your toolchain and SDK paths
```

### 2. Apply config and patches

```bash
cp patches/initramfs.c linux/init/
cp kernel-config linux/.config
cp dts/* linux/arch/arm64/boot/dts/rockchip/
grep -q "firefly-aio-3588l" linux/arch/arm64/boot/dts/rockchip/Makefile || \
  echo 'dtb-$(CONFIG_ARCH_ROCKCHIP) += rk3588-firefly-aio-3588l.dtb' \
    >> linux/arch/arm64/boot/dts/rockchip/Makefile
```

### 3. One-click build

```bash
./build-ubuntu.sh
```

Script steps (all automated):
1. Copies vendor firmware (uboot.img, MiniLoaderAll.bin) from `$FIREFLY_SDK` if available
2. Extracts Ubuntu cloud rootfs, installs kernel modules + WiFi tools + GPU firmware
3. Creates `/sbin/init` → systemd, sets root/firefly passwords, fixes permissions
4. Configures apt (Tsinghua mirror), disables snapd and networkd-wait-online
5. Creates firstboot service (resize rootfs, format /home, mount binder)
6. Builds ext4 rootfs image, shrinks to minimum size (`resize2fs -M`)
7. Rebuilds boot.img (kernel + DTB + resource) from scratch
8. Packages update.img
9. Runs 16-point pre-flash self-check

**Output**: `output/update.img` (~2.4G)

## Flash to eMMC

```bash
# Using Firefly upgrade_tool (Linux)
sudo upgrade_tool uf output/update.img
```

## First Boot

- **登录**: `root` / `root` 或 `firefly` / `firefly`
- 首次启动自动执行：rootfs 扩容至 32G，格式化 /home 分区（26G），挂载 binder 设备
- 已配置清华 apt 镜像源

## Install Desktop

```bash
# 联网（Wi-Fi 或 Ethernet）
wpa_passphrase "SSID" "密码" > /tmp/wpa.conf
wpa_supplicant -B -i wlP2p33s0 -c /tmp/wpa.conf
dhcpcd wlP2p33s0

# 或使用 nmcli
nmcli device wifi connect "SSID" password "密码"

# 装 KDE Plasma Wayland
apt update && apt install -y kde-plasma-desktop plasma-nm plasma-workspace-wayland sddm
systemctl enable sddm --now
# 登录界面左下角选择 "Plasma (Wayland)"
```

## Verification

```bash
# GPU hardware acceleration
dmesg | grep panthor
ls /dev/dri/render*

# Wi-Fi
lsmod | grep rtw89

# Storage
df -h /
df -h /home
```

## Board Features

| Feature | Status | Details |
|---|---|---|
| HDMI | ✓ | Dual HDMI via VOP2 |
| GPU | ✓ | Mali-G610 via panthor (Mesa 25+) |
| Wi-Fi | ✓ | RTL8852BE via rtw89 |
| Ethernet | ✓ | RTL8211F (end0) |
| USB 3.0 | ✓ | Native support |
| eMMC | ✓ | 64G total, 32G / + 26G /home |
| Audio | - | Not tested |
| VPU | - | Not tested |

## File Structure

```
.
├── build-ubuntu.sh      # 一键构建脚本
├── build.sh             # 内核+固件构建脚本
├── check.sh             # 16 项预烧录自检
├── setpass.py           # 密码 hash 工具
├── env.sh               # 工具链环境
├── kernel-config        # .config for Linux 7.1.1
├── README.md
├── dts/
│   ├── rk3588-firefly-aio-3588l.dts
│   └── rk3588-firefly-core-3588j.dtsi
├── patches/
│   └── initramfs.c
├── kernel-config            # .config for Linux 7.1.1
├── firmware/
│   ├── bootramdisk.its      # FIT Image 模板
│   ├── parameter.txt        # 分区布局 (32G rootfs)
│   └── rtw89/               # Wi-Fi 固件
├── tools/                   # Rockchip 工具
│   ├── afptool
│   ├── mkimage
│   ├── resource_tool
│   └── rkImageMaker
└── keys/                # RSA2048 开发签名密钥
```
