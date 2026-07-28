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

MIHOMO_INTEGRATED=false
ADGUARDHOME_INTEGRATED=false

echo "=========================================="
echo "📋 集成开关状态："
echo "   集成 mihomo: ${ENABLE_MIHOMO}"
echo "   集成 AdGuardHome: ${ENABLE_ADGUARDHOME}"
echo "   小巧思: ${ENABLE_TWEAKS}"
echo "=========================================="




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
        local STABLE_API="https://api.github.com/repos/MetaCubeX/mihomo/releases/latest"
        local STABLE_TAG=$(wget -q -O- "$STABLE_API" 2>/dev/null | grep -o '"tag_name": "[^"]*"' | sed 's/"tag_name": "//;s/"//')
        
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
    
    MIHOMO_INTEGRATED=false
    
    if wget -q -O /tmp/mihomo.gz "$DOWNLOAD_URL"; then
        gunzip -c /tmp/mihomo.gz > "$KERNEL_PATH"
        chmod 755 "$KERNEL_PATH"
        upx --best --lzma "$KERNEL_PATH" 2>/dev/null || true
        echo "✅ mihomo 内核已集成到: $KERNEL_PATH"
        ls -lh "$KERNEL_PATH"
        rm -f /tmp/mihomo.gz
        MIHOMO_INTEGRATED=true
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
            MIHOMO_INTEGRATED=true
            VERSION="${FALLBACK_TAG} (回退)"
        else
            echo "❌ mihomo 内核下载失败"
            echo "   → 用户可在 OpenClash 中手动上传或在线下载内核"
            MIHOMO_INTEGRATED=false
        fi
    fi

    echo ""
    echo "=========================================="
    echo "✅ 集成完成"
    echo ""
    
    if [ "$MIHOMO_INTEGRATED" = "true" ]; then
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
    
    ADGUARDHOME_INTEGRATED=false
    
    if grep -q "CONFIG_PACKAGE_adguardhome=y" .config; then
        echo "✅ 检测到官方源提供的 adguardhome 包已启用"
        echo "   → 跳过压缩版集成"
        ADGUARDHOME_INTEGRATED=true
        echo ""
        echo "💡 如果要使用压缩版，请在 .config 中确保："
        echo "   CONFIG_PACKAGE_adguardhome is not set"
        echo ""
        echo "=========================================="
        echo "✅ AdGuardHome 集成完成 (官方包)"
        echo "=========================================="
        return 0
    fi



    # ---- 第2步：准备压缩版二进制文件 ----
    echo "⚠️ 官方 adguardhome 包未启用"
    echo "📥 下载并压缩 AdGuardHome 二进制..."
    
    mkdir -p files/usr/bin/AdGuardHome
    
    local DOWNLOAD_URL="https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_arm64.tar.gz"
    local FALLBACK_URL="https://github.com/AdguardTeam/AdGuardHome/releases/download/v0.107.78/AdGuardHome_linux_arm64.tar.gz"
    
    echo "📥 下载 AdGuardHome (latest)"
    echo "   URL: $DOWNLOAD_URL"
    
    if wget -q -O /tmp/AdGuardHome.tar.gz "$DOWNLOAD_URL"; then
        tar -xzf /tmp/AdGuardHome.tar.gz -C /tmp/
        
        upx --best --lzma /tmp/AdGuardHome/AdGuardHome 2>/dev/null || true
        echo "✅ 压缩完成，大小:"
        ls -lh /tmp/AdGuardHome/AdGuardHome
        
        cp /tmp/AdGuardHome/AdGuardHome files/usr/bin/AdGuardHome/AdGuardHome
        chmod 755 files/usr/bin/AdGuardHome/AdGuardHome
        
        echo "✅ 压缩版二进制已放到: files/usr/bin/AdGuardHome/AdGuardHome"
        ADGUARDHOME_INTEGRATED=true
        
        rm -f /tmp/AdGuardHome.tar.gz
        rm -rf /tmp/AdGuardHome
    else
        echo "⚠️ latest 下载失败，尝试回退到 v0.107.78..."
        
        if wget -q -O /tmp/AdGuardHome.tar.gz "$FALLBACK_URL"; then
            tar -xzf /tmp/AdGuardHome.tar.gz -C /tmp/
            
            upx --best --lzma /tmp/AdGuardHome/AdGuardHome 2>/dev/null || true
            echo "✅ 压缩完成，大小:"
            ls -lh /tmp/AdGuardHome/AdGuardHome
            
            cp /tmp/AdGuardHome/AdGuardHome files/usr/bin/AdGuardHome/AdGuardHome
            chmod 755 files/usr/bin/AdGuardHome/AdGuardHome
            
            echo "✅ 回退到 v0.107.78 下载成功"
            echo "✅ 压缩版二进制已放到: files/usr/bin/AdGuardHome/AdGuardHome"
            ADGUARDHOME_INTEGRATED=true
            
            rm -f /tmp/AdGuardHome.tar.gz
            rm -rf /tmp/AdGuardHome
        else
            echo "❌ AdGuardHome 二进制下载失败"
            echo "   → 用户可手动上传 AdGuardHome 二进制"
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
# 函数3: 小巧思 (OpenClash预设 + AdGuardHome配置 + UPnP启用)
# ============================================================
apply_tweaks() {
    echo "=========================================="
    echo "✨ 开始应用小巧思"
    echo "=========================================="

    # --- 小巧思1: OpenClash 预设配置 + 面板更新 + rc.local ---
    if grep -q "CONFIG_PACKAGE_luci-app-openclash=y" .config 2>/dev/null; then
        echo ""
        echo "🔧 小巧思1: luci-app-openclash 已启用"

        # 写入 OpenClash 默认 UCI 配置
        local OPENCLASH_CONFIG="files/etc/config/openclash"
        mkdir -p files/etc/config

        if [ -f "$OPENCLASH_CONFIG" ]; then
            echo "   检测到已有 openclash 配置文件，追加/覆盖选项"
        else
            echo "   创建 openclash 配置文件"
            echo "config openclash 'config'" > "$OPENCLASH_CONFIG"
        fi

        # 设置各项 UCI 选项（追加或覆盖）
        set_uci_option() {
            local FILE="$1"
            local OPTION="$2"
            local VALUE="$3"
            if grep -q "option ${OPTION} " "$FILE" 2>/dev/null; then
                sed -i "s/option ${OPTION} .*/option ${OPTION} '${VALUE}'/" "$FILE"
            else
                echo "	option ${OPTION} '${VALUE}'" >> "$FILE"
            fi
        }

        set_uci_option "$OPENCLASH_CONFIG" default_dashboard zashboard
        set_uci_option "$OPENCLASH_CONFIG" delay_start 5
        set_uci_option "$OPENCLASH_CONFIG" small_flash_memory 1
        set_uci_option "$OPENCLASH_CONFIG" skip_proxy_address 1
        set_uci_option "$OPENCLASH_CONFIG" china_ip_route 1
        set_uci_option "$OPENCLASH_CONFIG" enable_redirect_dns 1
        set_uci_option "$OPENCLASH_CONFIG" en_mode fake-ip-mix
        set_uci_option "$OPENCLASH_CONFIG" operation_mode fake-ip-mix

        # 覆写设置
        set_uci_option "$OPENCLASH_CONFIG" enable_tcp_concurrent 1
        set_uci_option "$OPENCLASH_CONFIG" enable_unified_delay 1
        set_uci_option "$OPENCLASH_CONFIG" find_process_mode off
        set_uci_option "$OPENCLASH_CONFIG" geodata_loader memconservative
        set_uci_option "$OPENCLASH_CONFIG" enable_meta_sniffer 1
        set_uci_option "$OPENCLASH_CONFIG" enable_meta_sniffer_pure_ip 1
        set_uci_option "$OPENCLASH_CONFIG" smart_prefer_asn 1
        set_uci_option "$OPENCLASH_CONFIG" enable_respect_rules 1
        set_uci_option "$OPENCLASH_CONFIG" store_fakeip 1

        echo "✅ OpenClash 预设配置已写入:"
        echo "   - 面板: Zashboard"
        echo "   - 延迟启动: 5s"
        echo "   - 小闪存模式: 开启"
        echo "   - 绕过服务器地址: 开启"
        echo "   - 绕过中国大陆 IP: 开启"
        echo "   - 本地 DNS 劫持: Dnsmasq 转发"
        echo "   - 运行模式: Fake-IP + TUN 混合"
        echo "   - TCP 并发: 开启"
        echo "   - 统一延迟: 开启"
        echo "   - 进程规则: OFF"
        echo "   - Geodata 加载: 低内存模式"
        echo "   - 流量探测: 开启"
        echo "   - 嗅探纯 IP: 开启"
        echo "   - ASN 优先: 开启"
        echo "   - 遵循规则: 开启"
        echo "   - Fake-IP 持久化: 开启"

        # 下载最新 Zashboard 面板替换预置版本
        local ZASHBOARD_URL="https://github.com/Zephyruso/zashboard/releases/latest/download/dist-cdn-fonts.zip"
        local ZASHBOARD_DIR="files/usr/share/openclash/ui/zashboard"
        echo ""
        echo "📥 下载最新 Zashboard 面板 (CDN字体版)..."
        if wget -q -O /tmp/zashboard.zip "$ZASHBOARD_URL"; then
            rm -rf "$ZASHBOARD_DIR"
            mkdir -p "$ZASHBOARD_DIR"
            unzip -q -o /tmp/zashboard.zip -d "$ZASHBOARD_DIR"
            rm -f /tmp/zashboard.zip
            echo "✅ Zashboard 面板已更新到: $ZASHBOARD_DIR"
        else
            echo "⚠️ Zashboard 下载失败，将使用 OpenClash 预置版本"
            rm -f /tmp/zashboard.zip
        fi

        # 下载最新 Metacubexd 面板替换预置版本
        local METACUBEXD_URL="https://github.com/MetaCubeX/metacubexd/releases/latest/download/compressed-dist.tgz"
        local METACUBEXD_DIR="files/usr/share/openclash/ui/metacubexd"
        echo ""
        echo "📥 下载最新 Metacubexd 面板..."
        if wget -q -O /tmp/metacubexd.tgz "$METACUBEXD_URL"; then
            rm -rf "$METACUBEXD_DIR"
            mkdir -p "$METACUBEXD_DIR"
            tar -xzf /tmp/metacubexd.tgz -C "$METACUBEXD_DIR"
            rm -f /tmp/metacubexd.tgz
            echo "✅ Metacubexd 面板已更新到: $METACUBEXD_DIR"
        else
            echo "⚠️ Metacubexd 下载失败，将使用 OpenClash 预置版本"
            rm -f /tmp/metacubexd.tgz
        fi

        # 写入 rc.local: 开机自动复制内核到 /tmp (仅 mihomo 已集成时)
        if [ "$MIHOMO_INTEGRATED" = "true" ]; then
            mkdir -p files/etc
            if [ ! -f files/etc/rc.local ]; then
                cat > files/etc/rc.local << 'RCEOF'
#!/bin/sh
# OpenWrt rc.local - executed at boot

# 小巧思: 小闪存模式下自动复制 mihomo 内核到 /tmp
if [ -f /etc/openclash/core/clash_meta ]; then
    if uci -q get openclash.config.small_flash_memory | grep -q '1'; then
        mkdir -p /tmp/etc/openclash/core
        cp /etc/openclash/core/clash_meta /tmp/etc/openclash/core/
    fi
fi

exit 0
RCEOF
                chmod 755 files/etc/rc.local
            else
                if ! grep -q "small_flash_memory" files/etc/rc.local 2>/dev/null; then
                    sed -i '/^exit 0/i\
# 小巧思: 小闪存模式下自动复制 mihomo 内核到 /tmp\
if [ -f /etc/openclash/core/clash_meta ]; then\
    if uci -q get openclash.config.small_flash_memory | grep -q '\''1'\''; then\
        mkdir -p /tmp/etc/openclash/core\
        cp /etc/openclash/core/clash_meta /tmp/etc/openclash/core/\
    fi\
fi' files/etc/rc.local
                fi
            fi
            echo "✅ rc.local 已写入 (开机自动复制内核到 /tmp)"
        fi
    else
        echo "⏭️ luci-app-openclash 未启用，跳过 OpenClash 预设"
    fi

    # --- 小巧思2: 写入预设 AdGuardHome 配置文件 ---
    if [ "$ADGUARDHOME_INTEGRATED" = "true" ] && grep -q "CONFIG_PACKAGE_luci-app-adguardhome=y" .config 2>/dev/null; then
        echo ""
        echo "🔧 小巧思2: AdGuardHome 内核已集成且 luci-app-adguardhome 已启用，从 Gist 下载预设配置文件"
        mkdir -p files/etc

        local GIST_URL="https://gist.github.com/cuddly-guacamole/dd77ff71ab181a5ea228d25bc728a6b6/raw/AdGuardHome.yaml"
        if wget -q -O files/etc/AdGuardHome.yaml "$GIST_URL"; then
            echo "✅ 预设配置文件已写入: files/etc/AdGuardHome.yaml"
        else
            echo "❌ 从 Gist 下载配置文件失败"
        fi
    else
        echo "⏭️ AdGuardHome 内核未集成或 luci-app-adguardhome 未启用，跳过预设配置文件"
    fi

    # --- 小巧思3: 自动启用 UPnP ---
    if grep -q "CONFIG_PACKAGE_luci-app-upnp=y" .config 2>/dev/null; then
        echo ""
        echo "🔧 小巧思3: 检测到 luci-app-upnp 已启用，自动开启 UPnP 服务"
        local UPNP_CONFIG="files/etc/config/upnpd"
        mkdir -p files/etc/config

        if [ -f "$UPNP_CONFIG" ]; then
            if grep -q "option enabled " "$UPNP_CONFIG" 2>/dev/null; then
                sed -i "s/option enabled .*/option enabled '1'/" "$UPNP_CONFIG"
            else
                sed -i '/config upnpd/a\\	option enabled '\''1'\''' "$UPNP_CONFIG"
            fi
        else
            cat > "$UPNP_CONFIG" << 'EOF'
config upnpd config
	option enabled '1'
	option enable_natpmp '1'
	option enable_upnp '1'
	option secure_mode '1'
	option log_output '0'
	option download '1024'
	option upload '512'
	option internal_iface 'lan'
	option port '5000'

config perm_rule
	option action    'allow'
	option ext_ports '1024-65535'
	option int_addr  '0.0.0.0/0'
	option int_ports '1024-65535'
	option comment   'Allow high ports'

config perm_rule
	option action    'deny'
	option ext_ports '0-65535'
	option int_addr  '0.0.0.0/0'
	option int_ports '0-65535'
	option comment   'Default deny'
EOF
        fi
        echo "✅ UPnP 服务已启用 (upnpd.config.enabled=1)"
    else
        echo "⏭️ luci-app-upnp 未启用，跳过 UPnP 配置"
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

if [ "$ENABLE_MIHOMO" = "true" ] && grep -q "CONFIG_PACKAGE_luci-app-openclash=y" .config 2>/dev/null; then
    integrate_mihomo
else
    echo "⏭️ 跳过 mihomo 内核集成 (需 ENABLE_MIHOMO=true 且 luci-app-openclash=y)"
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
echo ""
echo "📋 最终状态："
echo "   mihomo 内核:       $([ "$MIHOMO_INTEGRATED" = "true" ] && echo '已集成 ✅' || echo '未集成')"
echo "   AdGuardHome 内核:  $([ "$ADGUARDHOME_INTEGRATED" = "true" ] && echo '已集成 ✅' || echo '未集成')"
echo "=========================================="
