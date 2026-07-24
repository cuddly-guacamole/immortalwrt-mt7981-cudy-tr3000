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
# 函数1: 集成 mihomo 内核
# ============================================================
integrate_mihomo() {
    echo "=========================================="
    echo "📦 开始集成 mihomo 内核"
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
        echo "❌ AdGuardHome 二进制下载失败"
        return 1
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
