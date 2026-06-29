// Guard: every minifier named in vite.config.ts (build.minify / build.cssMinify)
// must be a declared dependency in package.json.
//
// terser, esbuild and lightningcss are Vite *optional* peers used only as config
// STRINGS (never `import`ed). Because they're never imported, depcheck
// (`make deps-prune-check`) does NOT flag their removal, and a frozen-lockfile
// install keeps passing (the committed lockfile still contains them). But a full
// re-resolve (Renovate `lockFileMaintenance`) can drop the optional-peer wiring,
// and the build then fails non-deterministically with
// `[plugin vite:css-post] Error: Cannot find package '<minifier>'`.
//
// Declaring each minifier as a direct dependency makes the wiring deterministic.
// This gate fails the moment a config-referenced minifier is no longer declared,
// so the silent-removal hole is closed at lint time instead of on the next
// weekly lockfile maintenance. See viteapp PR #326.
import { readFileSync } from "node:fs";

// The minifiers Vite accepts as `minify` / `cssMinify` values that resolve to a
// real npm package (i.e. an optional peer that must be installed). Boolean values
// (`true`/`false`) need no package and are ignored.
const MINIFIER_PACKAGES = new Set(["terser", "esbuild", "lightningcss"]);

const root = new URL("../", import.meta.url);
const config = readFileSync(new URL("vite.config.ts", root), "utf8");
const pkg = JSON.parse(readFileSync(new URL("package.json", root), "utf8"));

const declared = new Set([
  ...Object.keys(pkg.dependencies ?? {}),
  ...Object.keys(pkg.devDependencies ?? {}),
]);

// Extract the quoted string value of every `minify:` / `cssMinify:` key.
const used = new Set();
for (const m of config.matchAll(/\b(?:css)?[Mm]inify\s*:\s*["']([^"']+)["']/g)) {
  used.add(m[1]);
}

const relevant = [...used].filter((v) => MINIFIER_PACKAGES.has(v));
const missing = relevant.filter((v) => !declared.has(v));

if (missing.length > 0) {
  console.error(
    `✗ minifier(s) referenced in vite.config.ts but NOT declared in package.json: ${missing.join(", ")}`,
  );
  console.error(
    "  These are Vite optional-peer minifiers (used as config strings, never imported);",
  );
  console.error(
    "  depcheck won't flag them and frozen-lockfile CI still passes, but the build breaks",
  );
  console.error(
    "  non-deterministically on the next full lockfile re-resolve. Add each to devDependencies.",
  );
  process.exit(1);
}

console.log(
  `✓ minifier deps declared: ${relevant.length ? relevant.join(", ") : "(none referenced)"}`,
);
