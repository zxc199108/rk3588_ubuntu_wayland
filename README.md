# RK3588 Ubuntu Wayland Build System

Firefly AIO-3588L board running Linux 7.1.1 + Ubuntu Noble (24.04) + KDE Plasma Wayland.

## Prerequisites

```bash
sudo apt install -y build-essential flex bison bc libssl-dev rsync \
  libncurses-dev python3 wget curl git device-tree-compiler
```

## Build

### 1. Download kernel 7.1.1 and Ubuntu rootfs

```bash
cd ~/rk3588_ubuntu_wayland/

# Download kernel source (150M compressed, ~1.5G extracted)
wget https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.1.1.tar.xz
tar xf linux-7.1.1.tar.xz
mv linux-7.1.1 linux

# Download Ubuntu Noble cloud rootfs (205M compressed, ~1.2G extracted)
wget https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-arm64-root.tar.xz \
  -O ubuntu-noble-rootfs.tar.xz
```

### 2. Apply patches and copy config

```bash
# initramfs alignment fix (required for initrd on ARM)
cp patches/initramfs.c linux/init/

# Kernel config (panthor GPU, binder, rtw89 WiFi, btrfs)
cp kernel-config linux/.config

# Board device trees
cp dts/*.dts dts/*.dtsi linux/arch/arm64/boot/dts/rockchip/

# Add our DTS to the Makefile
grep -q "firefly-aio-3588l" linux/arch/arm64/boot/dts/rockchip/Makefile || \
  echo 'dtb-$(CONFIG_ARCH_ROCKCHIP) += rk3588-firefly-aio-3588l.dtb' \
    >> linux/arch/arm64/boot/dts/rockchip/Makefile
```

### 3. Set up toolchain

默认使用 Firefly SDK 预编译工具链，也可替换为你自己的：

```bash
# 编辑 env.sh 或设置环境变量
export PATH="/path/to/gcc-arm-10.3/bin:$PATH"
export CROSS_COMPILE=aarch64-none-linux-gnu-
export ARCH=arm64
```

### 4. One-click build

```bash
./build-ubuntu.sh
```

脚本自动执行：
1. 解压 Ubuntu 云镜像到临时目录
2. 创建 `/sbin/init` → systemd（Ubuntu 云镜像缺失此项）
3. 设置 root 密码（root/root）和 firefly 用户（firefly/firefly）
4. 编译内核模块并安装
5. 添加 rtw89 + Mali G610 固件
6. 添加 Wi-Fi 工具（wpa_supplicant + iw + wpa_passphrase + wpa_cli）
7. 配置清华 apt 镜像源
8. 禁用 snapd、networkd-wait-online
9. 修复权限（/tmp 1777, 目录 755）
10. 创建首次启动服务（resize2fs、home 分区格式化、binder 设备挂载）
11. 构建 ext4 根文件系统
12. 重建 boot.img（kernel + DTB + resource）
13. 打包 update.img
14. 运行 16 项自检

**输出**: `output/update.img` (~2.4G)

## Vendor Firmware

Before building, copy these files from the Firefly BSP SDK to `firmware/`:

```bash
# From https://drive.google.com/...  or the Firefly BSP SDK
cp /path/to/sdk/rkbin/MiniLoaderAll.bin firmware/
cp /path/to/sdk/u-boot/uboot.img firmware/
cp /path/to/sdk/rkbin/recovery.img firmware/
```

Alternatively, get the complete firmware pack from Firefly.

## Flash to eMMC

使用 RKDevTool (Windows) 或 upgrade_tool (Linux)：

```bash
# Linux flashing (需要 Firefly SDK 的 upgrade_tool)
sudo upgrade_tool uf output/update.img
```

或使用 SD 卡通过 Maskrom 模式烧录。

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
│   └── initramfs.c      # initramfs 对齐修复
├── firmware/
│   ├── bootramdisk.its  # FIT Image 模板
│   └── parameter.txt    # 分区布局 (32G rootfs)
├── tools/               # Rockchip 工具
│   ├── afptool
│   ├── mkimage
│   ├── resource_tool
│   └── rkImageMaker
└── keys/                # RSA2048 开发签名密钥
```
