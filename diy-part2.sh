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
sed -i 's/192.168.6.1/192.168.10.1/g' package/base-files/files/bin/config_generate

# Modify default theme
#sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile

# Modify hostname
sed -i "/hostname='ImmortalWrt'/s/'ImmortalWrt'/'CUDY'/g" package/base-files/files/bin/config_generate

# 修改 MTK WiFi 默认配置
sed -i 's/ssid="ImmortalWrt-2.4G"/ssid="CUDY-2.4G"/g' package/mtk/applications/mtwifi-cfg/files/mtwifi.sh
sed -i 's/ssid="ImmortalWrt-5G"/ssid="CUDY-5G"/g' package/mtk/applications/mtwifi-cfg/files/mtwifi.sh

# 修改默认国家码为 AU
sed -i 's/set wireless.${dev}.country=CN/set wireless.${dev}.country=AU/g' package/mtk/applications/mtwifi-cfg/files/mtwifi.sh

# 修改默认信道为 auto
sed -i 's/channel="36"/channel="auto"/g' package/mtk/applications/mtwifi-cfg/files/mtwifi.sh

# 临时解决Rust问题
sed -i 's/ci-llvm=true/ci-llvm=false/g' feeds/packages/lang/rust/Makefile

# add date in output file name
sed -i -e '/^IMG_PREFIX:=/i BUILD_DATE := $(shell date +%Y%m%d)' \
       -e '/^IMG_PREFIX:=/ s/\($(SUBTARGET)\)/\1-$(BUILD_DATE)/' include/image.mk

# set ubi to 122M
# sed -i 's/model = "Cudy TR3000 v1 ubi 112M"/model = "Cudy TR3000 v1 ubi 122M"/g' target/linux/mediatek/dts/mt7981b-cudy-tr3000-v1-ubootmod.dts
# sed -i 's/reg = <0x5c0000 0x7000000>;/reg = <0x5c0000 0x7a40000>;/' target/linux/mediatek/dts/mt7981b-cudy-tr3000-v1-ubootmod.dts



# ============================================================
# 读取用户开关
# ============================================================
ENABLE_MIHOMO="${ENABLE_MIHOMO:-false}"
ENABLE_ADGUARDHOME="${ENABLE_ADGUARDHOME:-false}"
ENABLE_TWEAKS="${ENABLE_TWEAKS:-false}"

echo "=========================================="
echo "📋 集成开关状态："
echo "   集成 mihomo: ${ENABLE_MIHOMO}"
echo "   集成 AdGuardHome: ${ENABLE_ADGUARDHOME}"
echo "   小巧思: ${ENABLE_TWEAKS}"
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
# 函数1: 集成 mihomo
# ============================================================
integrate_mihomo() {
    echo "=========================================="
    echo "📦 开始集成 mihomo"
    echo "=========================================="

    echo ""
    echo "📥 下载 mihomo 内核..."
    
    mkdir -p files/etc/openclash/core
    local KERNEL_PATH="files/etc/openclash/core/clash_meta"
    local FALLBACK_TAG="v1.19.29"
    local DOWNLOAD_URL=""
    local VERSION=""
    
    # 优先级1: Alpha 预览版 (动态获取含短哈希的文件名)
    echo "🔍 [1/3] 尝试 Alpha 预览版..."
    local ALPHA_API="https://api.github.com/repos/MetaCubeX/mihomo/releases/tags/Prerelease-Alpha"
    local ALPHA_FILE=$(wget -q -O- "$ALPHA_API" 2>/dev/null | \
        grep -o '"name": *"mihomo-linux-arm64-alpha-[a-f0-9]*\.gz"' | \
        grep -o 'mihomo-linux-arm64-alpha-[a-f0-9]*\.gz')
    
    if [ -n "$ALPHA_FILE" ]; then
        DOWNLOAD_URL="https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/${ALPHA_FILE}"
        VERSION="Alpha"
        echo "✅ 获取到 Alpha 文件名: ${ALPHA_FILE}"
    else
        echo "⚠️ Alpha 版获取失败，尝试正式版..."
        
        # 优先级2: 正式版 (API获取最新tag)
        echo "🔍 [2/3] 尝试正式版..."
        local STABLE_TAG=$(get_latest_tag "MetaCubeX/mihomo")
        
        if [ -n "$STABLE_TAG" ]; then
            DOWNLOAD_URL="https://github.com/MetaCubeX/mihomo/releases/download/${STABLE_TAG}/mihomo-linux-arm64-${STABLE_TAG}.gz"
            VERSION="${STABLE_TAG}"
            echo "✅ 获取到正式版: ${STABLE_TAG}"
        else
            echo "⚠️ 正式版获取失败，回退到硬编码版本..."
            
            # 优先级3: 硬编码回退版本
            echo "🔍 [3/3] 回退到 ${FALLBACK_TAG}"
            DOWNLOAD_URL="https://github.com/MetaCubeX/mihomo/releases/download/${FALLBACK_TAG}/mihomo-linux-arm64-${FALLBACK_TAG}.gz"
            VERSION="${FALLBACK_TAG} (回退)"
        fi
    fi
    
    echo "📥 下载 mihomo: ${VERSION}"
    echo "   URL: $DOWNLOAD_URL"
    
    local KERNEL_DOWNLOAD_SUCCESS=false
    
    if wget -q -O /tmp/mihomo.gz "$DOWNLOAD_URL"; then
        gunzip -c /tmp/mihomo.gz > "$KERNEL_PATH"
        chmod 755 "$KERNEL_PATH"
        upx --best --lzma "$KERNEL_PATH" 2>/dev/null || true
        echo "✅ mihomo 内核已集成到: $KERNEL_PATH"
        ls -lh "$KERNEL_PATH"
        rm -f /tmp/mihomo.gz
        KERNEL_DOWNLOAD_SUCCESS=true
    else
        echo "⚠️ 下载失败，尝试回退到 ${FALLBACK_TAG}..."
        local FALLBACK_URL="https://github.com/MetaCubeX/mihomo/releases/download/${FALLBACK_TAG}/mihomo-linux-arm64-${FALLBACK_TAG}.gz"
        
        if wget -q -O /tmp/mihomo.gz "$FALLBACK_URL"; then
            gunzip -c /tmp/mihomo.gz > "$KERNEL_PATH"
            chmod 755 "$KERNEL_PATH"
            upx --best --lzma "$KERNEL_PATH" 2>/dev/null || true
            echo "✅ 回退到 ${FALLBACK_TAG} 下载成功"
            ls -lh "$KERNEL_PATH"
            rm -f /tmp/mihomo.gz
            KERNEL_DOWNLOAD_SUCCESS=true
            VERSION="${FALLBACK_TAG} (回退)"
        else
            echo "❌ mihomo 内核下载失败"
            echo "   → 用户可在 OpenClash 中手动上传或在线下载内核"
            KERNEL_DOWNLOAD_SUCCESS=false
        fi
    fi

    echo ""
    echo "=========================================="
    echo "✅ 集成完成"
    echo ""
    
    if [ "$KERNEL_DOWNLOAD_SUCCESS" = "true" ]; then
        echo "   - mihomo 内核: 已集成 ✅"
        echo "   - 内核路径: $KERNEL_PATH"
        echo "   - 内核版本: ${VERSION}"
    else
        echo "   - mihomo 内核: 未集成（用户可手动上传）"
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
    

    echo ""
    echo "🔍 检测 .config 中 CONFIG_PACKAGE_adguardhome 状态..."
    
    if grep -q "CONFIG_PACKAGE_adguardhome=y" .config; then
        echo "✅ 检测到官方源提供的 adguardhome 包已启用"
        echo "   → 跳过压缩版集成"
        echo ""
        echo "💡 如果要使用压缩版，请在 .config 中确保："
        echo "   CONFIG_PACKAGE_adguardhome is not set"
        echo "=========================================="
        return 0
    fi



    # ---- 第2步：准备压缩版二进制文件 ----
    echo "⚠️ 官方 adguardhome 包未启用"
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
        echo "⚠️ ${VERSION} 下载失败，尝试回退到 v0.107.78..."
        
        local FALLBACK_VERSION="v0.107.78"
        local FALLBACK_URL="https://github.com/AdguardTeam/AdGuardHome/releases/download/${FALLBACK_VERSION}/AdGuardHome_linux_arm64.tar.gz"
        
        if wget -q -O /tmp/AdGuardHome.tar.gz "$FALLBACK_URL"; then
            tar -xzf /tmp/AdGuardHome.tar.gz -C /tmp/
            
            upx --best --lzma /tmp/AdGuardHome/AdGuardHome 2>/dev/null || true
            echo "✅ 压缩完成，大小:"
            ls -lh /tmp/AdGuardHome/AdGuardHome
            
            cp /tmp/AdGuardHome/AdGuardHome files/usr/bin/AdGuardHome/AdGuardHome
            chmod 755 files/usr/bin/AdGuardHome/AdGuardHome
            
            echo "✅ 回退到 ${FALLBACK_VERSION} 下载成功"
            echo "✅ 压缩版二进制已放到: files/usr/bin/AdGuardHome/AdGuardHome"
            
            rm -f /tmp/AdGuardHome.tar.gz
            rm -rf /tmp/AdGuardHome
        else
            echo "❌ AdGuardHome 二进制下载失败"
            return 1
        fi
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
# 函数3: 小巧思 (开机复制mihomo内核到内存 + AdGuardHome预设配置)
# ============================================================
apply_tweaks() {
    echo "=========================================="
    echo "✨ 开始应用小巧思"
    echo "=========================================="

    # --- 小巧思1: 开机自动复制 mihomo 内核到 /tmp ---
    if [ "$ENABLE_MIHOMO" = "true" ]; then
        echo ""
        echo "🔧 小巧思1: 写入 rc.local 实现开机自动复制 mihomo 内核到内存"
        mkdir -p files/etc
        if [ ! -f files/etc/rc.local ]; then
            cat > files/etc/rc.local << 'RCEOF'
#!/bin/sh
# OpenWrt rc.local - executed at boot

mkdir -p /tmp/etc/openclash/core
cp /etc/openclash/core/clash_meta /tmp/etc/openclash/core/

exit 0
RCEOF
            chmod 755 files/etc/rc.local
        else
            if ! grep -q "clash_meta" files/etc/rc.local 2>/dev/null; then
                sed -i '/^exit 0/i mkdir -p /tmp/etc/openclash/core\ncp /etc/openclash/core/clash_meta /tmp/etc/openclash/core/' files/etc/rc.local
            fi
        fi
        echo "✅ 已写入 rc.local，开机将自动复制 mihomo 内核到 /tmp"
    else
        echo "⏭️ mihomo 未启用，跳过开机复制内核"
    fi

    # --- 小巧思2: 写入预设 AdGuardHome 配置文件 ---
    if grep -q "CONFIG_PACKAGE_luci-app-adguardhome=y" .config 2>/dev/null; then
        echo ""
        echo "🔧 小巧思2: 检测到 luci-app-adguardhome 已启用，从 Gist 下载预设配置文件"
        mkdir -p files/etc

        local GIST_URL="https://gist.github.com/cuddly-guacamole/dd77ff71ab181a5ea228d25bc728a6b6/raw/AdGuardHome.yaml"
        if wget -q -O files/etc/AdGuardHome.yaml "$GIST_URL"; then
            echo "✅ 预设配置文件已写入: files/etc/AdGuardHome.yaml"
        else
            echo "❌ 从 Gist 下载配置文件失败"
        fi
    else
        echo "⏭️ luci-app-adguardhome 未启用，跳过预设配置文件"
    fi

    echo ""
    echo "=========================================="
    echo "✅ 小巧思应用完成"
    echo "=========================================="
    return 0
}



# ============================================================
# 主执行流程: 依次调用各个函数
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

if [ "$ENABLE_TWEAKS" = "true" ]; then
    apply_tweaks
else
    echo "⏭️ 跳过小巧思 (ENABLE_TWEAKS=false)"
fi

echo ""
echo "=========================================="
echo "✅ 所有集成任务完成!"
echo "=========================================="
