# bun-freebsd

Build [Bun](https://github.com/oven-sh/bun) natively on FreeBSD. Based on [Li-Wen Hsu's `claude/freebsd-support` branch](https://github.com/lwhsu/bun/tree/claude/freebsd-support) with additional patches for WebKit, bootstrap toolchain, and cmake wiring.

## Build

```sh
git clone https://github.com/8ff/bun-freebsd.git
cd bun-freebsd
sh build.sh
```

Requires FreeBSD 13.2+ amd64, ~16 GB RAM, ~20 GB disk. The script installs all dependencies via `pkg`, clones the source trees, builds Bun's Zig fork, applies patches, and compiles Bun + WebKit/JSC.

Output: `~/src/bun/build/bun` — a native FreeBSD ELF.

## Running Claude Code

After building, grab `cli.js` from the npm package (while it's still available — Anthropic has said this is being deprecated):

```sh
mkdir -p ~/.npm-global
npm config set prefix ~/.npm-global
npm install -g @anthropic-ai/claude-code
```

Then run it under your native bun:

```sh
~/src/bun/build/bun ~/.npm-global/lib/node_modules/@anthropic-ai/claude-code/cli.js --version
```

For convenience, create a wrapper:

```sh
mkdir -p ~/.local/bin
cat > ~/.local/bin/claude <<'EOF'
#!/bin/sh
exec ~/src/bun/build/bun ~/.npm-global/lib/node_modules/@anthropic-ai/claude-code/cli.js "$@"
EOF
chmod +x ~/.local/bin/claude
```

**Note:** `cli.js` is Anthropic's proprietary code (not included in this repo). Anthropic has stated they plan to deprecate the npm package. This repo only contains the Bun build script and patches — sourcing `cli.js` is on you.

## What the patches fix

~150 lines on top of lwhsu's branch:

- **WebKit `AvailableMemory.cpp`** — FreeBSD branch was using Linux-only `struct sysinfo`; replaced with `sysctlbyname("hw.physmem")`
- **WebKit `RAMSize.cpp`** — removed FreeBSD from `#include <sys/sysinfo.h>` guard (Linux-only header)
- **`SetupWebKit.cmake`** — pass `USE_SYSTEM_MALLOC=ON` to JSC on FreeBSD (lwhsu had a comment for this but never wired it)
- **`codegen-ts-node-runner.mjs`** — fix esbuild output format for Node bootstrap: strip `__commonJS` wrapper, remove `init_define_*` no-ops, disable `keepNames` to avoid `__name()` helper
- **`bundle-functions.ts`** — remove `if (import.meta.main)` guard that esbuild's `--define` constant-folds to `if (true)` in bundled output
- **`glob-sources-node.mjs`** (new) — Node port of Bun-requiring `glob-sources.mjs` for bootstrap on hosts without an existing Bun binary
- **`stream.ts`** — fix internal module import typo: `internal/stream.promises` → `internal/stream/promises`
- **WebKit `Tools/CMakeLists.txt`** — skip `TestWebKitAPI` on FreeBSD to avoid nonessential API test build failures
- **`build.sh`** — add one-shot retry with known FreeBSD workarounds for `cares`/`libarchive` build failures (`-lz` for `bsdtar`)

## Credit

- [Li-Wen Hsu (@lwhsu)](https://github.com/lwhsu) — ~90% of the FreeBSD port
- Upstream: [oven-sh/bun](https://github.com/oven-sh/bun), [oven-sh/WebKit](https://github.com/oven-sh/WebKit), [oven-sh/zig](https://github.com/oven-sh/zig)
