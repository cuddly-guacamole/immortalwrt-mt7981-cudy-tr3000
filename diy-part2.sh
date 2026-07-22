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
sed -i 's/192.168.1.1/192.168.10.1/g' package/base-files/files/bin/config_generate

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
    
    # 检查是否启用 OpenClash
    if ! grep -q "CONFIG_PACKAGE_luci-app-openclash=y" .config; then
        echo "⏭️ OpenClash 未启用，跳过 mihomo 内核集成"
        return 0
    fi
    
    echo "✅ 检测到 OpenClash 已启用"
    mkdir -p files/etc/openclash/core
    
    local DOWNLOAD_SUCCESS=false
    local KERNEL_PATH="files/etc/openclash/core/clash_meta"
    
    # ---- 优先尝试预发行版 (Prerelease-Alpha) ----
    echo "📥 尝试获取预发行版 (Prerelease-Alpha)..."
    local SHORT_HASH=$(wget -q -O- \
        --header "Authorization: token ${GITHUB_TOKEN}" \
        "https://api.github.com/repos/MetaCubeX/mihomo/git/refs/tags/Prerelease-Alpha" \
        | grep -o '"sha": "[^"]*"' \
        | head -n 1 \
        | sed 's/"sha": "//;s/"//;s/^\(........\).*$/\1/')
    
    if [ -n "$SHORT_HASH" ]; then
        echo "✅ 获取到提交哈希: $SHORT_HASH"
        local PRERELEASE_FILE="mihomo-linux-arm64-${SHORT_HASH}.gz"
        local PRERELEASE_URL="https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/${PRERELEASE_FILE}"
        
        echo "📥 下载预发行版: $PRERELEASE_FILE"
        if wget -q -O /tmp/mihomo.gz "$PRERELEASE_URL"; then
            gunzip -c /tmp/mihomo.gz > "$KERNEL_PATH"
            chmod 755 "$KERNEL_PATH"
            upx --best --lzma "$KERNEL_PATH" 2>/dev/null || true
            echo "✅ mihomo 预发行版内核已集成到: $KERNEL_PATH"
            ls -lh "$KERNEL_PATH"
            rm -f /tmp/mihomo.gz
            DOWNLOAD_SUCCESS=true
        else
            echo "⚠️ 预发行版下载失败，尝试正式版..."
        fi
    else
        echo "⚠️ 无法获取预发行版信息，尝试正式版..."
    fi
    
    # ---- 如果预发行版失败，尝试正式版 ----
    if [ "$DOWNLOAD_SUCCESS" = "false" ]; then
        echo "📥 正在获取最新正式版标签..."
        local STABLE_TAG=$(wget -q -O- \
            --header "Authorization: token ${GITHUB_TOKEN}" \
            "https://api.github.com/repos/MetaCubeX/mihomo/tags" \
            | grep -o '"name": "v[0-9]*\.[0-9]*\.[0-9]*"' \
            | sed 's/"name": "//;s/"//g' \
            | sort -V \
            | tail -n 1)
        
        if [ -n "$STABLE_TAG" ]; then
            echo "✅ 找到正式版标签: $STABLE_TAG"
            local VERSION_NUM=$(echo "$STABLE_TAG" | sed 's/^v//')
            local FILE_NAME="mihomo-linux-arm64-${VERSION_NUM}.gz"
            local DOWNLOAD_URL="https://github.com/MetaCubeX/mihomo/releases/download/${STABLE_TAG}/${FILE_NAME}"
            
            echo "📥 下载正式版: $FILE_NAME"
            if wget -q -O /tmp/mihomo.gz "$DOWNLOAD_URL"; then
                gunzip -c /tmp/mihomo.gz > "$KERNEL_PATH"
                chmod 755 "$KERNEL_PATH"
                upx --best --lzma "$KERNEL_PATH" 2>/dev/null || true
                echo "✅ mihomo 正式版内核已集成到: $KERNEL_PATH"
                ls -lh "$KERNEL_PATH"
                rm -f /tmp/mihomo.gz
                DOWNLOAD_SUCCESS=true
            else
                echo "⚠️ 正式版下载失败"
            fi
        else
            echo "⚠️ 未找到正式版标签"
        fi
    fi
    
    if [ "$DOWNLOAD_SUCCESS" = "false" ]; then
        echo "❌ mihomo 内核集成失败 (预发行版和正式版均不可用)"
        return 1
    fi
    
    echo "✅ mihomo 内核集成完成"
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
    
    # 检查是否启用 AdGuardHome
    if ! grep -q "CONFIG_PACKAGE_adguardhome=y" .config; then
        echo "⏭️ AdGuardHome 未启用，跳过集成"
        return 0
    fi
    
    echo "✅ 检测到 AdGuardHome 已启用"
    mkdir -p files/usr/bin
    
    local DOWNLOAD_SUCCESS=false
    
    # ---- 优先尝试 Beta 预发行版 ----
    echo "📥 正在获取最新 Beta 预发行版标签..."
    local BETA_TAG=$(wget -q -O- \
        --header "Authorization: token ${GITHUB_TOKEN}" \
        "https://api.github.com/repos/AdguardTeam/AdGuardHome/tags" \
        | grep -o '"name": "v[0-9.]*-b\.[0-9]*"' \
        | sed 's/"name": "//;s/"//g' \
        | sort -V \
        | tail -n 1)
    
    if [ -n "$BETA_TAG" ]; then
        echo "✅ 找到 Beta 预发行版标签: $BETA_TAG"
        local DOWNLOAD_URL="https://github.com/AdguardTeam/AdGuardHome/releases/download/${BETA_TAG}/AdGuardHome_linux_arm64.tar.gz"
        
        echo "📥 下载 AdGuardHome Beta 版..."
        if wget -q -O /tmp/AdGuardHome.tar.gz "$DOWNLOAD_URL"; then
            tar -xzf /tmp/AdGuardHome.tar.gz -C /tmp/
            cp /tmp/AdGuardHome/AdGuardHome files/usr/bin/AdGuardHome
            chmod 755 files/usr/bin/AdGuardHome
            upx --best --lzma files/usr/bin/AdGuardHome 2>/dev/null || true
            echo "✅ AdGuardHome Beta 版已集成:"
            ls -lh files/usr/bin/AdGuardHome
            rm -f /tmp/AdGuardHome.tar.gz
            rm -rf /tmp/AdGuardHome
            DOWNLOAD_SUCCESS=true
        else
            echo "⚠️ Beta 版下载失败，尝试正式版..."
        fi
    else
        echo "⚠️ 未找到 Beta 预发行版标签，尝试正式版..."
    fi
    
    # ---- 如果 Beta 失败，尝试正式版 ----
    if [ "$DOWNLOAD_SUCCESS" = "false" ]; then
        echo "📥 正在获取最新正式版标签..."
        local STABLE_TAG=$(wget -q -O- \
            --header "Authorization: token ${GITHUB_TOKEN}" \
            "https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest" \
            | grep -o '"tag_name": "[^"]*"' \
            | sed 's/"tag_name": "//;s/"//g')
        
        if [ -n "$STABLE_TAG" ]; then
            echo "✅ 找到正式版标签: $STABLE_TAG"
            local DOWNLOAD_URL="https://github.com/AdguardTeam/AdGuardHome/releases/download/${STABLE_TAG}/AdGuardHome_linux_arm64.tar.gz"
            
            echo "📥 下载 AdGuardHome 正式版..."
            if wget -q -O /tmp/AdGuardHome.tar.gz "$DOWNLOAD_URL"; then
                tar -xzf /tmp/AdGuardHome.tar.gz -C /tmp/
                cp /tmp/AdGuardHome/AdGuardHome files/usr/bin/AdGuardHome
                chmod 755 files/usr/bin/AdGuardHome
                upx --best --lzma files/usr/bin/AdGuardHome 2>/dev/null || true
                echo "✅ AdGuardHome 正式版已集成:"
                ls -lh files/usr/bin/AdGuardHome
                rm -f /tmp/AdGuardHome.tar.gz
                rm -rf /tmp/AdGuardHome
                DOWNLOAD_SUCCESS=true
            else
                echo "⚠️ 正式版下载失败"
            fi
        else
            echo "⚠️ 未找到正式版标签"
        fi
    fi
    
    if [ "$DOWNLOAD_SUCCESS" = "false" ]; then
        echo "❌ AdGuardHome 集成失败 (Beta 和正式版均不可用)"
        return 1
    fi
    
    echo "✅ AdGuardHome 集成完成"
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
