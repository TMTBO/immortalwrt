#!/bin/bash
# ==============================================================================
# macOS 本机编译辅助脚本
# 创建大小写敏感的稀疏磁盘镜像，在其中完成编译
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_PATH="$HOME/immortalwrt-build.sparsebundle"
MOUNT_POINT="/Volumes/immortalwrt-build"
IMAGE_SIZE="50g"   # 稀疏镜像，实际占用随编译内容增长，最大 50GB

# ---- 检查空间 ----------------------------------------------------------------
AVAIL_GB=$(df -g "$HOME" | awk 'NR==2{print $4}')
echo "当前可用磁盘空间: ${AVAIL_GB}GB"
if [ "$AVAIL_GB" -lt 30 ]; then
  echo "警告: 可用空间不足 30GB，编译可能失败！"
  read -p "是否继续？(y/N): " confirm
  [[ "$confirm" != "y" && "$confirm" != "Y" ]] && exit 1
fi

# ---- 创建或挂载磁盘镜像 -------------------------------------------------------
if [ ! -e "$IMAGE_PATH" ]; then
  echo "创建大小写敏感稀疏磁盘镜像 (最大 ${IMAGE_SIZE})..."
  hdiutil create -size "$IMAGE_SIZE" \
    -type SPARSEBUNDLE \
    -fs "Case-sensitive APFS" \
    -volname "immortalwrt-build" \
    "$IMAGE_PATH"
fi

if ! mount | grep -q "$MOUNT_POINT"; then
  echo "挂载磁盘镜像..."
  hdiutil attach "$IMAGE_PATH" -mountpoint "$MOUNT_POINT"
fi

# ---- 将源码同步到镜像内 -------------------------------------------------------
BUILD_DIR="$MOUNT_POINT/immortalwrt"
if [ ! -d "$BUILD_DIR" ]; then
  echo "同步源码到镜像 (rsync)..."
  rsync -a --progress \
    --exclude '.git' \
    --exclude 'build_dir' \
    --exclude 'staging_dir' \
    --exclude 'dl' \
    --exclude 'bin' \
    --exclude 'tmp' \
    "$SCRIPT_DIR/" "$BUILD_DIR/"
  # 保留 dl/ 缓存（如果有）
  [ -d "$SCRIPT_DIR/dl" ] && rsync -a "$SCRIPT_DIR/dl" "$BUILD_DIR/"
fi

# ---- 检查 macOS 依赖 ----------------------------------------------------------
echo ""
echo "检查 Homebrew 依赖..."
BREW_PKGS=(
  coreutils findutils gawk gnu-sed gnu-tar
  make automake autoconf libtool
  gettext ncurses openssl@3 zlib
  python3 perl git wget rsync
  bison flex diffutils patch
  xz zstd
)
MISSING=()
for pkg in "${BREW_PKGS[@]}"; do
  brew list "$pkg" &>/dev/null || MISSING+=("$pkg")
done

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "安装缺失的 Homebrew 包: ${MISSING[*]}"
  brew install "${MISSING[@]}"
fi

# GNU tools 需要优先在 PATH 中
export PATH="$(brew --prefix coreutils)/libexec/gnubin:\
$(brew --prefix findutils)/libexec/gnubin:\
$(brew --prefix gnu-sed)/libexec/gnubin:\
$(brew --prefix gnu-tar)/libexec/gnubin:\
$(brew --prefix make)/libexec/gnubin:\
$(brew --prefix)/bin:\
$PATH"

echo "make 版本: $(make --version | head -1)"

# ---- 开始编译 -----------------------------------------------------------------
cd "$BUILD_DIR"

JOBS=$(sysctl -n hw.ncpu)
echo ""
echo "========================================"
echo " 编译目录: $BUILD_DIR"
echo " 编译线程: $JOBS"
echo "========================================"

echo ""
echo "[1/4] 更新 feeds..."
./scripts/feeds update -a

echo "[2/4] 安装 feeds..."
./scripts/feeds install -a

echo "[3/4] 生成 .config..."
cat > .config << 'EOF'
CONFIG_TARGET_sunxi=y
CONFIG_TARGET_sunxi_cortexa53=y
CONFIG_TARGET_sunxi_cortexa53_DEVICE_xunlong_orangepi-zero3=y
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-base=y
CONFIG_PACKAGE_luci-theme-bootstrap=y
CONFIG_PACKAGE_luci-i18n-base-zh-cn=y
CONFIG_PACKAGE_wget-ssl=y
CONFIG_PACKAGE_curl=y
CONFIG_PACKAGE_htop=y
CONFIG_PACKAGE_nano=y
CONFIG_PACKAGE_bash=y
EOF
make defconfig

echo "[4/4] 开始编译..."
make -j"${JOBS}" V=s 2>&1 | tee "$SCRIPT_DIR/build.log" || {
  echo "多线程编译失败，尝试单线程定位错误..."
  make -j1 V=s 2>&1 | tee -a "$SCRIPT_DIR/build.log"
}

echo ""
echo "========================================"
echo " 编译完成！固件位于:"
echo " $BUILD_DIR/bin/targets/sunxi/cortexa53/"
echo "========================================"
ls -lh "$BUILD_DIR/bin/targets/sunxi/cortexa53/" 2>/dev/null || true

echo ""
echo "提示: 卸载磁盘镜像请运行:"
echo "  hdiutil detach $MOUNT_POINT"
