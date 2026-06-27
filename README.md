# RK3588 Ubuntu Wayland Build System

Firefly AIO-3588L board running Linux 7.1.1 + Ubuntu Noble with KDE Plasma Wayland.

## Quick Start

```bash
# 1. Download kernel 7.1.1
wget https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.1.1.tar.xz
tar xf linux-7.1.1.tar.xz && mv linux-7.1.1 linux

# 2. Apply patches
cp patches/initramfs.c linux/init/

# 3. Copy config + DTS
cp kernel-config linux/.config
cp dts/* linux/arch/arm64/boot/dts/rockchip/

# 4. Download Ubuntu cloud rootfs
wget https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-arm64-root.tar.xz \
  -O ubuntu-noble-rootfs.tar.xz

# 5. Build
./build-ubuntu.sh
# output: output/update.img
```

## Components

- **Kernel**: Linux 7.1.1 + panthor GPU + binder + rtw89 WiFi
- **Rootfs**: Ubuntu Noble (24.04) cloud image
- **Desktop**: KDE Plasma Wayland (installed via apt after first boot)
- **GPU**: Mali-G610 via panthor, Mesa 25+
- **WiFi**: RTL8852BE via rtw89 driver

## Key Files

| File | Purpose |
|---|---|
| `build-ubuntu.sh` | One-click rootfs + boot.img + update.img |
| `build.sh` | Kernel + firmware builder |
| `check.sh` | 16-point pre-flash verification |
| `dts/*` | Board device tree (AIO-3588L) |
| `kernel-config` | Linux 7.1.1 kernel config |
| `patches/initramfs.c` | initramfs alignment fix |
| `firmware/bootramdisk.its` | FIT image template |
| `firmware/parameter.txt` | Partition layout (32G rootfs) |

## Board Features

- HDMI output (VOP2)
- WiFi: RTL8852BE via rtw89
- Ethernet: RTL8211F
- GPU: Mali-G610 via panthor
- Watchdog: PC9202 (GPIO-driven disable)
- USB 3.0, PCIe, eMMC

## First Boot

```
root / root
firefly / firefly
```

- Rootfs auto-resizes to 32G
- /home auto-formats on 26G userdata partition
- Binder devices auto-mounted for Android container support
