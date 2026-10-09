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

## 包管理器 (opkg / apk)

本仓库默认固定使用 **opkg**，与历史固件行为一致。

上游 25.12 的 `CONFIG_USE_APK` 默认为 `y`，而配置中沿用了 24.10 的 `CONFIG_PACKAGE_opkg=y`。
两者叠加会让 `make defconfig` 同时启用两个包管理器，因此配置里已显式写死 `# CONFIG_USE_APK is not set`。

想尝鲜 APK（Alpine Package Keeper，25.12 官方默认）时，手动触发 `ImmortalWrt Builder` 并勾选
**`enable_apk`** 即可 —— 工作流会在构建前改写配置，仓库里的配置文件不受影响，取消勾选即回到 opkg。

> 注意：opkg 与 apk 的命令语法不同，且两者记录的已安装软件元数据不通用，切换后建议全新刷入而非保留配置升级。

---

## 大分区 ubootmod 固件

本仓库编译的 ubootmod 固件固定为 **112M** ubi 分区（`reg = <0x5c0000 0x7000000>`），由 `diy-part2.sh` 在编译时把上游默认值改回。

上游 25.12（含官方 openwrt / immortalwrt）默认是 122M（`0x7a40000`），该值恰好占满整块 NAND 在 `0x5c0000` 之后的全部剩余空间（128MiB − 5.75MiB = 122.25MiB），没有留下坏块替换余量。112M 保留 10.25MiB 余量，并与历史固件分区布局保持一致 —— 部分 uboot 版本按 112M 布局构建，分区不一致会导致固件刷入失败。

构建时会校验该替换是否生效，未生效会直接中止构建。

---

## DHCP uboot

本仓库固件按 ubootmod 布局编译，适配 https://github.com/Yuzhii0718/bl-mt798x-dhcpd （hanwckf `bl-mt798x` 的分支，支持 DHCP、带 Web UI 与多布局）。

> 本仓库**不再构建 uboot**，直接使用上述项目的发布版本即可。若需自行编译，请选择 `VARIANT=ubootmod`。

![](/uboot.png)

128M uboot 为三分区 uboot，支持原厂 ubi 大小 64MB，扩容 ubi 分区 112MB，最大 ubi 分区 122MB

> 该 uboot 的 `ubootmod` 变体（`configs-fit/mt7981_cudy_tr3000-v1_defconfig`）未启用 MTK-NMBM，
> 其 mtdparts 把 ubi 声明为「剩余全部空间」；固件侧按 112M 构建，与历史行为保持一致。

---

## 刷机流程（U-Boot / FIT）

**注意镜像格式变了**：本仓库 ubootmod 固件是 **FIT 格式（`sysupgrade.itb`）**，而 padavanonly 24.10 分支的 ubootmod 产出的是 **`sysupgrade.bin`（`sysupgrade-tar`，`KERNEL_IN_UBI=1`）**。两者对应的 U-Boot 引导流程不同，请按下面步骤操作。

`firmware_collection/` 中的产物：

| 文件 | 用途 |
|---|---|
| `*sysupgrade.itb` | 主固件（FIT），**这是要刷的固件** |
| `*initramfs-recovery.itb` | 恢复镜像，U-Boot failsafe 引导用 |
| `*sysupgrade.bin` | 仅 128M（非 ubootmod）机型产出 |
| `*preloader.bin` / `*bl31-uboot.fip` | OpenWrt U-Boot 工件（BL2 / FIP） |

操作步骤：

1. **先用 failsafe Web UI 备份全部 flash 与分区**（`http://failsafe.lan`）——这一步非常重要。
2. Web UI 中更新 BL2，刷入 `*preloader.bin`。
3. Web UI 中更新 U-Boot，刷入 FIT 版本的 `*bl31-uboot.fip`。
4. **用 Web UI 的 Flash Editor 擦除 UBI 分区**（或命令行 `mtd erase ubi`）。仅 NAND 设备需要这一步。
   > 这一步是关键。历史固件（padavanonly 分支）为该机型启用了 MTK-NMBM，而 NMBM 会在 NAND 上维护坏块表并调整块映射。上游有明确提交（`7044345`，"mediatek: cudy nand: fix wrong nmbm configuration"）指出 Cudy NAND 的 ubootmod 构建开启 NMBM 会导致启动时报 `Signature not found`。擦除 ubi 可清掉这些残留状态。
5. 在固件升级页刷入 `*sysupgrade.itb`。若无法启动，继续下一步。
6. 用 failsafe Web UI 的 Initramfs 引导 `*initramfs-recovery.itb`。
7. 若能正常进入系统，再次在固件升级页刷入 `*sysupgrade.itb`。

> 该 U-Boot 带 `CONFIG_MTK_WEB_FAILSAFE_AFTER_BOOT_FAILURE`，启动失败会自动进入 Web 恢复界面，可反复重试。
> 建议保留一份历史可用的 `sysupgrade.bin` 作为回退。

`CONFIG_TARGET_ROOTFS_INITRAMFS` 已启用（第 6 步依赖它），预检会校验它是否仍然生效。

### 关于 NMBM：固件必须与 U-Boot 匹配

U-Boot 在引导前会校验 **Linux FDT 与自身 MTD 布局 / NMBM 模式是否一致**，不一致会直接拒绝引导——表现是**红灯闪烁后回到 failsafe WEBUI，且连 Initramfs 也起不来**（该校验对任何引导都生效）。

本仓库适配的 U-Boot（`Yuzhii0718/bl-mt798x-dhcpd`，`VARIANT=ubootmod`）**NMBM 是开启的**：

```
mtd list   -> 存在 nmbm0, 所有分区挂在 nmbm0 上
env print  -> mtdids=nmbm0=nmbm0, mtdparts=nmbm0:...,114688k(ubi)
启动日志   -> "Initializing NMBM ... NMBM has been successfully attached"
```

因此 `diy-part2.sh` 会把上游 25.12 ubootmod 设备树**被删掉的 `&spi_nand` 节点补回来**（`spi-cal-*` + `mediatek,nmbm` + bmt 参数），并把 ubi 改成 112M，与 padavanonly 24.10 分支上能正常启动的同名设备树一致。预检会校验这三项（112M / NMBM / spi-cal）同时存在，缺一即中止构建。

> 注意：上游有提交 `7044345` 要求 Cudy NAND 的 ubootmod 构建**关闭** NMBM——那是为**官方 OpenWrt U-Boot**（不含 NMBM）准备的。本仓库用的是第三方 U-Boot，NMBM 开着，所以固件侧也必须开着，两边必须一致。

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

## 构建兼容性：RELR 已关闭

上游 25.12 默认开启 `CONFIG_PKG_DT_RELR`，会向 `TARGET_LDFLAGS` 注入 `-zpack-relative-relocs`。
该标志在 aarch64 上会被链接器忽略，并输出一行警告：

| 项 | 内容 |
|---|---|
| 链接器输出 | `ld.bfd: warning: -z pack-relative-relocs ignored` |
| 链接结果 | 成功（退出码 0），仅 stderr 非空 |

问题出在 `ruby` 3.4 的 `configure`：它用 `RUBY_WERROR_FLAG` 包裹「LDFLAGS 是否有效」的检测，
而该检测要求链接的 **stderr 必须为空**（`test ! -s conftest.err`）。于是这行警告会让
`configure` 直接报错并中止：

```
checking whether LDFLAGS is valid... no
configure: error: something wrong with LDFLAGS="..."
    ERROR: package/feeds/packages/ruby failed to build.
```

`ruby` 是 OpenClash 的硬依赖（`YAML.rb` 负责生成 mihomo 配置），无法移除。
由于该标志在 aarch64 上本就被忽略，配置中已显式关闭 `CONFIG_PKG_DT_RELR`，
预检会校验它必须处于关闭状态。

> 同类症状的判断方法：凡是「链接成功但 stderr 非空」导致的 autoconf 检测失败，
> 都可用 `-zpack-relative-relocs` 这条线索反查。

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

- [bl-mt798x-dhcpd (Yuzhii0718)](https://github.com/Yuzhii0718/bl-mt798x-dhcpd)
- [bl-mt798x-dhcpd (weekdaycare)](https://github.com/weekdaycare/bl-mt798x-dhcpd)
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
