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
# 上游默认 LAN 网段随分支变化: 24.10 分支为 192.168.6.1, 25.12 分支为 192.168.1.1
# 两种都替换, 并校验结果, 避免上游改默认值后静默失效
sed -i -e 's/192\.168\.6\.1/192.168.10.1/g' -e 's/192\.168\.1\.1/192.168.10.1/g' \
    package/base-files/files/bin/config_generate
if grep -q '192\.168\.10\.1' package/base-files/files/bin/config_generate; then
    echo "✅ 默认 LAN 网段已改为 192.168.10.1"
else
    echo "⚠️ 默认 LAN 网段替换未生效, 请检查上游 config_generate 结构"
fi

# Modify default theme
#sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile

# Modify hostname
sed -i "/hostname='ImmortalWrt'/s/'ImmortalWrt'/'CUDY'/g" package/base-files/files/bin/config_generate

# 修改 MTK WiFi 默认配置
# 25.12 起配置工具链由 Lua 重写为 ucode, 实际生效的是 mtwifi-cfg-ucode,
# 默认值位于 lib/wifi/mtwifi.uc; 旧 Lua 包已废弃, 一并处理以防上游回退。
MTWIFI_UC="package/mtk/applications/mtwifi-cfg-ucode/files/lib/wifi/mtwifi.uc"
MTWIFI_LUA="package/mtk/applications/mtwifi-cfg/files/mtwifi.sh"
MTWIFI_DONE=false

if [ -f "$MTWIFI_UC" ]; then
    sed -i -e 's/ssid: "ImmortalWrt-2.4G"/ssid: "CUDY-2.4G"/' \
           -e 's/ssid: "ImmortalWrt-5G"/ssid: "CUDY-5G"/' \
           -e 's/ssid: "ImmortalWrt-6G"/ssid: "CUDY-6G"/' \
           -e 's/"country": "CN"/"country": "AU"/' "$MTWIFI_UC"

    if grep -q 'CUDY-2.4G' "$MTWIFI_UC" && grep -q '"country": "AU"' "$MTWIFI_UC"; then
        echo "✅ MTK WiFi 默认 SSID / 国家码已修改 (ucode)"
        MTWIFI_DONE=true
    else
        echo "⚠️ ucode 版 mtwifi 默认值修改未完全生效, 请检查 $MTWIFI_UC 结构"
    fi
fi

if [ -f "$MTWIFI_LUA" ]; then
    sed -i -e 's/ssid="ImmortalWrt-2.4G"/ssid="CUDY-2.4G"/g' \
           -e 's/ssid="ImmortalWrt-5G"/ssid="CUDY-5G"/g' \
           -e 's/set wireless.${dev}.country=CN/set wireless.${dev}.country=AU/g' "$MTWIFI_LUA"

    if [ "$MTWIFI_DONE" = "false" ] && grep -q 'ssid="CUDY-2.4G"' "$MTWIFI_LUA"; then
        echo "✅ MTK WiFi 默认 SSID / 国家码已修改 (Lua)"
        MTWIFI_DONE=true
    fi
fi

if [ "$MTWIFI_DONE" = "false" ]; then
    echo "⚠️ 未找到可修改的 mtwifi 默认值文件, 跳过 MTK WiFi 默认值修改"
fi

# 默认信道: 上游 mtwifi 默认已是 channel=auto, 无需替换

# 防御: 若 feeds 中自带 luci-app-openclash, 移除避免与 package/ 内克隆版本冲突
# (此脚本在 feeds update/install 之后执行, 此时的移除才是有效的)
rm -rf feeds/luci/luci-app-openclash 2>/dev/null || true

# add date in output file name
sed -i -e '/^IMG_PREFIX:=/i BUILD_DATE := $(shell date +%Y%m%d)' \
       -e '/^IMG_PREFIX:=/ s/\($(SUBTARGET)\)/\1-$(BUILD_DATE)/' include/image.mk

# ubootmod 设备树: ubi 分区改回 112M, 并补回 NMBM + spi-cal 节点
#
# (1) 分区大小
# 上游 25.12 (含官方 openwrt/immortalwrt) 默认 reg = <0x5c0000 0x7a40000> 即 122M,
# 该值恰好占满整块 NAND 在 0x5c0000 之后的全部剩余空间 (128MiB - 5.75MiB = 122.25MiB),
# 没有任何坏块替换余量; 且本机 uboot 的 mtdparts 就是 112M, 分区不一致会导致刷入失败。
# 112M 保留 10.25MiB 余量, 与历史固件行为一致。
#
# (2) NMBM + spi-cal
# 上游 25.12 的 ubootmod 设备树删掉了整个 &spi_nand 节点, 而本机 uboot
# (Yuzhii0718 bl-mt798x-dhcpd, VARIANT=ubootmod) 的 NMBM 是开启的:
#   mtd list   -> 存在 nmbm0, 所有分区挂在 nmbm0 上
#   env print  -> mtdids=nmbm0=nmbm0, mtdparts=nmbm0:...,114688k(ubi)
#   启动日志   -> "Initializing NMBM ... NMBM has been successfully attached"
# uboot 在引导前会校验 Linux FDT 与自身 MTD 布局 / NMBM 模式是否一致, 不一致直接拒绝引导
# (表现为红灯闪烁后回到 failsafe WEBUI, 且 Initramfs 同样起不来)。
# 因此必须把该节点补回来, 与 padavanonly 24.10 分支上能正常启动的同名设备树保持一致。
UBOOTMOD_DTS="target/linux/mediatek/dts/mt7981b-cudy-tr3000-v1-ubootmod.dts"
if [ -f "$UBOOTMOD_DTS" ]; then
    sed -i 's/reg = <0x5c0000 0x7a40000>;/reg = <0x5c0000 0x7000000>;/' "$UBOOTMOD_DTS"

    if grep -q 'mediatek,nmbm;' "$UBOOTMOD_DTS"; then
        echo "ℹ️ ubootmod 设备树已含 NMBM 节点, 跳过注入"
    else
        awk '
            /^&ubi \{/ && !done {
                print "&spi_nand {"
                print "\tspi-cal-enable;"
                print "\tspi-cal-mode = \"read-data\";"
                print "\tspi-cal-datalen = <7>;"
                print "\tspi-cal-data = /bits/ 8 <0x53 0x50 0x49 0x4E 0x41 0x4E 0x44>;"
                print "\tspi-cal-addrlen = <5>;"
                print "\tspi-cal-addr = /bits/ 32 <0x0 0x0 0x0 0x0 0x0>;"
                print ""
                print "\tmediatek,nmbm;"
                print "\tmediatek,bmt-max-ratio = <1>;"
                print "\tmediatek,bmt-max-reserved-blocks = <64>;"
                print "};"
                print ""
                done = 1
            }
            { print }
        ' "$UBOOTMOD_DTS" > "$UBOOTMOD_DTS.tmp" && mv "$UBOOTMOD_DTS.tmp" "$UBOOTMOD_DTS"
    fi

    DTS_OK=1
    grep -q 'reg = <0x5c0000 0x7000000>;' "$UBOOTMOD_DTS" || { echo "⚠️ ubootmod ubi 分区替换未生效, 请检查上游设备树结构"; DTS_OK=0; }
    grep -q 'mediatek,nmbm;' "$UBOOTMOD_DTS"           || { echo "⚠️ ubootmod NMBM 节点注入未生效"; DTS_OK=0; }
    grep -q 'spi-cal-enable;' "$UBOOTMOD_DTS"          || { echo "⚠️ ubootmod spi-cal 注入未生效"; DTS_OK=0; }
    [ "$DTS_OK" = "1" ] && echo "✅ ubootmod 设备树已调整为 112M + NMBM + spi-cal"
else
    echo "⚠️ 未找到 $UBOOTMOD_DTS, 跳过 uboot 布局调整"
fi



# 移除 OpenClash 包内自带的 GeoSite.dat (约 9.9 MB)
# 固件按 mmdb 模式运行 (enable_geoip_dat=0), 不使用 geosite.dat;
# 若将来切回 dat 模式, OpenClash 会在运行时自行下载到 /etc/openclash/, 不影响功能。
OPENCLASH_GEOSITE="package/luci-app-openclash/root/etc/openclash/GeoSite.dat"
if [ -f "$OPENCLASH_GEOSITE" ]; then
    GEOSITE_MB=$(du -m "$OPENCLASH_GEOSITE" 2>/dev/null | cut -f1)
    rm -f "$OPENCLASH_GEOSITE"
    if [ -f "$OPENCLASH_GEOSITE" ]; then
        echo "⚠️ GeoSite.dat 移除失败, 请检查权限"
    else
        echo "✅ 已移除 OpenClash 内置 GeoSite.dat (省约 ${GEOSITE_MB:-10} MB)"
    fi
else
    echo "ℹ️ 未找到 $OPENCLASH_GEOSITE (上游可能已改名或移除)"
fi

# 预置 GeoIP / ASN 数据文件 (可选, 默认关闭)
#
# 背景: mihomo 在启动阶段就会拉取 geox 数据, 那时代理还没起来, 走的是直连。
# 因此 geox-url 必须指向国内可直连的地址 —— 见下方预设里的 jsdelivr CDN。
# 本函数只是备选方案: 若希望设备完全离线可用, 可在编译时把数据写进固件。
# 注意 jsdelivr 单文件上限 20 MB, geoip.dat 约 15.8 MB 已接近该上限。
#
# 文件名与 OpenClash 使用的路径一致 (见 init 脚本 ipdb_path / asn_path)。
# 下载失败时不写入, 保留包内自带的 lite 版作为兜底, 不影响构建。
GEO_DIR="files/etc/openclash"
GEO_MMDB_URL="https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/country.mmdb"
GEO_ASN_URL="https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/GeoLite2-ASN.mmdb"

prefetch_geodata() {
    local URL="$1" DST="$2" LABEL="$3" TMP="/tmp/geo_prefetch.tmp"
    rm -f "$TMP"
    if ! wget -q --timeout=30 --tries=2 -O "$TMP" "$URL"; then
        echo "⚠️ $LABEL 下载失败, 保留包内自带版本 (首次启动时会尝试在线下载)"
        rm -f "$TMP"; return 1
    fi
    # MaxMind DB 格式: 元数据段以 \xab\xcd\xef + "MaxMind.com" 结尾
    if ! grep -q -a "MaxMind.com" "$TMP"; then
        echo "⚠️ $LABEL 内容校验失败 (不是有效的 mmdb), 保留包内自带版本"
        rm -f "$TMP"; return 1
    fi
    local SIZE_MB
    SIZE_MB=$(du -m "$TMP" 2>/dev/null | cut -f1)
    mkdir -p "$GEO_DIR"
    mv -f "$TMP" "$GEO_DIR/$DST"
    echo "✅ 已预置 $LABEL -> $GEO_DIR/$DST (约 ${SIZE_MB:-?} MB)"
    return 0
}

# 默认关闭: geox-url 已指向 jsdelivr CDN, 首启动可直连下载 (实测 HTTP 200),
# 预置会把 15.8 MB 写进 flash 却没带来额外收益。
# 只有在希望设备完全离线可用 / CDN 不可信时, 才设 PREFETCH_GEODATA=true 打开。
PREFETCH_GEODATA="${PREFETCH_GEODATA:-false}"
if [ "$PREFETCH_GEODATA" = "true" ]; then
    if grep -q "CONFIG_PACKAGE_luci-app-openclash=y" .config 2>/dev/null; then
        prefetch_geodata "$GEO_MMDB_URL" "Country.mmdb" "GeoIP 库 (country.mmdb)" || true
        prefetch_geodata "$GEO_ASN_URL"  "ASN.mmdb"     "ASN 库 (GeoLite2-ASN.mmdb)" || true
    else
        echo "ℹ️ luci-app-openclash 未启用, 跳过 geodata 预置"
    fi
else
    echo "ℹ️ geodata 预置未开启 (PREFETCH_GEODATA=false), 由 mihomo 从 jsdelivr CDN 下载"
fi

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
#
# ⚠️ 慎用: 若把结果写进 files/etc/config/<pkg>, 会【整体覆盖】该包的默认配置。
# 包默认通常有几十项, 只写自己关心的几项会静默丢掉其余默认值 —— 这已经造成过
# 一次事故 (openclash 丢 proxy_mode 导致 mihomo 报 invalid mode 起不来)。
# 想覆盖包的默认值, 请改用 files/etc/uci-defaults/ 脚本做"叠加", 见
# apply_system_defaults() 与 apply_tweaks() 里 OpenClash 预设的写法。
set_uci_option() {
    local FILE="$1"
    local OPTION="$2"
    local VALUE="$3"
    # 值里可能含 / : 等字符 (例如 geodata 的 URL), 故改用 | 作 sed 分隔符,
    # 并把值中的 \ & | 转义, 避免破坏 sed 表达式。
    local ESC
    ESC=$(printf '%s' "$VALUE" | sed -e 's/[\\&|]/\\&/g')
    if grep -q "^[[:space:]]*option ${OPTION} " "$FILE" 2>/dev/null; then
        sed -i "s|^\([[:space:]]*option ${OPTION} \).*|\1'${ESC}'|" "$FILE"
    else
        printf "\toption %s '%s'\n" "$OPTION" "$VALUE" >> "$FILE"
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
    # 安全网: luci-app-adguardhome 未启用时直接跳过。
    # 配置中已禁用该包 (与 OpenClash 的 fake-ip + mihomo DNS 功能重叠, 且占 11-13 MB),
    # 没有 UI 的情况下再打包二进制没有意义。
    if ! grep -q "CONFIG_PACKAGE_luci-app-adguardhome=y" .config 2>/dev/null; then
        echo "⏭️ luci-app-adguardhome 未启用, 跳过 AdGuardHome 集成"
        return 0
    fi

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

    # 只装 core + cli。
    # easytier-web 是独立的 Web 控制台 (来自 easytier-web-embed, UPX 后单独占 6.2 MB),
    # LuCI 的 init 脚本本来也只搬 core 与 cli 两个, 不依赖它;
    # 上游另提供 easytier-noweb 包变体, 做法与此一致。
    local PROCESSED=0
    local PAIR SRC DST
    for PAIR in "easytier-core:easytier-core" "easytier-cli:easytier-cli"; do
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

        # OpenClash 预设: 用 uci-defaults 叠加, 不写 files/etc/config/openclash
        #
        # 为什么不能写 files/etc/config/openclash:
        # 该文件会整体覆盖包自带的 /etc/config/openclash, 而包默认包含 63 个
        # option + 40 个 dns_servers + 2 个 config_overwrite。只写我们关心的
        # 十几项会把这些默认全部丢掉, 实测已造成事故:
        #   openclash.config.proxy_mode 丢失
        #   -> init.d/openclash 把它作为第 10 个参数传给 yml_change.sh
        #   -> yml_change.sh: mode = '${10}' 写入 mihomo 的 mode
        #   -> 生成 mode: '' , 核心报 "Parse config error: invalid mode" 无法启动
        # 同时丢失的还有 http_port / socks_port / mixed_port / proxy_port /
        # tproxy_port / enable_udp_proxy / intranet_allowed / log_level 等。
        #
        # 改用 uci-defaults 在首次启动时"叠加"设置, 包默认值全部保留。
        #
        # ⚠️ 文件名必须以 zz- 开头, 不能是 99-:
        #    /etc/init.d/boot 的 uci_apply_defaults() 实现是
        #        files="$(ls)"; for file in $files; do ( . "./$(basename $file)" ); done
        #    即按【字典序】依次 source。OpenClash 自己的脚本叫 luci-openclash,
        #    它会在其中生成随机的 @authentication 密码与 dashboard_password。
        #    若我们排在它前面 (原名 99-openclash-preset), 它随后又会重新生成,
        #    禁用就失效了。改成 zz- 前缀可保证最后执行, 覆盖掉它生成的随机值。
        local OPENCLASH_DEFAULTS="files/etc/uci-defaults/zz-openclash-preset"
        mkdir -p files/etc/uci-defaults
        {
            echo '#!/bin/sh'
            echo '# 由 diy-part2.sh 生成 —— OpenClash 预设'
            echo '# 只 set 需要覆盖的项, 其余保留包 /etc/config/openclash 的默认值'
            echo '# zz- 前缀用于排在 luci-openclash 之后执行 (原因见 diy-part2.sh 注释)'
            echo ''
        } > "$OPENCLASH_DEFAULTS"

        oc_set() {
            echo "uci -q set openclash.config.$1='$2'" >> "$OPENCLASH_DEFAULTS"
        }

        # 显式固定代理模式: 它是 init 脚本传给 yml_change.sh 的第 10 个参数,
        # 最终成为 mihomo 的 mode, 缺失或非法会直接导致核心启动失败。
        oc_set proxy_mode rule
        oc_set default_dashboard zashboard
        oc_set delay_start 5
        # 小闪存模式会把 mihomo 内核复制到 /tmp 常驻内存 (十几 MB),
        # 收益仅在更新内核时体现, 而代价是持续占用 RAM, 故关闭
        oc_set small_flash_memory 0
        oc_set skip_proxy_address 1
        oc_set china_ip_route 1
        oc_set enable_redirect_dns 1
        oc_set en_mode fake-ip-mix
        oc_set operation_mode fake-ip-mix

        # 覆写设置
        oc_set enable_tcp_concurrent 1
        oc_set enable_unified_delay 1
        oc_set find_process_mode off
        oc_set geodata_loader memconservative
        # geodata 走 mmdb 模式: enable_geoip_dat=0 时不会写入 geodata-mode,
        # 即不使用体积巨大的 geosite.dat / geoip.dat, 改用 Country.mmdb + ASN mmdb。
        # 配合下方移除包内自带的 GeoSite.dat (9.9 MB)。
        oc_set enable_geoip_dat 0
        # 走 jsdelivr CDN 而非 github release: release 资产要经 github 重定向链,
        # 国内直连(首启动时代理尚未起来)经常失败; jsdelivr 可直连 (实测 HTTP 200)。
        # MetaCubeX/meta-rules-dat 的 release 分支同时提供 mmdb 与 ASN 文件。
        oc_set geo_custom_url "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/country.mmdb"
        oc_set geoasn_custom_url "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/GeoLite2-ASN.mmdb"
        oc_set enable_meta_sniffer 1
        oc_set enable_meta_sniffer_pure_ip 1
        oc_set smart_prefer_asn 1
        oc_set enable_respect_rules 1
        # fakeip 缓存不持久化, 避免周期性写闪存 (重启后重建映射)
        oc_set store_fakeip 0

        # 仅内网可访问管理端口 (显式固定为默认值)
        # LuCI 原文: "Only intranet allowed" —— When Enabled, The Control Panel
        # And The Connection Broker Port Will Not Be Accessible From The Public
        # Network。即 1 = 挡公网、只留内网; 设 0 反而会开放到公网, 不要改。
        oc_set intranet_allowed 1

        # 关闭 OpenClash 首次启动时随机生成的代理认证与面板密码。
        # 生成位置 root/etc/uci-defaults/luci-openclash:
        #   if [ -z "$(uci_get_config "dashboard_password")" ]; then  ...随机 8 位...  fi
        #   if [ -z "$(uci -q get openclash.@authentication[0])" ]; then 建段+随机密码 fi
        # 两处都有 -z 守卫 (只在值为空时生成), 而本脚本排在它之后执行(zz-),
        # 所以这里的赋值是最终值, 不会被重新生成。
        {
            echo ''
            echo '# 代理认证: 关闭 (保留条目, 仅置 enabled=0; 两个消费点都要求 enabled=="1")'
            echo '[ -n "$(uci -q get openclash.@authentication[0])" ] || uci -q add openclash authentication'
            echo "uci -q set openclash.@authentication[0].enabled='0'"
            echo ''
            echo '# 面板密码 (mihomo secret): 置空即不校验'
            echo "uci -q set openclash.config.dashboard_password=''"
        } >> "$OPENCLASH_DEFAULTS"

        echo 'uci -q commit openclash' >> "$OPENCLASH_DEFAULTS"
        echo 'exit 0' >> "$OPENCLASH_DEFAULTS"
        chmod 755 "$OPENCLASH_DEFAULTS"

        if [ "$(grep -c "^uci -q set openclash" "$OPENCLASH_DEFAULTS")" -ge 15 ] \
           && grep -q "openclash.config.proxy_mode='rule'" "$OPENCLASH_DEFAULTS" \
           && grep -q "openclash.@authentication\[0\].enabled='0'" "$OPENCLASH_DEFAULTS" \
           && grep -q "openclash.config.dashboard_password=''" "$OPENCLASH_DEFAULTS"; then
            echo "✅ OpenClash 预设已生成: $OPENCLASH_DEFAULTS"
            echo "   (含关闭随机生成的代理认证与面板密码)"
        else
            echo "⚠️ OpenClash 预设生成异常, 请检查 $OPENCLASH_DEFAULTS"
        fi

        echo "✅ OpenClash 预设配置已写入:"
        echo "   - 面板: Zashboard"
        echo "   - 延迟启动: 5s"
        echo "   - 代理模式: rule (proxy_mode, 缺失会导致核心报 invalid mode)"
        echo "   - 小闪存模式: 关闭 (省十几 MB 常驻内存)"
        echo "   - 绕过服务器地址: 开启"
        echo "   - 绕过中国大陆 IP: 开启"
        echo "   - 本地 DNS 劫持: Dnsmasq 转发"
        echo "   - 运行模式: Fake-IP + TUN 混合"
        echo "   - TCP 并发: 开启"
        echo "   - 统一延迟: 开启"
        echo "   - 进程规则: OFF"
        echo "   - Geodata 加载: 低内存模式"
        echo "   - Geodata 模式: mmdb (Country.mmdb + ASN), 非 dat"
        echo "   - Geodata 源: MetaCubeX/meta-rules-dat"
        echo "   - 流量探测: 开启"
        echo "   - 嗅探纯 IP: 开启"
        echo "   - ASN 优先: 开启"
        echo "   - 遵循规则: 开启"
        echo "   - Fake-IP 持久化: 关闭 (不写闪存)"
        echo "   - 仅内网可访问管理端口: 开启 (intranet_allowed=1, 挡公网)"
        echo "   - 代理认证 / 面板密码: 已关闭 (不再随机生成)"

        # --- 小巧思1b: 拉长 watchdog 里「跳过代理地址」的刷新间隔 ---
        #
        # 背景 (实测数据, 2026-10-09):
        #   openclash_watchdog.sh 主循环末尾是 sleep 60, 而脚本头部写着
        #       SKIP_PROXY_ADDRESS_INTERVAL=30
        #   表示每 30 轮调用一次 skip_proxies_address():
        #       30 × 60s ≈ 31 分钟一次
        #   实测 loadmon 连续 8 轮尖峰间隔 30m53s~31m05s, 与推算完全吻合。
        #
        #   每次那 37 秒里它做的是: 用 ruby 加载 ~99KB YAML, 再对 35 个节点域名
        #   各做 A / AAAA 两次 DNS 查询 ——
        #       curl -s -m 3 http://127.0.0.1:$cn_port/dns/query | jsonfilter
        #   10 线程并发, 共 70 个 curl+jsonfilter 子进程。在 2 核 MT7981 上直接
        #   把 CPU 打满: 实测 idle 0% / 63% usr + 36% sys / 进程数 132 → 239 /
        #   load1 从 1.6 冲到 7.5~9.4, 并留下 60 个 [sh] 僵尸进程。
        #
        #   危害: 这 30 多秒里节点健康检查会失败 (clash API 直接返回
        #   "get delay: all proxies timeout"), DNS 与新建连接也会超时,
        #   是「掉登录态 / 游戏登录转圈」的诱因之一。
        #
        # 为什么不能直接关掉 skip_proxy_address:
        #   router_self_proxy=1 时, clash 核心自身到节点的出站连接会被
        #   nft 的 openclash_output 链 redirect 回它自己的 redir 端口而形成环,
        #   必须靠 localnetwork 集合里的节点 IP 兜底放行。所以只能降低频率。
        #
        # 取值权衡:
        #   30  轮 ≈ 31 分钟 (上游默认) —— 太频繁, 每半小时一次 37 秒满载
        #   120 轮 ≈ 2 小时           —— 采用值, 频率降 4 倍
        #   360 轮 ≈ 6 小时           —— 更激进, 想更安静可以改
        #   节点是腾讯云/AWS 的弹性 IP, 极少变动; 万一某个节点 IP 变了, 最坏情况是
        #   该节点不可用并由组内健康检查自动切换, 不会整体断网。
        #
        # 想恢复上游默认: 删掉本段即可 (下次编译自动还原为 30)。
        local OC_WATCHDOG="package/luci-app-openclash/root/usr/share/openclash/openclash_watchdog.sh"
        local OC_SKIP_INTERVAL=120
        if [ -f "$OC_WATCHDOG" ]; then
            if grep -q '^SKIP_PROXY_ADDRESS_INTERVAL=30$' "$OC_WATCHDOG"; then
                sed -i "s/^SKIP_PROXY_ADDRESS_INTERVAL=30\$/SKIP_PROXY_ADDRESS_INTERVAL=${OC_SKIP_INTERVAL}/" "$OC_WATCHDOG"
            fi
            if grep -q "^SKIP_PROXY_ADDRESS_INTERVAL=${OC_SKIP_INTERVAL}\$" "$OC_WATCHDOG"; then
                echo ""
                echo "✅ 已拉长「跳过代理地址」刷新间隔: 30 轮(约31分钟) -> ${OC_SKIP_INTERVAL} 轮(约${OC_SKIP_INTERVAL}分钟, 每轮 sleep 60s)"
            else
                echo ""
                echo "⚠️ watchdog 间隔改写失败, 上游可能改了变量名或格式, 请检查:"
                echo "   $OC_WATCHDOG"
                grep -n 'SKIP_PROXY_ADDRESS_INTERVAL' "$OC_WATCHDOG" | head -3
            fi
        else
            echo ""
            echo "⚠️ 未找到 $OC_WATCHDOG, 跳过「跳过代理地址」间隔改写"
        fi

        # 下载最新 Zashboard 面板替换预置版本
        local ZASHBOARD_URL="https://github.com/Zephyruso/zashboard/releases/latest/download/dist-cdn-fonts.zip"
        local ZASHBOARD_DIR="files/usr/share/openclash/ui/zashboard"
        echo ""
        echo "📥 下载最新 Zashboard 面板 (CDN字体版)..."
        if wget -q -O /tmp/zashboard.zip "$ZASHBOARD_URL"; then
            rm -rf "$ZASHBOARD_DIR"
            mkdir -p "$ZASHBOARD_DIR"
            unzip -q -o /tmp/zashboard.zip -d "$ZASHBOARD_DIR"

            # 上游 dist-cdn-fonts.zip 内部【只含一层 dist/ 目录】(实测 33 个文件
            # 全在 dist/ 下), 直接解到目标目录会得到 <目标>/dist/index.html,
            # 而 OpenClash 查找的是 <目标>/index.html —— 结果面板仍是包内自带的
            # 旧版本 (实测表现为一直停留在 v1.48.0, 而上游已到 v3.29.x)。
            # 故解包后把 dist/ 的内容上移一层。
            if [ ! -f "$ZASHBOARD_DIR/index.html" ] && [ -f "$ZASHBOARD_DIR/dist/index.html" ]; then
                echo "   检测到解包结果多了一层 dist/, 正在上移..."
                for f in "$ZASHBOARD_DIR/dist"/* "$ZASHBOARD_DIR/dist"/.[!.]*; do
                    [ -e "$f" ] || continue
                    mv -f "$f" "$ZASHBOARD_DIR/" 2>/dev/null
                done
                rmdir "$ZASHBOARD_DIR/dist" 2>/dev/null
            fi

            rm -f /tmp/zashboard.zip

            if [ -f "$ZASHBOARD_DIR/index.html" ]; then
                echo "✅ Zashboard 面板已更新到: $ZASHBOARD_DIR"
            else
                echo "⚠️ Zashboard 解包后未找到 index.html, 面板可能仍是包内自带旧版本"
            fi
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
            # 统计库改到 /tmp, 避免 AdGuardHome 按 interval 周期性写闪存
            # (querylog 预设中已关闭; 代价是重启后统计数据清零)
            sed -i 's|^  dir_path: ""$|  dir_path: /tmp|' files/etc/AdGuardHome.yaml

            if grep -q '^  dir_path: /tmp$' files/etc/AdGuardHome.yaml; then
                echo "✅ 预设配置文件已写入: files/etc/AdGuardHome.yaml (统计库已改到 /tmp)"
            else
                echo "⚠️ 预设配置已写入, 但统计库路径替换未生效, 请检查 yaml 结构"
            fi
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
# 安全加固: 关闭非特权 user namespace
# 作为内核 CONFIG_KERNEL_USER_NS 关闭的兜底。若内核已编译掉 USER_NS,
# /proc/sys/user/ 不存在, 此处静默跳过, 不产生启动报错。
# ============================================================
apply_security_hardening() {
    echo ""
    echo "🔒 应用安全加固: 关闭非特权 user namespace"

    local RC_LOCAL="files/etc/rc.local"
    local BLOCK='# security-hardening: 关闭非特权 user namespace, 阻断内核本地提权
[ -w /proc/sys/user/max_user_namespaces ] && echo 0 > /proc/sys/user/max_user_namespaces'

    mkdir -p files/etc

    if [ ! -f "$RC_LOCAL" ]; then
        printf '#!/bin/sh\n# OpenWrt rc.local - executed at boot\n\n%s\n\nexit 0\n' "$BLOCK" > "$RC_LOCAL"
    elif ! grep -q "max_user_namespaces" "$RC_LOCAL"; then
        if grep -q "^exit 0" "$RC_LOCAL"; then
            awk -v block="$BLOCK" '
                /^exit 0/ && !done { print block; done = 1 }
                { print }
            ' "$RC_LOCAL" > "$RC_LOCAL.tmp" && mv "$RC_LOCAL.tmp" "$RC_LOCAL"
        else
            printf '\n%s\n\nexit 0\n' "$BLOCK" >> "$RC_LOCAL"
        fi
    fi

    chmod 755 "$RC_LOCAL"

    if grep -q "max_user_namespaces" "$RC_LOCAL"; then
        echo "✅ rc.local 已包含 user namespace 加固"
    else
        echo "⚠️ user namespace 加固写入失败"
    fi
}


# ============================================================
# 预置防火墙与 DNS 默认设置 (uci-defaults)
# ============================================================
# 下列 6 项都是 UCI 运行时配置, 不属于 build config (.config), 无法写进
# config/*.config, 因此用 uci-defaults 在首次启动时写入。
#
# 之所以不用 files/etc/config/firewall 直接覆盖: firewall4 的默认配置来自其
# git 源码 (PKG_SOURCE_PROTO:=git, 见 firewall4/Makefile, 默认配置为
# root/etc/config/firewall), 覆盖会丢掉上游后续新增的默认项; dnsmasq 的
# dhcp.conf 虽在源码树里, 但两者统一用同一机制更清晰、也便于日后维护。
apply_system_defaults() {
    local UCI_DIR="files/etc/uci-defaults"
    local UCI_FILE="$UCI_DIR/99-custom-network-settings"

    echo ""
    echo "=========================================="
    echo "⚙️ 预置防火墙与 DNS 默认设置"
    echo "=========================================="

    mkdir -p "$UCI_DIR"

    cat > "$UCI_FILE" <<'UCIEOF'
#!/bin/sh
# 由 diy-part2.sh 生成 —— 预置防火墙与 DNS 默认设置
# uci-defaults 只在"首次启动"时执行一次, 执行后本文件会被自动删除;
# 带配置升级 (sysupgrade 不带 -n) 时不会重跑, 已写入的设置继续有效。

# ---------- 防火墙 (firewall4, config defaults) ----------
[ -n "$(uci -q get firewall.@defaults[0])" ] || uci -q add firewall defaults

# 1. 丢弃无效数据包
#    fw4 规则: ct state vmap { established:accept, related:accept, invalid:drop }
uci -q set firewall.@defaults[0].drop_invalid='1'

# 2. 启用 FullCone NAT6
#    对应 ImmortalWrt 的 fullcone 补丁 (defaults.fullcone6), 只作用于 IPv6;
#    IPv4 的 defaults.fullcone 在 ImmortalWrt 中默认已经是 1
uci -q set firewall.@defaults[0].fullcone6='1'

# 3. 流量卸载类型 = 无
#    不使用 firewall4 的 flowtable 卸载: 本机 turboacc 的 fastpath 已启用
#    mediatek_hnat (MTK 开源硬件加速引擎; 其 uci-defaults 检测到 mtkhnat.ko
#    即自动选它), 两条路径最终都编程同一个 PPE, 功能重叠。
#    显式写 0 以固定意图, 避免上游将来改默认值时被静默打开。
#    参考: fw4.uc 的 resolve_offload_devices() 要求 flow_offloading=1 才会
#    创建 flowtable, ruleset.uc 再依据 flow_offloading_hw=1 追加 flags offload。
uci -q set firewall.@defaults[0].flow_offloading='0'
uci -q set firewall.@defaults[0].flow_offloading_hw='0'

# ---------- DNS (dnsmasq) ----------
# dnsmasq.init 中的映射:
#   append_bool "$cfg" stripmac   "--strip-mac"
#   append_bool "$cfg" stripsubnet "--strip-subnet"
# 4. 在转发查询之前移除 MAC 地址
uci -q set dhcp.@dnsmasq[0].stripmac='1'
# 5. 在转发查询之前移除子网地址
uci -q set dhcp.@dnsmasq[0].stripsubnet='1'

uci -q commit firewall
uci -q commit dhcp

exit 0
UCIEOF

    chmod 755 "$UCI_FILE"

    # 结果校验: 6 个选项必须都出现在生成的文件里
    local MISSING=""
    local KEY
    for KEY in \
        'firewall.@defaults[0].drop_invalid' \
        'firewall.@defaults[0].fullcone6' \
        'firewall.@defaults[0].flow_offloading' \
        'firewall.@defaults[0].flow_offloading_hw' \
        'dhcp.@dnsmasq[0].stripmac' \
        'dhcp.@dnsmasq[0].stripsubnet' ; do
        grep -Fq "$KEY" "$UCI_FILE" || MISSING="$MISSING $KEY"
    done

    if [ -z "$MISSING" ]; then
        echo "✅ 已生成 $UCI_FILE (防火墙 4 项 + DNS 2 项)"
        echo "   → 首次启动时自动应用, 无需手动配置"
    else
        echo "⚠️ 以下选项未写入:$MISSING"
    fi
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

apply_security_hardening
apply_system_defaults

echo ""
echo "=========================================="
echo "✅ 所有集成任务完成!"
echo ""
echo "📋 最终状态："
echo "   mihomo 内核:       $([ "$MIHOMO_INTEGRATED" = "true" ] && echo '已集成 ✅' || echo '未集成')"
echo "   AdGuardHome 内核:  $([ "$ADGUARDHOME_INTEGRATED" = "true" ] && echo '已集成 ✅' || echo '未集成')"
echo "   easytier 内核:     $([ "$EASYTIER_INTEGRATED" = "true" ] && echo '已集成 ✅' || echo '未集成')"
echo "   防火墙/DNS 预设:   $([ -x files/etc/uci-defaults/99-custom-network-settings ] && echo '已预置 ✅' || echo '未预置')"
echo "=========================================="
