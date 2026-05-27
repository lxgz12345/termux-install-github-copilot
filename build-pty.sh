#!/data/data/com.termux/files/usr/bin/bash
# build-pty.sh — 为 Termux (Android arm64) 编译并部署 Copilot CLI 的 pty.node
# 支持全新环境首次使用，也可重复运行（幂等）

set -euo pipefail

# ── 路径配置 ─────────────────────────────────────────────────────────────────
# 以脚本所在目录作为 Termux 主目录，避免 root/suroot 环境下 $HOME 错误
TERMUX_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
COPILOT_DIR="$TERMUX_PREFIX/lib/node_modules/@github/copilot"
TARGET_DIR="$COPILOT_DIR/prebuilds/android-arm64"
RG_ANDROID_DIR="$COPILOT_DIR/ripgrep/bin/android-arm64"
BUILD_DIR="$TERMUX_HOME/pty-build"

# ── 彩色输出 ─────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*" >&2; }
step()  { echo -e "\n${BOLD}── $* ──${NC}"; }

# ── Step 1: 更新软件包 ───────────────────────────────────────────────────────
step "[1/7] 更新 pkg 软件包列表"
pkg update
pkg upgrade -y
info "软件包已更新"

# ── Step 2: 安装编译依赖 ─────────────────────────────────────────────────────
step "[2/7] 检查并安装编译依赖"
REQUIRED_PKGS=(nodejs-lts python make clang binutils ripgrep gh git)
MISSING_PKGS=()
for _pkg in "${REQUIRED_PKGS[@]}"; do
  if dpkg -l "$_pkg" 2>/dev/null | grep -q "^ii"; then
    info "$_pkg 已安装，跳过"
  else
    MISSING_PKGS+=("$_pkg")
  fi
done
if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
  info "安装缺失的包: ${MISSING_PKGS[*]}"
  pkg install -y "${MISSING_PKGS[@]}"
else
  info "所有依赖包均已安装"
fi

# ── Step 3: 安装 Copilot CLI ─────────────────────────────────────────────────
step "[3/7] 安装 Copilot CLI"
info "安装 @github/copilot@1.0.42..."
npm install -g @github/copilot@1.0.42
info "Copilot CLI 安装完成"

# ── 环境检查 ─────────────────────────────────────────────────────────────────
if ! command -v node &>/dev/null; then
  error "node 安装后仍无法调用，请检查 PATH"
  exit 1
fi
NODE_VER="$(node -e 'console.log(process.version.slice(1))')"
info "Node.js: v${NODE_VER}"
info "Termux Home: $TERMUX_HOME"
info "Build Dir:   $BUILD_DIR"
info "Target:      $TARGET_DIR"

# ── Step 4: 修复 ripgrep 符号链接 ────────────────────────────────────────────
step "[4/7] 修复 ripgrep 符号链接"
if [ ! -e "$RG_ANDROID_DIR/rg" ]; then
  mkdir -p "$RG_ANDROID_DIR"
  ln -sf "$(command -v rg)" "$RG_ANDROID_DIR/rg"
  info "已创建软链接: $RG_ANDROID_DIR/rg -> $(command -v rg)"
else
  info "rg 软链接已存在，跳过"
fi

# ── Step 3: 准备编译工作区 ────────────────────────────────────────────────────
step "[5/7] 准备编译工作区"
rm -rf "$BUILD_DIR" && mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

HOME="$TERMUX_HOME" npm init -y >/dev/null
HOME="$TERMUX_HOME" npm install node-gyp --save-dev >/dev/null 2>&1
export PATH="$BUILD_DIR/node_modules/.bin:$PATH"

# 确保 node-gyp 头文件缓存存在（首次运行时需要下载）
COMMON_GYPI="$TERMUX_HOME/.cache/node-gyp/${NODE_VER}/include/node/common.gypi"
if [ ! -f "$COMMON_GYPI" ]; then
  info "下载 node-gyp 头文件（首次运行，需联网）..."
  HOME="$TERMUX_HOME" node-gyp install --arch=arm64 2>&1 | grep -E "gyp info|error|ERR" || true
fi
if [ ! -f "$COMMON_GYPI" ]; then
  error "无法找到 common.gypi: $COMMON_GYPI"
  error "请检查网络连接后重试"
  exit 1
fi
info "node-gyp 头文件就绪"

# ── Step 4: 修补 common.gypi ─────────────────────────────────────────────────
step "[6/7] 修补 common.gypi（移除 Android NDK 依赖）"
if grep -q "android_ndk_path" "$COMMON_GYPI"; then
  sed -i 's|-I<(android_ndk_path)/sources/android/cpufeatures||g' "$COMMON_GYPI"
  info "已移除 NDK include 路径"
else
  info "common.gypi 无需修补（已干净）"
fi

# ── Step 5: 编译 node-pty ────────────────────────────────────────────────────
step "[7/7] 编译 node-pty"

# 使用 Termux 原生 clang 工具链
export CC=clang CXX=clang++ AR=llvm-ar RANLIB=llvm-ranlib STRIP=llvm-strip

try_build() {
  local VER="$1"
  rm -rf "$BUILD_DIR/node_modules/node-pty"

  info "下载 node-pty@${VER} 源码..."
  if ! HOME="$TERMUX_HOME" npm install "node-pty@${VER}" --ignore-scripts --save \
       >/dev/null 2>&1; then
    warn "node-pty@${VER} 下载失败，跳过"
    return 1
  fi

  local BUILD_LOG="$BUILD_DIR/build-${VER}.log"
  info "编译 node-pty@${VER}..."
  if ( cd "$BUILD_DIR/node_modules/node-pty" && \
       HOME="$TERMUX_HOME" node-gyp rebuild --arch=arm64 ) \
     >"$BUILD_LOG" 2>&1; then
    PTY_NODE="$(find "$BUILD_DIR/node_modules/node-pty/build" \
                     -name 'pty.node' 2>/dev/null | head -1)"
    [ -n "$PTY_NODE" ] && return 0
  fi
  warn "node-pty@${VER} 编译失败，末尾日志："
  tail -8 "$BUILD_LOG" | sed 's/^/  /'
  return 1
}

PTY_NODE=""
BUILD_SUCCESS=0
for VER in "1.0.0" "0.11.0" "1.0.0-beta.12" "0.10.1"; do
  if try_build "$VER"; then
    info "✅ node-pty@${VER} 编译成功"
    BUILD_SUCCESS=1
    break
  fi
done

if [ "$BUILD_SUCCESS" -eq 0 ]; then
  error "所有版本均编译失败，完整日志位于 $BUILD_DIR/build-*.log"
  exit 1
fi

# ── 部署 ─────────────────────────────────────────────────────────────────────
mkdir -p "$TARGET_DIR"
cp "$PTY_NODE" "$TARGET_DIR/pty.node"
chmod 755 "$TARGET_DIR/pty.node"



echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║  ✅ 修复完成！                                   ║${NC}"
echo -e "${GREEN}${BOLD}║  pty.node 已部署至 prebuilds/android-arm64       ║${NC}"
echo -e "${GREEN}${BOLD}║  请重启 Copilot CLI 以启用 bash 工具             ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""
ls -lh "$TARGET_DIR/pty.node"
