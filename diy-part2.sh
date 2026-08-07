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

# 防御: 若 feeds 中自带 luci-app-openclash, 移除避免与 package/ 内克隆版本冲突
# (此脚本在 feeds update/install 之后执行, 此时的移除才是有效的)
rm -rf feeds/luci/luci-app-openclash 2>/dev/null || true

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
ENABLE_EASYTIER="${ENABLE_EASYTIER:-false}"
ENABLE_TWEAKS="${ENABLE_TWEAKS:-false}"

MIHOMO_INTEGRATED=false
ADGUARDHOME_INTEGRATED=false
EASYTIER_INTEGRATED=false

echo "=========================================="
echo "📋 集成开关状态："
echo "   集成 mihomo: ${ENABLE_MIHOMO}"
echo "   集成 AdGuardHome: ${ENABLE_ADGUARDHOME}"
echo "   集成 easytier: ${ENABLE_EASYTIER}"
echo "   小巧思: ${ENABLE_TWEAKS}"
echo "=========================================="



# ============================================================
# 公共工具函数
# ============================================================

# 获取 GitHub 仓库最新 release tag (失败返回空)
get_latest_tag() {
    local REPO="$1"
    wget -q -O- "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null | \
        grep -o '"tag_name": "[^"]*"' | sed 's/"tag_name": "//;s/"//'
}

# 确保 UPX 4.2.4 可用 (官方 easytier release 用 4.2.4 压缩, apt 的 upx-ucl 3.96 无法解包/校验 v4 格式)
UPX_BIN=""
ensure_upx() {
    [ -n "$UPX_BIN" ] && return 0
    if wget -q -O /tmp/upx.tar.xz "https://github.com/upx/upx/releases/download/v4.2.4/upx-4.2.4-amd64_linux.tar.xz"; then
        tar -xJf /tmp/upx.tar.xz -C /tmp/
        rm -f /tmp/upx.tar.xz
        UPX_BIN="/tmp/upx-4.2.4-amd64_linux/upx"
        chmod +x "$UPX_BIN"
        echo "✅ UPX 版本: $("$UPX_BIN" --version | head -1)"
    else
        echo "⚠️ UPX 4.2.4 下载失败, 回退系统 upx-ucl (3.96 可能无法校验官方压缩包)"
        rm -f /tmp/upx.tar.xz
        UPX_BIN="upx"
    fi
}

# UPX 校验/兜底压缩单个二进制 (返回 0 成功; 失败时保留原文件, 不中断构建)
# upx -t 退出码: 0=已压缩且正常, 2=未压缩(NotPacked), 1=其他错误(如格式不兼容)
upx_verify_or_compress() {
    local FILE="$1"
    local NAME
    NAME="$(basename "$FILE")"
    "$UPX_BIN" -t "$FILE" >/dev/null 2>&1
    local RET=$?
    if [ "$RET" -eq 0 ]; then
        echo "✅ ${NAME}: UPX 压缩包, 校验通过"
        return 0
    fi
    if [ "$RET" -eq 2 ]; then
        echo "⚠️ ${NAME}: 非 UPX 压缩, 尝试兜底压缩..."
        if "$UPX_BIN" --best --lzma "$FILE" >/dev/null 2>&1; then
            if "$UPX_BIN" -t "$FILE" >/dev/null 2>&1; then
                echo "✅ ${NAME}: 兜底 UPX 压缩成功, 校验通过"
                return 0
            fi
            echo "❌ ${NAME}: 兜底压缩后校验失败, 保留当前文件"
        else
            echo "⚠️ ${NAME}: UPX 压缩失败, 保留原始二进制 (功能不受影响)"
        fi
        return 1
    fi
    echo "⚠️ ${NAME}: UPX 无法校验 (可能已压缩但格式与当前 UPX 不兼容), 保留原文件"
    return 1
}

# 校验文件是否为有效 ELF 可执行文件 (防 GitHub 限流返回 HTML/JSON 造成假成功)
is_valid_elf() {
    local FILE="$1"
    [ -s "$FILE" ] && file -b "$FILE" | grep -qi "ELF.*executable"
}

# 设置 UCI 选项 (已存在则覆盖, 否则追加)
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

# 在指定 UCI section 内精准设置选项 (官方配置文件结构变化也能正确处理):
#   - 目标 section 内已有该 option → 仅替换该 section 内的那行, 不影响其他 section
#   - 目标 section 存在但没有该 option → 在 section 末尾插入
#   - 整个文件都没有目标 section (含空文件) → 在文件末尾追加新 section
set_section_option() {
    local FILE="$1"
    local SECTION="$2"
    local OPTION="$3"
    local VALUE="$4"
    if [ ! -f "$FILE" ]; then
        printf 'config %s\n\toption %s '\''%s'\''\n' "$SECTION" "$OPTION" "$VALUE" > "$FILE"
        return 0
    fi
    local TMP="${FILE}.tmp"
    awk -v section="$SECTION" -v opt="$OPTION" -v val="$VALUE" '
        $1 == "config" {
            if (in_sec && !found) {
                printf "\toption %s '\''%s'\''\n", opt, val
            }
            in_sec = ($2 == section)
            if (in_sec) saw_section = 1
            print
            next
        }
        in_sec && $1 == "option" && $2 == opt {
            found = 1
            printf "\toption %s '\''%s'\''\n", opt, val
            next
        }
        { print }
        END {
            if (in_sec && !found) {
                printf "\toption %s '\''%s'\''\n", opt, val
            }
            if (!saw_section) {
                printf "config %s\n\toption %s '\''%s'\''\n", section, opt, val
            }
        }
    ' "$FILE" > "$TMP" && mv "$TMP" "$FILE"
}

# 校验某 UCI 文件的目标 section 内是否已有指定 option (返回 0 存在)
section_has_option() {
    local FILE="$1"
    local SECTION="$2"
    local OPTION="$3"
    [ -f "$FILE" ] || return 1
    awk -v section="$SECTION" -v opt="$OPTION" '
        $1 == "config" && $2 == section { s = 1; next }
        s && $1 == "config" { s = 0 }
        s && $1 == "option" && $2 == opt { f = 1 }
        END { exit (f ? 0 : 1) }
    ' "$FILE"
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
    local FALLBACK_URL="https://github.com/MetaCubeX/mihomo/releases/download/${FALLBACK_TAG}/mihomo-linux-arm64-${FALLBACK_TAG}.gz"
    local VERSION=""
    local URL=""
    
    # 优先级1: Alpha 预览版 (动态获取含短哈希的文件名)
    echo "🔍 [1/3] 尝试 Alpha 预览版..."
    local ALPHA_FILE
    ALPHA_FILE=$(wget -q -O- "https://api.github.com/repos/MetaCubeX/mihomo/releases/tags/Prerelease-Alpha" 2>/dev/null | \
        grep -o '"name": *"mihomo-linux-arm64-alpha-[a-f0-9]*\.gz"' | \
        grep -o 'mihomo-linux-arm64-alpha-[a-f0-9]*\.gz')
    
    if [ -n "$ALPHA_FILE" ]; then
        URL="https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/${ALPHA_FILE}"
        VERSION="Alpha"
        echo "✅ 获取到 Alpha 文件名: ${ALPHA_FILE}"
    else
        # 优先级2: 正式版 (API获取最新tag)
        echo "⚠️ Alpha 版获取失败, 尝试正式版..."
        echo "🔍 [2/3] 尝试正式版..."
        local STABLE_TAG
        STABLE_TAG="$(get_latest_tag "MetaCubeX/mihomo")"
        if [ -n "$STABLE_TAG" ]; then
            URL="https://github.com/MetaCubeX/mihomo/releases/download/${STABLE_TAG}/mihomo-linux-arm64-${STABLE_TAG}.gz"
            VERSION="${STABLE_TAG}"
            echo "✅ 获取到正式版: ${STABLE_TAG}"
        else
            # 优先级3: 硬编码回退版本
            echo "🔍 [3/3] 回退到 ${FALLBACK_TAG}"
            URL="$FALLBACK_URL"
            VERSION="${FALLBACK_TAG} (回退)"
        fi
    fi
    
    echo "📥 下载 mihomo: ${VERSION}"
    echo "   URL: $URL"
    
    MIHOMO_INTEGRATED=false
    
    # 候选地址列表 (已在回退版本时不再重复回退)
    local URL_LIST="$URL"
    if [ "$URL" != "$FALLBACK_URL" ]; then
        URL_LIST="${URL_LIST} ${FALLBACK_URL}"
    fi
    
    local TRY_URL
    local TRY_NUM=0
    for TRY_URL in $URL_LIST; do
        TRY_NUM=$((TRY_NUM + 1))
        if [ "$TRY_NUM" -gt 1 ]; then
            VERSION="${FALLBACK_TAG} (回退)"
            echo "⚠️ 主地址下载失败, 回退到 ${FALLBACK_TAG}..."
        fi
        
        if ! wget -q -O /tmp/mihomo.gz "$TRY_URL"; then
            echo "   ⚠️ 下载失败: $TRY_URL"
            continue
        fi
        
        # 解压 + 内容有效性校验 (防限流返回 HTML 造成假成功)
        if ! gunzip -c /tmp/mihomo.gz > "$KERNEL_PATH" 2>/dev/null; then
            echo "❌ 解压失败 (内容不是有效 gz, 可能被 GitHub 限流)"
            rm -f /tmp/mihomo.gz "$KERNEL_PATH"
            continue
        fi
        rm -f /tmp/mihomo.gz
        if ! is_valid_elf "$KERNEL_PATH"; then
            echo "❌ 内容校验失败 (不是有效 ELF 可执行文件, 可能被 GitHub 限流)"
            rm -f "$KERNEL_PATH"
            continue
        fi
        
        chmod 755 "$KERNEL_PATH"
        ensure_upx
        upx_verify_or_compress "$KERNEL_PATH" || true
        
        echo "✅ mihomo 内核已集成到: $KERNEL_PATH"
        ls -lh "$KERNEL_PATH"
        MIHOMO_INTEGRATED=true
        break
    done
    
    if [ "$MIHOMO_INTEGRATED" != "true" ]; then
        echo "❌ mihomo 内核下载失败"
        echo "   → 用户可在 OpenClash 中手动上传或在线下载内核"
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
        echo "   - mihomo 内核: 未集成 (用户可手动上传)"
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
    
    if grep -q "CONFIG_PACKAGE_adguardhome=y" .config 2>/dev/null; then
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

    echo "⚠️ 官方 adguardhome 包未启用"
    echo "📥 下载并压缩 AdGuardHome 二进制..."
    
    mkdir -p files/usr/bin/AdGuardHome
    
    local DOWNLOAD_URL="https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_arm64.tar.gz"
    local FALLBACK_URL="https://github.com/AdguardTeam/AdGuardHome/releases/download/v0.107.78/AdGuardHome_linux_arm64.tar.gz"
    
    # 解析最新版本号用于显式日志 (二进制为 arm64, 无法在 x86_64 构建机上运行验证)
    local VERSION
    VERSION="$(get_latest_tag "AdguardTeam/AdGuardHome")"
    [ -z "$VERSION" ] && VERSION="v0.107.78"
    
    local TRY_URL
    local TRY_NUM=0
    for TRY_URL in "$DOWNLOAD_URL" "$FALLBACK_URL"; do
        TRY_NUM=$((TRY_NUM + 1))
        if [ "$TRY_NUM" -eq 1 ]; then
            echo "📥 下载 AdGuardHome (${VERSION})"
        else
            VERSION="${VERSION} (回退)"
            echo "⚠️ 主地址下载失败, 回退到 ${VERSION}..."
        fi
        echo "   URL: $TRY_URL"
        
        if ! wget -q -O /tmp/AdGuardHome.tar.gz "$TRY_URL"; then
            echo "   ⚠️ 下载失败: $TRY_URL"
            continue
        fi
        
        rm -rf /tmp/AdGuardHome
        if ! tar -xzf /tmp/AdGuardHome.tar.gz -C /tmp/; then
            echo "❌ 解压失败 (内容不是有效 tar.gz, 可能被 GitHub 限流)"
            rm -f /tmp/AdGuardHome.tar.gz
            continue
        fi
        rm -f /tmp/AdGuardHome.tar.gz
        
        if ! is_valid_elf /tmp/AdGuardHome/AdGuardHome; then
            echo "❌ 内容校验失败 (不是有效 ELF 可执行文件, 可能被 GitHub 限流)"
            rm -rf /tmp/AdGuardHome
            continue
        fi
        
        ensure_upx
        upx_verify_or_compress /tmp/AdGuardHome/AdGuardHome || true
        
        cp -f /tmp/AdGuardHome/AdGuardHome files/usr/bin/AdGuardHome/AdGuardHome
        chmod 755 files/usr/bin/AdGuardHome/AdGuardHome
        rm -rf /tmp/AdGuardHome
        
        echo "✅ 压缩版二进制已放到: files/usr/bin/AdGuardHome/AdGuardHome"
        ls -lh files/usr/bin/AdGuardHome/AdGuardHome
        ADGUARDHOME_INTEGRATED=true
        break
    done
    
    if [ "$ADGUARDHOME_INTEGRATED" != "true" ]; then
        echo "❌ AdGuardHome 二进制下载失败"
        echo "   → 用户可手动上传 AdGuardHome 二进制"
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
# 函数3: 集成 easytier (官方 release 已用 UPX 4.2.4 压缩, 此处校验 + 兜底压缩)
# 官方 CI: aarch64-unknown-linux-musl 静态二进制, 发布前已 upx --lzma --best
# ============================================================
integrate_easytier() {
    echo "=========================================="
    echo "📦 开始集成 easytier"
    echo "=========================================="

    local FALLBACK_TAG="v2.6.4"
    local ARCH="aarch64"
    local BIN_DIR="files/usr/bin"

    echo ""
    echo "🔍 获取 EasyTier 最新版本..."
    local TAG
    TAG="$(get_latest_tag "EasyTier/EasyTier")"
    if [ -z "$TAG" ]; then
        TAG="${FALLBACK_TAG}"
        echo "⚠️ GitHub API 获取失败, 回退到 ${FALLBACK_TAG}"
    else
        echo "✅ 最新版本: ${TAG}"
    fi

    local URL="https://github.com/EasyTier/EasyTier/releases/download/${TAG}/easytier-linux-${ARCH}-${TAG}.zip"
    echo "📥 下载 easytier (目标架构 ${ARCH}, 官方二进制已含 UPX 压缩)"
    echo "   URL: $URL"

    if ! wget -q -O /tmp/easytier.zip "$URL"; then
        echo "❌ easytier 下载失败"
        echo "   → 用户可通过 luci-app-easytier 上传程序或在线下载"
        return 1
    fi
    echo "✅ 下载成功"

    rm -rf /tmp/easytier && mkdir -p /tmp/easytier
    if ! unzip -o -q -j /tmp/easytier.zip -d /tmp/easytier; then
        echo "❌ 解压失败 (内容不是有效 zip, 可能被 GitHub 限流)"
        rm -f /tmp/easytier.zip
        rm -rf /tmp/easytier
        return 1
    fi
    rm -f /tmp/easytier.zip
    echo "📋 压缩包内容:"
    ls -lh /tmp/easytier/ | sed 's/^/   /'

    ensure_upx
    mkdir -p "$BIN_DIR"

    # 逐个处理: core / cli / web-embed (若有, 安装为 easytier-web)
    local PROCESSED=0
    local PAIR SRC DST
    for PAIR in "easytier-core:easytier-core" "easytier-cli:easytier-cli" "easytier-web-embed:easytier-web"; do
        SRC="/tmp/easytier/${PAIR%%:*}"
        DST="${PAIR##*:}"
        if [ ! -f "$SRC" ]; then
            echo "⏭️ 跳过 ${PAIR%%:*} (压缩包内不存在)"
            continue
        fi
        if ! is_valid_elf "$SRC"; then
            echo "❌ ${PAIR%%:*}: 内容校验失败 (不是有效 ELF 可执行文件), 跳过"
            continue
        fi
        cp -f "$SRC" "$BIN_DIR/$DST"
        chmod 755 "$BIN_DIR/$DST"

        upx_verify_or_compress "$BIN_DIR/$DST" || true

        echo "   类型: $(file -b "$BIN_DIR/$DST")"
        echo "   大小: $(ls -lh "$BIN_DIR/$DST" | awk '{print $5}')"
        PROCESSED=$((PROCESSED + 1))
    done

    if [ "$PROCESSED" -gt 0 ]; then
        EASYTIER_INTEGRATED=true
    else
        echo "❌ 没有可用的 easytier 二进制被集成"
    fi

    echo ""
    echo "=========================================="
    echo "✅ easytier 集成完成: ${TAG}"
    echo "   路径: $BIN_DIR/easytier-{core,cli,web}"
    echo "   ⚠️ 目标为 aarch64, 无法在 x86_64 构建机上直接运行验证, 已用 upx -t 校验完整性"
    echo "=========================================="
    return 0
}



# ============================================================
# 函数4: 小巧思 (OpenClash预设 + AdGuardHome配置 + UPnP启用)
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
            local RC_LOCAL="files/etc/rc.local"
            if [ ! -f "$RC_LOCAL" ]; then
                cat > "$RC_LOCAL" << 'RCEOF'
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
            else
                # 已有 rc.local: 未包含内核复制逻辑时插入
                if ! grep -q "small_flash_memory" "$RC_LOCAL" 2>/dev/null; then
                    local RC_BLOCK
                    RC_BLOCK='# 小巧思: 小闪存模式下自动复制 mihomo 内核到 /tmp
if [ -f /etc/openclash/core/clash_meta ]; then
    if uci -q get openclash.config.small_flash_memory | grep -q '\''1'\''; then
        mkdir -p /tmp/etc/openclash/core
        cp /etc/openclash/core/clash_meta /tmp/etc/openclash/core/
    fi
fi'
                    if grep -q "^exit 0" "$RC_LOCAL"; then
                        # 在 exit 0 之前插入
                        awk -v block="$RC_BLOCK" '
                            /^exit 0/ && !done { print block; done = 1 }
                            { print }
                        ' "$RC_LOCAL" > "$RC_LOCAL.tmp" && mv "$RC_LOCAL.tmp" "$RC_LOCAL"
                    else
                        # 无 exit 0: 末尾追加并补全
                        printf '\n%s\n\nexit 0\n' "$RC_BLOCK" >> "$RC_LOCAL"
                    fi
                fi
            fi
            chmod 755 "$RC_LOCAL"
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
            # 官方文件已存在: 仅在 config upnpd section 内精准修改, 不影响其他 section
            set_section_option "$UPNP_CONFIG" upnpd enabled 1
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

        # 校验生效 (防官方文件结构变化导致静默失效)
        if section_has_option "$UPNP_CONFIG" upnpd enabled; then
            echo "✅ UPnP 服务已启用 (upnpd.config.enabled=1)"
        else
            echo "⚠️ 写入后未检测到 upnpd section 的 enabled 选项, 请检查官方配置文件结构"
        fi
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

if [ "$ENABLE_EASYTIER" = "true" ]; then
    if grep -q "CONFIG_PACKAGE_easytier=y" .config 2>/dev/null; then
        echo "⏭️ 检测到官方 easytier 包已启用 (CONFIG_PACKAGE_easytier=y)"
        echo "   → 跳过压缩版集成, 避免 /usr/bin 文件冲突"
        EASYTIER_INTEGRATED=true
    else
        integrate_easytier
    fi
else
    echo "⏭️ 跳过 easytier 集成 (ENABLE_EASYTIER=false)"
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
echo "   easytier 内核:     $([ "$EASYTIER_INTEGRATED" = "true" ] && echo '已集成 ✅' || echo '未集成')"
echo "=========================================="
