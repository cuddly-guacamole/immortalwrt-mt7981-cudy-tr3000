#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#
# Copyright (c) 2019-2024 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# Modify default IP
sed -i 's/192\.168\.[0-9]*\.[0-9]*/192.168.10.1/g' package/base-files/files/bin/config_generate

# Modify default theme
#sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile

# Modify hostname
#sed -i 's/OpenWrt/P3TERX-Router/g' package/base-files/files/bin/config_generate

# 临时解决Rust问题
sed -i 's/ci-llvm=true/ci-llvm=false/g' feeds/packages/lang/rust/Makefile

# add date in output file name
sed -i -e '/^IMG_PREFIX:=/i BUILD_DATE := $(shell date +%Y%m%d)' \
       -e '/^IMG_PREFIX:=/ s/\($(SUBTARGET)\)/\1-$(BUILD_DATE)/' include/image.mk

# set ubi to 122M
sed -i 's/reg = <0x5c0000 0x7000000>;/reg = <0x5c0000 0x7a40000>;/' target/linux/mediatek/dts/mt7981b-cudy-tr3000-v1-ubootmod.dts

# ============================================================
# 函数1: 集成 mihomo 内核 (OpenClash)
# ============================================================
integrate_mihomo() {
    echo "=========================================="
    echo "📦 开始集成 mihomo 内核 (OpenClash)"
    echo "=========================================="
    
    mkdir -p files/etc/openclash/core
    
    local KERNEL_PATH="files/etc/openclash/core/clash_meta"
    
    # 硬编码正式版本号
    local STABLE_TAG="v1.19.29"
    local FILE_NAME="mihomo-linux-arm64-${STABLE_TAG}.gz"
    local DOWNLOAD_URL="https://github.com/MetaCubeX/mihomo/releases/download/${STABLE_TAG}/${FILE_NAME}"
    
    echo "📥 下载 mihomo 正式版: ${STABLE_TAG}"
    if wget -q -O /tmp/mihomo.gz "$DOWNLOAD_URL"; then
        gunzip -c /tmp/mihomo.gz > "$KERNEL_PATH"
        chmod 755 "$KERNEL_PATH"
        upx --best --lzma "$KERNEL_PATH" 2>/dev/null || true
        echo "✅ mihomo 内核已集成到: $KERNEL_PATH"
        ls -lh "$KERNEL_PATH"
        rm -f /tmp/mihomo.gz
        echo "✅ mihomo 内核集成完成"
    else
        echo "❌ mihomo 内核下载失败"
        echo "=========================================="
        return 1
    fi
    
    echo "=========================================="
    return 0
}

# ============================================================
# 函数2: 集成 AdGuardHome
# ============================================================
integrate_adguardhome() {
    echo "=========================================="
    echo "📦 开始集成 AdGuardHome"
    echo "=========================================="
    
    mkdir -p files/usr/bin
    
    # 硬编码版本号
    local STABLE_TAG="v0.107.78"
    local DOWNLOAD_URL="https://github.com/AdguardTeam/AdGuardHome/releases/download/${STABLE_TAG}/AdGuardHome_linux_arm64.tar.gz"
    
    echo "📥 下载 AdGuardHome: ${STABLE_TAG}"
    if wget -q -O /tmp/AdGuardHome.tar.gz "$DOWNLOAD_URL"; then
        tar -xzf /tmp/AdGuardHome.tar.gz -C /tmp/
        cp /tmp/AdGuardHome/AdGuardHome files/usr/bin/AdGuardHome
        chmod 755 files/usr/bin/AdGuardHome
        upx --best --lzma files/usr/bin/AdGuardHome 2>/dev/null || true
        echo "✅ AdGuardHome 已集成到: files/usr/bin/AdGuardHome"
        ls -lh files/usr/bin/AdGuardHome
        rm -f /tmp/AdGuardHome.tar.gz
        rm -rf /tmp/AdGuardHome
        echo "✅ AdGuardHome 集成完成"
    else
        echo "❌ AdGuardHome 下载失败"
        echo "=========================================="
        return 1
    fi
    
    echo "=========================================="
    return 0
}

# ============================================================
# 主执行流程: 依次调用两个独立函数
# ============================================================
echo ""
echo "🚀 开始执行集成任务..."
echo ""

integrate_mihomo
integrate_adguardhome

echo ""
echo "=========================================="
echo "✅ 所有集成任务完成!"
echo "=========================================="
