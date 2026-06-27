#!/bin/bash
export CROSS_COMPILE=aarch64-none-linux-gnu-
export ARCH=arm64
export TOOLCHAIN_DIR=/home/zxc/Linux6.1_SDK/Linux6.1_SDK/Firefly_SDK/prebuilts/gcc/linux-x86/aarch64/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu
export PATH=$TOOLCHAIN_DIR/bin:$PATH
export JOBS=$(nproc)
# Firefly BSP SDK path for vendor firmware
export FIREFLY_SDK=/home/zxc/Linux6.1_SDK/Linux6.1_SDK/Firefly_SDK
