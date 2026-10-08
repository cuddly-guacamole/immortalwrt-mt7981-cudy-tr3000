[定制教程](https://xiabee.eu.org/customize.html) | [刷写教程](https://xiabee.eu.org/install.html)

<div align=center>
<img src="tr3000.png" height=200px align="center">
</div>

---

## immortalwrt 源码

编译自 https://github.com/chasey-dev/immortalwrt-mt798x-rebase 的 `25.12` 分支，兼容 Cudy Tr3000 128M 新 flash。

该上游基于 ImmortalWrt 25.12（内核 6.12），移植了 MTK OpenWrt Feeds 的闭源无线驱动与硬件加速，内核跟随主线持续更新。

> 此前使用的 `padavanonly/immortalwrt-mt798x-6.6` 内核冻结在 6.6.133 且不再同步上游，已切换。

---

## 大分区 ubootmod 固件

上游 25.12 分支的 ubootmod 布局默认即为 122M 分区（`reg = <0x5c0000 0x7a40000>`），无需再手工修改设备树。

> 旧版 24.10 上游默认为 112M，需按本文档历史版本手工 sed 扩容；该做法已不再需要。

---

## DHCP uboot

编译自 https://github.com/weekdaycare/bl-mt798x-dhcpd 感谢大佬开源，兼容新 flash

![](/uboot.png)

128M uboot 为三分区 uboot 支持原厂 ubi 大小 64MB，扩容 ubi 分区 112MB，最大 ubi 分区 122MB

256M uboot 为单分区 uboot

---

## USB 供电控制

25.12 上游设备树中 USB VBUS 已改为 `regulator-fixed`（`usb-vbus`，GPIO 9，`regulator-boot-on`），开机默认供电。

> 旧版 24.10 上游通过 `gpio-export` 导出 `modem_power`，可用 `echo 0 > /sys/class/gpio/modem_power/value` 关闭供电。
> 25.12 上游已移除该 gpio-export，上述命令不再适用。

---

## 安全加固

上游内核尚未包含 2026-09 公开的四组内核本地提权漏洞修复（完整修复需 6.6.157 / 6.12.109）。
本仓库**不改动任何源码**，仅通过内核配置收窄攻击面：

| 漏洞 | 触发前提 | 处理方式 |
|---|---|---|
| TUNderflow | 非特权 user namespace + TUN | `CONFIG_KERNEL_USER_NS` 关闭 |
| PPPoEject | 非特权 user namespace + PPPoE | 同上 |
| DirtyAH6 | 非特权 user namespace + IPsec AH | 同上（AH 本已关闭） |
| DiagSpill | SCTP | `kmod-sctp` / `CONFIG_IP_SCTP` 本已关闭 |

此外 `diy-part2.sh` 会向固件写入 rc.local 兜底：若内核仍带 USER_NS，则开机时将
`user.max_user_namespaces` 置 0；内核已编译掉 USER_NS 时该文件不存在，静默跳过。

关闭非特权 user namespace 不影响 OpenClash 的 TUN 模式与 PPPoE 拨号。

构建时会在 `make defconfig` 之后自动校验上述配置是否真正生效：关键项未生效会直接中止
构建，结果写入 Actions 的 Step Summary，可在编译前快速定位上游符号变动。

---

## 第三方软件包

- [OpenClash](https://github.com/vernesong/OpenClash)
- [Bandix](https://github.com/timsaya/luci-app-bandix)
- [luci-theme-aurora](https://github.com/eamonxg/luci-theme-aurora)
- [luci-app-aurora-config](https://github.com/eamonxg/luci-app-aurora-config)
- luci-app-ttyd
- luci-app-upnp
- kmod-usb-net-cdc-ether
- kmod-usb-net-rndis
- kmod-mtd-rw

---

## SSH 连接 Action

可以通过 ssh 连接到 Action 工作流来配置 `menuconfig` 。

手动运行 `ImmortalWrt Builder`，选择单个设备（不能选 `all`），并勾选 SSH 选项。
工作流使用 Upterm 公共中继提供 SSH 会话，仅允许使用触发者 GitHub 账号上的 SSH 公钥连接。
在 `SSH connection to Menuconfig` 步骤的日志中找到 SSH 连接命令；连接后执行：

```sh
cd /workdir/openwrt
make menuconfig
# 保存并退出 menuconfig 后，通知工作流继续推送配置和编译：
touch "$GITHUB_WORKSPACE/continue"
```

SSH 步骤最多运行 15 分钟，请在超时前保存配置并创建 `continue` 文件；直接取消运行或超时会跳过配置推送。
如果不显示连接命令，可在 GitHub 的 Re-run jobs 中勾选 Enable debug logging，
检查 Upterm 启动日志及到 `uptermd.upterm.dev` 的连接情况。

---

## 编译注意事项

GitHub Actions 存储有限，大型软件包（如 sing-box 或 alist）建议使用预编译方式，而不是源码编译，即在编译过程中加入已经编译好现成软件包。否则你应该会碰到超长编译时间 + 超出 Action 储存。示例：

```sh
# 创建存储二进制文件的目录
BIN_DIR="$GITHUB_WORKSPACE/openwrt/files/usr/bin"
mkdir -p "$BIN_DIR"

# -------- 下载并解压 xray-core ARM64 -------
echo "Downloading xray-core..."
curl -L -o xray.zip https://github.com/XTLS/Xray-core/releases/download/v25.10.15/Xray-linux-arm64-v8a.zip
unzip -o xray.zip -d "$BIN_DIR"
chmod +x "$BIN_DIR/xray"
rm xray.zip

# -------- 下载并解压 sing-box ARM64 -------
echo "Downloading sing-box..."
curl -L -o sing-box.tar.gz https://github.com/SagerNet/sing-box/releases/download/v1.12.12/sing-box-1.12.12-linux-arm64.tar.gz
TMP_DIR=$(mktemp -d)
tar -xzf sing-box.tar.gz -C "$TMP_DIR"
mv "$TMP_DIR"/sing-box-1.12.12-linux-arm64/sing-box "$BIN_DIR"/sing-box
chmod +x "$BIN_DIR/sing-box"
rm -rf "$TMP_DIR"
rm sing-box.tar.gz
```

---

## Credits

- [bl-mt798x-dhcpd](https://github.com/weekdaycare/bl-mt798x-dhcpd)
- [bl-mt798x](https://github.com/hanwckf/bl-mt798x)
- [immortalwrt-mt798x-rebase](https://github.com/chasey-dev/immortalwrt-mt798x-rebase)（当前上游）
- [mtk-openwrt-feeds](https://github.com/mediatek/mtk-openwrt-feeds)
- [immortalwrt-mt798x-6.6](https://github.com/padavanonly/immortalwrt-mt798x-6.6)（历史上游）
- [P3TERX](https://github.com/P3TERX)
- [Microsoft Azure](https://azure.microsoft.com)
- [GitHub Actions](https://github.com/features/actions)
- [OpenWrt](https://github.com/openwrt/openwrt)
- [coolsnowwolf/lede](https://github.com/coolsnowwolf/lede)
- [Mikubill/transfer](https://github.com/Mikubill/transfer)
- [softprops/action-gh-release](https://github.com/softprops/action-gh-release)
- [Mattraks/delete-workflow-runs](https://github.com/Mattraks/delete-workflow-runs)
- [dev-drprasad/delete-older-releases](https://github.com/dev-drprasad/delete-older-releases)
- [peter-evans/repository-dispatch](https://github.com/peter-evans/repository-dispatch)

---

## License

[MIT](https://github.com/P3TERX/Actions-OpenWrt/blob/main/LICENSE) © [**P3TERX**](https://p3terx.com)
