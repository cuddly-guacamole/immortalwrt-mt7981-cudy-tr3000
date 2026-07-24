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

# Enable TWT
# sed -i '/set wireless.${dev}.serialize=1/a\
# 					set wireless.${dev}.twt_enable=1' \
# 					package/mtk/applications/mtwifi-cfg/files/mtwifi.sh

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
# ENABLE_UA2F="${ENABLE_UA2F:-false}"

echo "=========================================="
echo "📋 集成开关状态："
echo "   集成 mihomo: ${ENABLE_MIHOMO}"
echo "   集成 AdGuardHome: ${ENABLE_ADGUARDHOME}"
# echo "   集成 UA2F: ${ENABLE_UA2F}"
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

    # local CLONE_SUCCESS=false
    # 
    # echo "📥 克隆 OpenClash 源码..."
    # if [ -d "package/luci-app-openclash" ]; then
    #     echo "⚠️ 目录已存在，删除后重新克隆..."
    #     rm -rf package/luci-app-openclash
    # fi
    # 
    # # 尝试 dev 分支
    # echo "尝试克隆 dev 分支..."
    # git clone --depth=1 -b dev https://github.com/vernesong/OpenClash.git package/luci-app-openclash
    # 
    # if [ $? -ne 0 ]; then
    #     echo "⚠️ dev 分支克隆失败，尝试 master 分支..."
    #     git clone --depth=1 -b master https://github.com/vernesong/OpenClash.git package/luci-app-openclash
    #     
    #     if [ $? -ne 0 ]; then
    #         echo "⚠️ master 分支克隆失败，将使用官方包"
    #         echo "   → OpenClash 界面由官方源提供"
    #         CLONE_SUCCESS=false
    #     else
    #         echo "✅ master 分支克隆成功"
    #         CLONE_SUCCESS=true
    #     fi
    # else
    #     echo "✅ dev 分支克隆成功"
    #     CLONE_SUCCESS=true
    # fi



    echo ""
    echo "📥 下载 mihomo 内核..."
    
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
        echo "⚠️ ${VERSION} 下载失败，尝试回退到 v1.19.29..."
        
        local FALLBACK_VERSION="v1.19.29"
        local FALLBACK_FILE="mihomo-linux-arm64-${FALLBACK_VERSION}.gz"
        local FALLBACK_URL="https://github.com/MetaCubeX/mihomo/releases/download/${FALLBACK_VERSION}/${FALLBACK_FILE}"
        
        if wget -q -O /tmp/mihomo.gz "$FALLBACK_URL"; then
            gunzip -c /tmp/mihomo.gz > "$KERNEL_PATH"
            chmod 755 "$KERNEL_PATH"
            upx --best --lzma "$KERNEL_PATH" 2>/dev/null || true
            echo "✅ 回退到 ${FALLBACK_VERSION} 下载成功"
            ls -lh "$KERNEL_PATH"
            rm -f /tmp/mihomo.gz
            KERNEL_DOWNLOAD_SUCCESS=true
            VERSION="${FALLBACK_VERSION}"
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
    # if [ "$CLONE_SUCCESS" = "true" ]; then
    #     echo "   - OpenClash 界面: 源码克隆成功 (package/luci-app-openclash/)"
    # else
    #     echo "   - OpenClash 界面: 使用官方源"
    # fi
    
    if [ "$KERNEL_DOWNLOAD_SUCCESS" = "true" ]; then
        echo "   - mihomo 内核: 已集成 ✅"
        echo "   - 内核路径: $KERNEL_PATH"
        echo "   - 内核版本: ${VERSION}"
    else
        echo "   - mihomo 内核: 未集成（可选，用户可手动上传）"
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
    echo "🔍 检查是否集成预设配置文件..."

    if [ "$ENABLE_ADGUARDHOME_CONFIG" = "true" ]; then
        echo "✅ 用户已勾选「集成预设 AdGuardHome 配置文件」"
        echo "📝 写入 /etc/AdGuardHome.yaml ..."
        
        mkdir -p files/etc
        
        cat > files/etc/AdGuardHome.yaml << 'EOF'
http:
  pprof:
    port: 6060
    enabled: false
  doh:
    routes:
      - GET /dns-query
      - POST /dns-query
      - GET /dns-query/{ClientID}
      - POST /dns-query/{ClientID}
    insecure_enabled: false
  address: 0.0.0.0:3000
  session_ttl: 30d
users:
  - name: root
    password: $2y$10$PVhuB.icsC0Jl5Q.8twXwOOVPX0oxdmmilkkkjCXkIBki0rvBatMa
auth_attempts: 5
block_auth_min: 15
http_proxy: ""
language: ""
theme: auto
dns:
  bind_hosts:
    - 0.0.0.0
  port: 5553
  anonymize_client_ip: false
  ratelimit: 0
  ratelimit_subnet_len_ipv4: 24
  ratelimit_subnet_len_ipv6: 56
  ratelimit_whitelist: []
  refuse_any: false
  upstream_dns:
    - https://dns.google/dns-query
    - https://cloudflare-dns.com/dns-query
    - https://3v9q453gj5.cloudflare-gateway.com/dns-query
  upstream_dns_file: ""
  bootstrap_dns:
    - 1.1.1.1
    - 119.29.29.29
    - 223.5.5.5
  fallback_dns:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query
  upstream_mode: load_balance
  fastest_timeout: 1s
  allowed_clients: []
  disallowed_clients: []
  blocked_hosts:
    - version.bind
    - id.server
    - hostname.bind
  trusted_proxies:
    - 127.0.0.0/8
    - ::1/128
  cache_enabled: true
  cache_size: 4194304
  cache_ttl_min: 300
  cache_ttl_max: 86400
  cache_optimistic: true
  cache_optimistic_answer_ttl: 30s
  cache_optimistic_max_age: 12h
  bogus_nxdomain: []
  aaaa_disabled: false
  enable_dnssec: true
  edns_client_subnet:
    custom_ip: ""
    enabled: false
    use_custom: false
  max_goroutines: 300
  handle_ddr: true
  ipset: []
  ipset_file: ""
  bootstrap_prefer_ipv6: false
  upstream_timeout: 10s
  private_networks: []
  use_private_ptr_resolvers: true
  local_ptr_upstreams: []
  use_dns64: false
  dns64_prefixes: []
  serve_http3: false
  use_http3_upstreams: false
  serve_plain_dns: true
  hostsfile_enabled: true
  pending_requests:
    enabled: true
tls:
  enabled: false
  server_name: ""
  force_https: false
  port_https: 443
  port_dns_over_tls: 853
  port_dns_over_quic: 853
  port_dnscrypt: 0
  dnscrypt_config_file: ""
  certificate_chain: ""
  private_key: ""
  certificate_path: ""
  private_key_path: ""
  strict_sni_check: false
querylog:
  dir_path: ""
  ignored: []
  interval: 1d
  size_memory: 1000
  enabled: false
  ignored_enabled: false
  file_enabled: true
statistics:
  dir_path: ""
  ignored: []
  interval: 1d
  enabled: true
  ignored_enabled: false
filters:
  - enabled: true
    url: https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt
    name: AdGuard DNS filter
    id: 1
  - enabled: true
    url: https://adaway.org/hosts.txt
    name: AdAway Default Blocklist
    id: 2
  - enabled: false
    url: https://cdn.jsdelivr.net/gh/neoFelhz/neohosts@gh-pages/full/hosts.txt
    name: neoHosts full
    id: 3
  - enabled: false
    url: https://cdn.jsdelivr.net/gh/neoFelhz/neohosts@gh-pages/basic/hosts.txt
    name: neoHosts basic
    id: 4
  - enabled: false
    url: http://sbc.io/hosts/hosts
    name: StevenBlack host basic
    id: 5
  - enabled: false
    url: http://sbc.io/hosts/alternates/fakenews-gambling-porn-social/hosts
    name: StevenBlack host + fakenews + gambling + porn + social
    id: 6
  - enabled: false
    url: https://cdn.jsdelivr.net/gh/217heidai/adblockfilters@main/rules/adblockdns.txt
    name: 217heidai AdBlock DNS Filters
    id: 7
whitelist_filters: []
user_rules: []
dhcp:
  enabled: false
  interface_name: ""
  local_domain_name: lan
  dhcpv4:
    gateway_ip: ""
    subnet_mask: ""
    range_start: ""
    range_end: ""
    lease_duration: 86400
    icmp_timeout_msec: 1000
    options: []
  dhcpv6:
    range_start: ""
    lease_duration: 86400
    ra_slaac_only: false
    ra_allow_slaac: false
filtering:
  blocking_ipv4: ""
  blocking_ipv6: ""
  blocked_services:
    schedule:
      time_zone: UTC
    ids: []
  protection_disabled_until: null
  safe_search:
    enabled: false
    bing: true
    duckduckgo: true
    ecosia: true
    google: true
    pixabay: true
    yandex: true
    youtube: true
  blocking_mode: nxdomain
  parental_block_host: family-block.dns.adguard.com
  safebrowsing_block_host: standard-block.dns.adguard.com
  rewrites:
    - domain: dns.google
      answer: 8.8.8.8
      enabled: true
    - domain: dns.google
      answer: 8.8.4.4
      enabled: true
    - domain: cloudflare-dns.com
      answer: 104.16.249.249
      enabled: true
    - domain: cloudflare-dns.com
      answer: 104.16.248.249
      enabled: true
    - domain: dns.alidns.com
      answer: 223.5.5.5
      enabled: true
    - domain: dns.alidns.com
      answer: 223.6.6.6
      enabled: true
    - domain: doh.pub
      answer: 120.53.53.53
      enabled: true
    - domain: doh.pub
      answer: 1.12.12.12
      enabled: true
    - domain: 3v9q453gj5.cloudflare-gateway.com
      answer: 162.159.36.5
      enabled: true
    - domain: 3v9q453gj5.cloudflare-gateway.com
      answer: 162.159.36.20
      enabled: true
  safe_fs_patterns:
    - /usr/bin/AdGuardHome/data/userfilters/*
  max_http_size: 256MB
  safebrowsing_cache_size: 1048576
  safesearch_cache_size: 1048576
  parental_cache_size: 1048576
  cache_time: 30
  filters_update_interval: 24
  blocked_response_ttl: 10
  filtering_enabled: true
  rewrites_enabled: true
  parental_enabled: false
  safebrowsing_enabled: false
  protection_enabled: true
clients:
  runtime_sources:
    whois: true
    arp: true
    rdns: false
    dhcp: true
    hosts: true
  persistent: []
log:
  enabled: true
  file: ""
  max_backups: 0
  max_size: 100
  max_age: 3
  compress: false
  local_time: false
  verbose: false
os:
  group: ""
  user: ""
  rlimit_nofile: 0
schema_version: 34
EOF

        echo "✅ 预设配置文件已写入: files/etc/AdGuardHome.yaml"
    else
        echo "⏭️ 用户未勾选「集成预设 AdGuardHome 配置文件」，跳过"
    fi

    echo ""
    echo "=========================================="
    echo "✅ AdGuardHome 集成完成"
    echo "   版本: ${VERSION}"
    echo "   路径: files/usr/bin/AdGuardHome/AdGuardHome"
    if [ "$ENABLE_ADGUARDHOME_CONFIG" = "true" ]; then
        echo "   配置文件: files/etc/AdGuardHome.yaml ✅"
    else
        echo "   配置文件: 未预设"
    fi
    echo "=========================================="
    return 0
}



# ============================================================
# 函数3: 集成 UA2F
# ============================================================
# integrate_ua2f() {
#     echo "=========================================="
#     echo "📦 开始集成 UA2F"
#     echo "=========================================="
#     
#     # ---- 第1步：获取最新版本号 ----
#     echo "📡 获取 UA2F 最新版本..."
#     
#     local API_URL="https://api.github.com/repos/Zxilly/UA2F/releases/latest"
#     local LATEST_TAG=$(wget -q -O- "$API_URL" | grep -o '"tag_name": "[^"]*"' | sed 's/"tag_name": "//;s/"//')
#     
#     if [ -z "$LATEST_TAG" ]; then
#         echo "⚠️ 获取最新版本失败，使用默认版本 v5.2.0"
#         LATEST_TAG="v5.2.0"
#     fi
#     echo "✅ 最新版本: ${LATEST_TAG}"
# 
# 
# 
#     # ---- 第2步：下载 UA2F IPK ----
#     echo ""
#     echo "📥 下载 UA2F IPK..."
#     
#     local UA2F_FILE="ua2f_4.10.2-r1_aarch64_cortex-a53-24.10.0.ipk"
#     local DOWNLOAD_URL="https://github.com/Zxilly/UA2F/releases/download/${LATEST_TAG}/${UA2F_FILE}"
#     
#     echo "📥 下载 UA2F: ${LATEST_TAG}"
#     echo "   URL: $DOWNLOAD_URL"
#     
#     mkdir -p /tmp/ua2f_extract
#     
#     if ! wget -q -O /tmp/ua2f_extract/ua2f.ipk "$DOWNLOAD_URL"; then
#         echo "⚠️ 版本 ${LATEST_TAG} 下载失败，尝试回退到 v5.2.0..."
#         
#         local FALLBACK_TAG="v5.2.0"
#         local FALLBACK_URL="https://github.com/Zxilly/UA2F/releases/download/${FALLBACK_TAG}/${UA2F_FILE}"
#         
#         if wget -q -O /tmp/ua2f_extract/ua2f.ipk "$FALLBACK_URL"; then
#             echo "✅ 回退到 ${FALLBACK_TAG} 下载成功"
#             LATEST_TAG="${FALLBACK_TAG}"
#         else
#             echo "❌ UA2F 下载失败（包括回退版本），跳过集成"
#             rm -rf /tmp/ua2f_extract
#             return 1
#         fi
#     else
#         echo "✅ 下载成功，版本: ${LATEST_TAG}"
#     fi
# 
# 
# 
#     # ---- 第3步：完整解压 IPK 到 files/ 目录 ----
#     echo ""
#     echo "📦 完整解压 IPK 到 files/ 目录..."
#     
#     cd /tmp/ua2f_extract
#     
#     tar -xzf ua2f.ipk 2>/dev/null || {
#         echo "❌ 解压 IPK 失败"
#         cd - > /dev/null
#         rm -rf /tmp/ua2f_extract
#         return 1
#     }
#     
#     if [ -f data.tar.gz ]; then
#         mkdir -p files
#         tar -xzf data.tar.gz -C files/ 2>/dev/null || {
#             echo "❌ 解压 data.tar.gz 失败"
#             cd - > /dev/null
#             rm -rf /tmp/ua2f_extract
#             return 1
#         }
#         echo "✅ IPK 已完整解压到 files/ 目录"
#         echo "📋 解压后的文件:"
#         find files/ -type f 2>/dev/null | head -10
#     else
#         echo "❌ data.tar.gz 不存在"
#         cd - > /dev/null
#         rm -rf /tmp/ua2f_extract
#         return 1
#     fi
# 
# 
# 
#     # ---- 第4步：压缩 UA2F 二进制 ----
#     echo ""
#     echo "🔧 压缩 UA2F 二进制..."
#     
#     if [ -f files/usr/bin/ua2f ]; then
#         echo "压缩前: $(ls -lh files/usr/bin/ua2f | awk '{print $5}')"
#         upx --best --lzma files/usr/bin/ua2f 2>/dev/null || true
#         echo "压缩后: $(ls -lh files/usr/bin/ua2f | awk '{print $5}')"
#         echo "✅ UA2F 二进制已压缩"
#     else
#         echo "⚠️ 未找到 files/usr/bin/ua2f，跳过压缩"
#     fi
# 
# 
# 
#     # ---- 第5步：创建配置文件 ----
#     echo ""
#     echo "📝 创建 UA2F 配置文件..."
#     
#     mkdir -p files/etc/config
#     
#     cat > files/etc/config/ua2f << 'EOF'
# config ua2f 'firewall'
#         option handle_fw '1'
#         option handle_tls '0'
#         option handle_intranet '1'
#         option handle_mmtls '1'
# 
# config ua2f 'main'
#         option mode 'REDIRECT'
#         option listen_port '10010'
#         option nfqueue_workers '1'
#         option proxy_workers '0'
#         option disable_connmark '0'
#         option max_http_sessions '0'
#         option session_ttl '300'
#         option enabled '1'
#         option ua 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36'
# EOF
#     
#     echo "✅ 配置文件已创建: files/etc/config/ua2f"
#     
#     cd - > /dev/null
#     rm -rf /tmp/ua2f_extract
#     
#     echo ""
#     echo "=========================================="
#     echo "✅ UA2F 集成完成"
#     echo "   - 版本: ${LATEST_TAG}"
#     echo "   - 二进制: files/usr/bin/ua2f"
#     echo "   - 配置文件: files/etc/config/ua2f"
#     echo "=========================================="
#     return 0
# }



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

# if [ "$ENABLE_UA2F" = "true" ]; then
#     integrate_ua2f
# else
#     echo "⏭️ 跳过 UA2F 集成 (ENABLE_UA2F=false)"
# fi

echo ""
echo "=========================================="
echo "✅ 所有集成任务完成!"
echo "=========================================="
