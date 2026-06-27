#!/bin/bash
export CROSS_COMPILE=aarch64-none-linux-gnu-
export ARCH=arm64
export JOBS=$(nproc)

# Firefly BSP SDK root — edit this to match your setup
export FIREFLY_SDK=/home/zxc/Linux6.1_SDK/Linux6.1_SDK/Firefly_SDK

# Toolchain from SDK (auto-derived)
export TOOLCHAIN_DIR="$FIREFLY_SDK/prebuilts/gcc/linux-x86/aarch64/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu"
if [ -d "$TOOLCHAIN_DIR/bin" ]; then
    export PATH="$TOOLCHAIN_DIR/bin:$PATH"
fi
