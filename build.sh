#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ $# -ge 1 ]; then
  LEAN_RT="$1"
else
  LEAN_RT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi
[ -d "$LEAN_RT" ] || { echo "[!] 找不到 lean-wrt 源码目录: $LEAN_RT"; exit 1; }
cd "$LEAN_RT"
echo "[*] 源码目录: $LEAN_RT"

if [ -n "${DOWNLOAD_MIRROR:-}" ]; then
  echo "[*] 使用下载镜像: $DOWNLOAD_MIRROR"
  mkdir -p dl
fi

cp -f "$SCRIPT_DIR/feeds.conf" "$LEAN_RT/feeds.conf"
echo "[*] 已写入 feeds.conf"

if [ -d "$SCRIPT_DIR/files" ]; then
  rm -rf "$LEAN_RT/files"
  cp -a "$SCRIPT_DIR/files" "$LEAN_RT/files"
  echo "[*] 已写入 files/ 覆盖层（含 FM350-GL hotplug 脚本）"
fi

echo "[*] 更新 feeds (update -a) ..."
./scripts/feeds update -a
echo "[*] 安装 feeds (install -a) ..."
./scripts/feeds install -a
./scripts/feeds install luci-app-modem 2>/dev/null || \
  echo "[!] luci-app-modem 未从独立 feed 安装（可能已在 coolsnowwolf/luci 中，稍后 defconfig 校验）"

echo "[*] 生成 .config（目标 hinlink_opc-h29k + FM350-GL 选型）..."
: > .config
cat "$SCRIPT_DIR/config.seed" >> .config
cat >> .config <<'EOF'
# 关闭（如不需要）
# CONFIG_PACKAGE_luci-theme-argon is not set
EOF

echo "[*] 运行 make defconfig 解析依赖 ..."
make defconfig

echo "[*] 关键包选择校验："
for p in luci-app-modem fibocom-dial quectel-cm kmod-qmi_wwan_f kmod-usb-net-qmi_wwan; do
  if grep -q "CONFIG_PACKAGE_$p=y" .config; then
    echo "    [OK] $p"
  else
    echo "    [!!] 未选中 $p —— 请检查 feeds 是否正确安装"
  fi
done

echo "[*] 预下载源码包 (make download) ..."
make -j"$(nproc)" download || make download

echo "[*] 开始编译 make -j$(nproc) V=s ..."
make -j"$(nproc)" V=s

IMG="bin/targets/rockchip/armv8/openwrt-rockchip-armv8-hinlink_opc-h29k-sysupgrade.img.gz"
echo "[*] 编译完成。产物："
ls -lh "$IMG" 2>/dev/null || { echo "[!] 未找到 $IMG，请检查上面的编译日志"; exit 1; }
echo "[*] 刷机前请务必备份原厂 / 当前固件的 ART、MAC、btmac 等分区！"

