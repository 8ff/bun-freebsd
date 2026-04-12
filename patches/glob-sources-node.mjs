import { readFile, writeFile, mkdir, glob as fsGlob } from "node:fs/promises";
import { join, resolve, normalize } from "node:path";
import { fileURLToPath } from "node:url";

const here = fileURLToPath(new URL(".", import.meta.url));
const root = resolve(here, "..");
let total = 0;

async function globSources(output, patterns, excludes = []) {
  const paths = new Set();
  for (const pattern of patterns) {
    for await (const path of fsGlob(pattern, { cwd: root })) {
      if (excludes?.some(e => normalize(path) === normalize(e))) continue;
      paths.add(path);
    }
  }
  total += paths.size;
  const sources =
    [...paths]
      .map(p => normalize(p.replaceAll("\\", "/")))
      .sort((a, b) => a.localeCompare(b))
      .join("\n")
      .trim() + "\n";
  const outPath = join(root, "cmake", "sources", output);
  await mkdir(join(root, "cmake", "sources"), { recursive: true });
  await writeFile(outPath, sources);
}

const input = JSON.parse(await readFile(join(root, "cmake", "Sources.json"), "utf8"));
const start = performance.now();
for (const item of input) {
  await globSources(item.output, item.paths, [
    ...(item.exclude || []),
    "src/bun.js/bindings/GeneratedBindings.zig",
    "src/bun.js/bindings/GeneratedJS2Native.zig",
  ]);
}
console.log(`globbed ${total} sources in ${(performance.now() - start).toFixed(1)}ms`);
