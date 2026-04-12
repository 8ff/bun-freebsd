# bun-freebsd

Build [Bun](https://github.com/oven-sh/bun) natively on FreeBSD. Based on [Li-Wen Hsu's `claude/freebsd-support` branch](https://github.com/lwhsu/bun/tree/claude/freebsd-support) with additional patches for WebKit, bootstrap toolchain, and cmake wiring.

## Build

```sh
git clone https://github.com/8ff/bun-freebsd.git
cd bun-freebsd
sh build.sh
```

Requires FreeBSD 13.2+ amd64, ~16 GB RAM, ~20 GB disk. Takes ~15 minutes on 16 cores. The script installs all dependencies via `pkg`, clones the source trees, builds Bun's Zig fork, applies patches, and compiles Bun + WebKit/JSC.

Output: `~/src/bun/build/bun` — a native FreeBSD ELF.

## What the patches fix

~150 lines on top of lwhsu's branch:

- **WebKit `AvailableMemory.cpp`** — FreeBSD branch was using Linux-only `struct sysinfo`; replaced with `sysctlbyname("hw.physmem")`
- **WebKit `RAMSize.cpp`** — removed FreeBSD from `#include <sys/sysinfo.h>` guard (Linux-only header)
- **`SetupWebKit.cmake`** — pass `USE_SYSTEM_MALLOC=ON` to JSC on FreeBSD (lwhsu had a comment for this but never wired it)
- **`codegen-ts-node-runner.mjs`** — fix esbuild output format for Node bootstrap: strip `__commonJS` wrapper, remove `init_define_*` no-ops, disable `keepNames` to avoid `__name()` helper
- **`bundle-functions.ts`** — remove `if (import.meta.main)` guard that esbuild's `--define` constant-folds to `if (true)` in bundled output
- **`glob-sources-node.mjs`** (new) — Node port of Bun-requiring `glob-sources.mjs` for bootstrap on hosts without an existing Bun binary

## Credit

- [Li-Wen Hsu (@lwhsu)](https://github.com/lwhsu) — ~90% of the FreeBSD port
- Upstream: [oven-sh/bun](https://github.com/oven-sh/bun), [oven-sh/WebKit](https://github.com/oven-sh/WebKit), [oven-sh/zig](https://github.com/oven-sh/zig)
