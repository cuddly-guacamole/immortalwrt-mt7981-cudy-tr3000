#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part1.sh
# Description: OpenWrt DIY script part 1 (Before Update feeds)
#
# Copyright (c) 2019-2024 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# Uncomment a feed source
#sed -i 's/^#\(.*helloworld\)/\1/' feeds.conf.default

# Add a feed source
#echo 'src-git helloworld https://github.com/fw876/helloworld' >>feeds.conf.default
#echo 'src-git passwall https://github.com/xiaorouji/openwrt-passwall' >>feeds.conf.default

# Copy custom local packages into OpenWrt tree so they are available during build
if [ -d "$GITHUB_WORKSPACE/package/luci-compat-keep" ]; then
  mkdir -p package
  cp -r "$GITHUB_WORKSPACE/package/luci-compat-keep" package/
fi

# luci-theme-aurora
git clone  --depth 1 --single-branch https://github.com/eamonxg/luci-theme-aurora package/luci-theme-aurora
# luci-app-aurora-config
git clone  --depth 1 --single-branch https://github.com/eamonxg/luci-app-aurora-config package/luci-app-aurora-config

# luci-app-bandix
git clone --depth 1 --single-branch https://github.com/timsaya/luci-app-bandix.git temp-luci-app-bandix
mv temp-luci-app-bandix/luci-app-bandix package/
rm -rf temp-luci-app-bandix
# openwrt-bandix
git clone --depth 1 --single-branch https://github.com/timsaya/openwrt-bandix.git temp-openwrt-bandix
mv temp-openwrt-bandix/openwrt-bandix package/
rm -rf temp-openwrt-bandix

# luci-app-openclash
rm -rf feeds/luci/luci-app-openclash
git clone --depth 1 --branch dev https://github.com/vernesong/OpenClash.git temp-openclash
mv temp-openclash/luci-app-openclash package/
rm -rf temp-openclash

# luci-app-adguardhome
git clone  --depth 1 --single-branch https://github.com/stevenjoezhang/luci-app-adguardhome package/luci-app-adguardhome
