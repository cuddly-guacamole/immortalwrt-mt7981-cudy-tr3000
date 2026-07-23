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
# 读取用户开关
# ============================================================
ENABLE_MIHOMO="${ENABLE_MIHOMO:-false}"
ENABLE_ADGUARDHOME="${ENABLE_ADGUARDHOME:-false}"

echo "=========================================="
echo "📋 集成开关状态："
echo "   集成 mihomo: ${ENABLE_MIHOMO}"
echo "   集成 AdGuardHome: ${ENABLE_ADGUARDHOME}"
echo "=========================================="

# ============================================================
# 获取最新版本号
# ============================================================
get_latest_tag() {
    local REPO=$1
    local API_URL="https://api.github.com/repos/${REPO}/releases/latest"
    
    echo "📡 获取 ${REPO} 最新版本..." >&2
    local TAG=$(wget -q -O- "$API_URL" | grep -o '"tag_name": "[^"]*"' | sed 's/"tag_name": "//;s/"//')
    
    if [ -n "$TAG" ]; then
        echo "✅ 最新版本: ${TAG}" >&2
        echo "$TAG"
        return 0
    else
        echo "⚠️ 获取失败" >&2
        return 1
    fi
}


# ============================================================
# 函数1: 集成 mihomo 内核 (OpenClash)
# ============================================================
integrate_mihomo() {
    echo "=========================================="
    echo "📦 开始集成 mihomo 内核 (OpenClash)"
    echo "=========================================="
    
    mkdir -p files/etc/openclash/core
    
    local KERNEL_PATH="files/etc/openclash/core/clash_meta"
    
    # 获取最新版本
    local VERSION=$(get_latest_tag "MetaCubeX/mihomo")
    if [ -z "$VERSION" ]; then
        VERSION="v1.19.29"
        echo "⚠️ 使用默认版本: ${VERSION}" >&2
    fi
    
    local FILE_NAME="mihomo-linux-arm64-${VERSION}.gz"
    local DOWNLOAD_URL="https://github.com/MetaCubeX/mihomo/releases/download/${VERSION}/${FILE_NAME}"
    
    echo "📥 下载 mihomo: ${VERSION}"
    echo "   URL: $DOWNLOAD_URL"
    
    if wget -q -O /tmp/mihomo.gz "$DOWNLOAD_URL"; then
        gunzip -c /tmp/mihomo.gz > "$KERNEL_PATH"
        chmod 755 "$KERNEL_PATH"
        upx --best --lzma "$KERNEL_PATH" 2>/dev/null || true
        echo "✅ mihomo 内核已集成到: $KERNEL_PATH"
        ls -lh "$KERNEL_PATH"
        rm -f /tmp/mihomo.gz
    else
        echo "❌ mihomo 内核下载失败"
        return 1
    fi
    
    echo "=========================================="
    return 0
}

# ============================================================
# 函数2: 偷梁换柱集成 AdGuardHome
# ============================================================
integrate_adguardhome() {
    echo "=========================================="
    echo "📦 开始集成 AdGuardHome"
    echo "=========================================="
    
    # ---- 第1步：克隆 LuCI 界面源码 (dev 分支) ----
    echo "📥 克隆 luci-app-adguardhome 源码 (dev 分支)..."
    if [ -d "package/luci-app-adguardhome" ]; then
        echo "⚠️ 目录已存在，删除后重新克隆..."
        rm -rf package/luci-app-adguardhome
    fi
    
    git clone --depth=1 -b dev https://github.com/stevenjoezhang/luci-app-adguardhome.git package/luci-app-adguardhome
    if [ $? -eq 0 ]; then
        echo "✅ LuCI 源码已克隆 (dev 分支) 到 package/luci-app-adguardhome"
    else
        echo "⚠️ 克隆失败，尝试用 master 分支..."
        git clone --depth=1 https://github.com/stevenjoezhang/luci-app-adguardhome.git package/luci-app-adguardhome
    fi
    
    # ---- 第2步：准备压缩版二进制文件 ----
    echo ""
    echo "📥 下载并压缩 AdGuardHome 二进制..."
    
    mkdir -p files/usr/bin/AdGuardHome
    
    # 获取最新版本
    local VERSION=$(get_latest_tag "AdguardTeam/AdGuardHome")
    if [ -z "$VERSION" ]; then
        VERSION="v0.107.78"
        echo "⚠️ 使用默认版本: ${VERSION}" >&2
    fi
    
    local DOWNLOAD_URL="https://github.com/AdguardTeam/AdGuardHome/releases/download/${VERSION}/AdGuardHome_linux_arm64.tar.gz"
    
    echo "📥 下载 AdGuardHome: ${VERSION}"
    echo "   URL: $DOWNLOAD_URL"
    
    if wget -q -O /tmp/AdGuardHome.tar.gz "$DOWNLOAD_URL"; then
        tar -xzf /tmp/AdGuardHome.tar.gz -C /tmp/
        
        upx --best --lzma /tmp/AdGuardHome/AdGuardHome 2>/dev/null || true
        echo "✅ 压缩完成，大小:"
        ls -lh /tmp/AdGuardHome/AdGuardHome
        
        cp /tmp/AdGuardHome/AdGuardHome files/usr/bin/AdGuardHome/AdGuardHome
        chmod 755 files/usr/bin/AdGuardHome/AdGuardHome
        
        echo "✅ 压缩版二进制已放到: files/usr/bin/AdGuardHome/AdGuardHome"
        
        rm -f /tmp/AdGuardHome.tar.gz
        rm -rf /tmp/AdGuardHome
    else
        echo "❌ AdGuardHome 二进制下载失败"
        return 1
    fi
    
    # ---- 第3步：尝试修改官方包的 Makefile ----
    echo ""
    echo "🔍 寻找官方 adguardhome 包 Makefile..."
    
    ADG_MAKEFILE=$(find feeds -name "Makefile" -path "*/adguardhome/*" 2>/dev/null | head -n1)
    
    if [ -n "$ADG_MAKEFILE" ]; then
        echo "🔍 找到 Makefile: $ADG_MAKEFILE"
        local VERSION_NUM=$(echo "$VERSION" | sed 's/^v//')
        sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=${VERSION_NUM}/g" "$ADG_MAKEFILE" 2>/dev/null || true
        echo "✅ 已修改 Makefile 版本号为: ${VERSION_NUM}"
    else
        echo "⚠️ 未找到官方 adguardhome 包"
    fi
    
    echo ""
    echo "=========================================="
    echo "✅ AdGuardHome 集成完成"
    echo "   版本: ${VERSION}"
    echo "   路径: files/usr/bin/AdGuardHome/AdGuardHome"
    echo "=========================================="
    return 0
}
# ============================================================
# 主执行流程: 依次调用两个独立函数
# ============================================================
echo ""
echo "🚀 开始执行集成任务..."
echo ""

if [ "$ENABLE_MIHOMO" = "true" ]; then
    integrate_mihomo
else
    echo "⏭️ 跳过 mihomo 内核集成 (ENABLE_MIHOMO=false)"
fi

if [ "$ENABLE_ADGUARDHOME" = "true" ]; then
    integrate_adguardhome
else
    echo "⏭️ 跳过 AdGuardHome 集成 (ENABLE_ADGUARDHOME=false)"
fi


echo ""
echo "=========================================="
echo "✅ 所有集成任务完成!"
echo "=========================================="
