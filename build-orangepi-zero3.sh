#!/bin/bash
# ==============================================================================
# ImmortalWrt 编译脚本 - Orange Pi Zero3 1.5GB
# 目标平台: sunxi / cortexa53 / xunlong_orangepi-zero3
# 说明: 已包含 1.5GB DRAM 修复补丁 (280-sunxi-h616-fix-1.5GB-dram-size-detection.patch)
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 并行编译线程数，默认使用所有核心
JOBS=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

echo "========================================"
echo " ImmortalWrt - Orange Pi Zero3 1.5GB"
echo " 编译线程: ${JOBS}"
echo "========================================"

# ------------------------------------------------------------------------------
# Step 1: 更新并安装 feeds
# ------------------------------------------------------------------------------
echo ""
echo "[1/4] 更新 feeds..."
./scripts/feeds update -a

echo ""
echo "[2/4] 安装 feeds..."
./scripts/feeds install -a

# ------------------------------------------------------------------------------
# Step 2: 生成 .config
# ------------------------------------------------------------------------------
echo ""
echo "[3/4] 配置编译目标..."

cat > .config << 'EOF'
# 目标平台
CONFIG_TARGET_sunxi=y
CONFIG_TARGET_sunxi_cortexa53=y
CONFIG_TARGET_sunxi_cortexa53_DEVICE_xunlong_orangepi-zero3=y

# 基础软件包
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-base=y
CONFIG_PACKAGE_luci-theme-bootstrap=y

# 中文语言支持
CONFIG_PACKAGE_luci-i18n-base-zh-cn=y

# 常用工具
CONFIG_PACKAGE_wget-ssl=y
CONFIG_PACKAGE_curl=y
CONFIG_PACKAGE_htop=y
CONFIG_PACKAGE_nano=y
CONFIG_PACKAGE_bash=y
EOF

# 使用 defconfig 填充其余默认值
make defconfig

# ------------------------------------------------------------------------------
# Step 3: 编译
# ------------------------------------------------------------------------------
echo ""
echo "[4/4] 开始编译 (make -j${JOBS} V=s)..."
echo "编译日志将输出到: build.log"
echo "这可能需要较长时间（首次编译通常需要 1~3 小时）..."
echo ""

make -j"${JOBS}" V=s 2>&1 | tee build.log

# ------------------------------------------------------------------------------
# 输出结果
# ------------------------------------------------------------------------------
echo ""
echo "========================================"
echo " 编译完成!"
echo "========================================"
echo ""
echo "固件输出目录: bin/targets/sunxi/cortexa53/"
ls -lh bin/targets/sunxi/cortexa53/*.img.gz 2>/dev/null || \
ls -lh bin/targets/sunxi/cortexa53/ 2>/dev/null || \
echo "(未找到输出文件，请检查 build.log)"
