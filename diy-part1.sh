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

# Copy custom local packages into OpenWrt tree so they are available during build
if [ -d "$GITHUB_WORKSPACE/package/luci-compat-keep" ]; then
  mkdir -p package
  cp -r "$GITHUB_WORKSPACE/package/luci-compat-keep" package/
fi

# luci-theme-aurora
git clone --depth 1 --single-branch https://github.com/eamonxg/luci-theme-aurora package/luci-theme-aurora || { echo "❌ clone 失败: luci-theme-aurora"; exit 1; }
# luci-app-aurora-config
git clone --depth 1 --single-branch https://github.com/eamonxg/luci-app-aurora-config package/luci-app-aurora-config || { echo "❌ clone 失败: luci-app-aurora-config"; exit 1; }

# luci-app-bandix
git clone --depth 1 --single-branch https://github.com/timsaya/luci-app-bandix.git temp-luci-app-bandix || { echo "❌ clone 失败: luci-app-bandix"; exit 1; }
mv temp-luci-app-bandix/luci-app-bandix package/ || { echo "❌ 目录结构不符: temp-luci-app-bandix/luci-app-bandix"; exit 1; }
rm -rf temp-luci-app-bandix
# openwrt-bandix
git clone --depth 1 --single-branch https://github.com/timsaya/openwrt-bandix.git temp-openwrt-bandix || { echo "❌ clone 失败: openwrt-bandix"; exit 1; }
mv temp-openwrt-bandix/openwrt-bandix package/ || { echo "❌ 目录结构不符: temp-openwrt-bandix/openwrt-bandix"; exit 1; }
rm -rf temp-openwrt-bandix

# luci-app-openclash
git clone --depth 1 --branch dev https://github.com/vernesong/OpenClash.git temp-openclash || { echo "❌ clone 失败: OpenClash"; exit 1; }
mv temp-openclash/luci-app-openclash package/ || { echo "❌ 目录结构不符: temp-openclash/luci-app-openclash"; exit 1; }
rm -rf temp-openclash

# luci-app-adguardhome
git clone --depth 1 --single-branch https://github.com/stevenjoezhang/luci-app-adguardhome package/luci-app-adguardhome || { echo "❌ clone 失败: luci-app-adguardhome"; exit 1; }

# easytier (EasyTier 组网, 官方包: easytier / luci-app-easytier)
git clone --depth 1 --single-branch https://github.com/EasyTier/luci-app-easytier.git temp-easytier || { echo "❌ clone 失败: EasyTier/luci-app-easytier"; exit 1; }
cp -r temp-easytier/easytier package/easytier || { echo "❌ 目录结构不符: temp-easytier/easytier"; exit 1; }
cp -r temp-easytier/luci-app-easytier package/luci-app-easytier || { echo "❌ 目录结构不符: temp-easytier/luci-app-easytier"; exit 1; }
# version.mk 放入各包目录, 并修正 Makefile 引用路径, 避免污染 package/ 根目录
if [ -f temp-easytier/version.mk ]; then
  cp -f temp-easytier/version.mk package/easytier/version.mk
  cp -f temp-easytier/version.mk package/luci-app-easytier/version.mk
  sed -i 's|\.\./version\.mk|version.mk|g' package/easytier/Makefile package/luci-app-easytier/Makefile
else
  echo "⚠️ temp-easytier/version.mk 不存在, 使用 Makefile 内默认版本号"
fi
rm -rf temp-easytier
