#!/bin/sh
# Build Bun natively on FreeBSD from lwhsu's claude/freebsd-support branch
# plus a small set of additional patches.
#
# Expects FreeBSD 13.2+ amd64 with ~16 GB+ RAM and ~20 GB free disk.
# Takes ~15 minutes on a 16-core box.
#
# Usage:
#   git clone https://github.com/8ff/bun-freebsd.git
#   cd bun-freebsd
#   sh build.sh
#
# Output: ~/src/bun/build/bun (native FreeBSD ELF)

set -eu

# --- Pinned versions ---

LWHSU_BUN_SHA="5a9ab808bd71fe32b08244314896a7e3df54bcb3"
WEBKIT_SHA="4a6a32c32c11ffb9f5a94c310b10f50130bfe6de"
BUN_ZIG_SHA="c031cbebf5b063210473ff5204a24ebfb2492c72"
LLVM_VERSION="21.1.8"

# --- Paths ---

BUILD_ROOT="${BUILD_ROOT:-$HOME/src}"
PATCHES_DIR="$(cd "$(dirname "$0")/patches" && pwd)"

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!!\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31mxxx\033[0m %s\n' "$*" >&2; exit 1; }

# --- Sanity ---

[ "$(uname -s)" = "FreeBSD" ] || fail "FreeBSD only. Got: $(uname -s)"
[ "$(uname -m)" = "amd64" ]   || fail "amd64 only. Got: $(uname -m)"

if command -v doas >/dev/null 2>&1; then SUDO=doas
elif command -v sudo >/dev/null 2>&1; then SUDO=sudo
else SUDO=""; fi

# --- Install build deps ---

say "Installing build dependencies"
$SUDO env ASSUME_ALWAYS_YES=yes pkg install -y \
  cmake ninja zig llvm21 llvm20 python3 rust go perl5 bash pkgconf \
  automake autoconf libtool gperf ruby icu esbuild \
  node22 npm-node22 ripgrep git zstd

# --- Clone sources ---

mkdir -p "$BUILD_ROOT"
cd "$BUILD_ROOT"

if [ ! -d bun ]; then
  say "Cloning lwhsu/bun @ ${LWHSU_BUN_SHA}"
  git clone --filter=blob:none --branch claude/freebsd-support https://github.com/lwhsu/bun.git
fi
( cd bun && git fetch origin "${LWHSU_BUN_SHA}" 2>/dev/null || true; git checkout "${LWHSU_BUN_SHA}" )

if [ ! -d bun/vendor/WebKit ]; then
  say "Cloning oven-sh/WebKit @ ${WEBKIT_SHA}"
  mkdir -p bun/vendor && cd bun/vendor
  git init -q WebKit
  cd WebKit
  git remote add origin https://github.com/oven-sh/WebKit.git
  git fetch --depth=1 --filter=blob:none origin "${WEBKIT_SHA}"
  git checkout FETCH_HEAD
  cd "$BUILD_ROOT"
fi

if [ ! -d bun-zig ]; then
  say "Cloning oven-sh/zig @ ${BUN_ZIG_SHA}"
  git clone --filter=blob:none https://github.com/oven-sh/zig.git bun-zig
  ( cd bun-zig && git fetch --depth=1 origin "${BUN_ZIG_SHA}" && git checkout FETCH_HEAD )
fi

# --- Build Bun's Zig fork ---

if [ ! -x "$HOME/bun-zig-install/bin/zig" ]; then
  say "Building Bun's Zig fork (~10 min)"
  mkdir -p bun-zig/build
  ( cd bun-zig/build && \
    cmake .. -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_PREFIX_PATH=/usr/local/llvm20 \
      -DCMAKE_C_COMPILER=/usr/local/llvm20/bin/clang \
      -DCMAKE_CXX_COMPILER=/usr/local/llvm20/bin/clang++ \
      -DZIG_STATIC_LLVM=OFF \
      -DCMAKE_INSTALL_PREFIX="$HOME/bun-zig-install" \
      -DCMAKE_EXE_LINKER_FLAGS="-L/usr/local/lib -Wl,-rpath,/usr/local/lib" \
      -DCMAKE_SHARED_LINKER_FLAGS="-L/usr/local/lib -Wl,-rpath,/usr/local/lib" && \
    ninja install -j "$(sysctl -n hw.ncpu)" )
  "$HOME/bun-zig-install/bin/zig" version
fi

# --- Apply patches ---

say "Applying patches"

apply_once() {
  patch_path="$1"
  tree_root="$2"
  marker="${tree_root}/.patched-${3}"
  if [ -e "$marker" ]; then
    echo "  (already applied: ${patch_path##*/})"
    return
  fi
  ( cd "$tree_root" && git apply --check "$patch_path" )
  ( cd "$tree_root" && git apply "$patch_path" )
  touch "$marker"
  echo "  applied: ${patch_path##*/}"
}

apply_once "$PATCHES_DIR/0001-bun-freebsd-patches.diff"    "$BUILD_ROOT/bun"              1
apply_once "$PATCHES_DIR/0002-webkit-freebsd-patches.diff" "$BUILD_ROOT/bun/vendor/WebKit" 2

install -m 644 "$PATCHES_DIR/glob-sources-node.mjs" "$BUILD_ROOT/bun/scripts/glob-sources-node.mjs"

# --- Install devDeps (workaround for workspace: refs npm can't resolve) ---

say "Installing build-time npm devDeps"
mkdir -p "$BUILD_ROOT/pk" && cd "$BUILD_ROOT/pk"
[ -f package.json ] || echo '{"name":"tmp","version":"1.0.0"}' > package.json
NODE_OPTIONS="${NODE_OPTIONS:-} --dns-result-order=ipv6first" \
  npm install --no-package-lock --ignore-scripts --no-audit --no-fund \
    peechy@0.4.34 @lezer/cpp@^1.1.3 @lezer/common@^1.2.3 mitata@^0.1.14 source-map-js@^1.2.1
mkdir -p "$BUILD_ROOT/bun/node_modules"
for d in peechy @lezer mitata source-map-js; do
  [ -d "node_modules/$d" ] && cp -R "node_modules/$d" "$BUILD_ROOT/bun/node_modules/"
done

NPM_GLOBAL="$HOME/.npm-global"
mkdir -p "$NPM_GLOBAL"
NODE_OPTIONS="${NODE_OPTIONS:-} --dns-result-order=ipv6first" \
  npm install -g --prefix "$NPM_GLOBAL" esbuild@0.27.1

# --- Generate cmake/sources/*.txt ---

say "Generating source lists"
cd "$BUILD_ROOT/bun"
node scripts/glob-sources-node.mjs

# --- Configure + build ---

say "Configuring cmake"
mkdir -p build && cd build
export PATH="$HOME/bun-zig-install/bin:/usr/local/llvm21/bin:$PATH"
export NODE_PATH="$NPM_GLOBAL/lib/node_modules"
export NODE_OPTIONS="--dns-result-order=ipv6first"

cmake .. -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DUSE_SYSTEM_ZIG=ON \
  -DWEBKIT_LOCAL=ON \
  -DLLVM_VERSION="${LLVM_VERSION}" \
  -DZIG_EXECUTABLE="$HOME/bun-zig-install/bin/zig"

say "Building (~15 min on 16 cores)"
ninja -j "$(sysctl -n hw.ncpu)" all

# --- Verify ---

if [ -x "$BUILD_ROOT/bun/build/bun" ]; then
  say "Build succeeded:"
  ls -la "$BUILD_ROOT/bun/build/bun"
  "$BUILD_ROOT/bun/build/bun" --version
  file "$BUILD_ROOT/bun/build/bun"
else
  fail "bun binary not found"
fi
