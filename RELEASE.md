# Release Process

There are **two** independent release channels:

| Channel | Trigger | Registry | Native code |
| --- | --- | --- | --- |
| **Public (npm.org)** | push a `v*` tag | npmjs.org, package name `react-native-duckdb` | source only — compiled on the consumer's machine |
| **CrunchyMonkies prebuilt** | push to the `production` branch | npm on GitHub Packages (`@crunchymonkies/react-native-duckdb`) + prebuilt `.so` on public GitHub Releases | Gradle downloads the matching `libRNDuckDB.so` per ABI from the Release at build time (falls back to source) |

The public tag flow is described below. The prebuilt Android flow is described in
[Prebuilt Android release (GitHub Packages)](#prebuilt-android-release-github-packages).

## How to Release

1. Update the version in `package/package.json`:
   ```bash
   # Edit package/package.json "version" field
   ```

2. Commit the version bump:
   ```bash
   git commit -am "chore: bump version to X.Y.Z"
   ```

3. Create and push the tag:
   ```bash
   git tag vX.Y.Z
   git push && git push --tags
   ```

4. **Approve the publish** in the [GitHub Actions UI](https://github.com/pranshuchittora/react-native-duckdb/actions) — the workflow will pause and wait for manual approval before publishing.

5. Verify the package on [npmjs.com/package/react-native-duckdb](https://www.npmjs.com/package/react-native-duckdb).

## What the Workflow Does

When a `v*` tag is pushed, the [release workflow](.github/workflows/release.yml) runs two jobs:

**`publish`** — Builds and publishes to npm:
- Installs dependencies with Bun
- Runs `bun run build` (TypeScript compilation + Expo plugin build)
- Validates tarball contents with `npm pack --dry-run`
- Publishes with `npm publish --provenance`

**`github-release`** — Creates a GitHub Release from the tag with auto-generated release notes from commits since the previous tag.

## What Gets Published

Included in the npm package:
- `src/` — TypeScript source
- `lib/` — Compiled JavaScript
- `cpp/` — C++ native source
- `android/` — Android build configuration
- `ios/` — iOS build configuration (podspec)
- `nitrogen/` — Nitro Modules codegen output
- `plugin/` — Expo config plugin (compiled)
- `app.plugin.js` — Expo plugin entry point
- `scripts/` — Build-time scripts (extension configuration, DuckDB download)
- `vendor/` — DuckDB version markers for build caching

**Not published:** DuckDB source code (downloaded at consumer build time), build artifacts, test files, example app.

## Security Model

### Environment Protection

The `npm` GitHub environment requires manual approval before any publish proceeds. This prevents accidental releases from tag pushes — a human must explicitly approve every publish in the GitHub Actions UI.

### Provenance Attestation

Every published version includes an [npm provenance attestation](https://docs.npmjs.com/generating-provenance-statements) — a cryptographic proof linking the package to this GitHub repository and the specific commit that produced it. You can verify this on the npm package page.

### Token Isolation

The `NPM_TOKEN` secret is scoped to the `npm` environment, not available as a general repository secret. It is only accessible during approved publish runs.

### Clean Git History

The entire git history (94 commits at time of initial release) has been audited — zero credentials, API keys, or tokens in any commit.

### Release Safeguards

The release pipeline includes multiple safeguards:
- **Human approval gate** before every npm publish
- **Provenance attestation** proving the package was built from this repo
- **`prepublishOnly` script** ensures a clean build before publish
- **`npm pack --dry-run`** verification step in CI
- **No pre-release complexity** — every publish goes to `latest`, no accidental beta tags

## Prebuilt Android release (download at build time)

The [`production-release` workflow](.github/workflows/production-release.yml) cross-compiles the
native Android library for two **feature sets** (`core` and `all`) and uploads them to a **public
GitHub Release**. Consumer Gradle builds select a feature set via the `DUCKDB_FEATURES` env var and
**download the matching `libRNDuckDB.so` for each ABI at build time** instead of compiling DuckDB
from source. The scoped npm package (`@crunchymonkies/react-native-duckdb`, on GitHub Packages)
carries the JS code plus the Gradle logic that performs the download (and the source-build fallback).

### `DUCKDB_FEATURES`

| `DUCKDB_FEATURES`            | Behavior |
| --------------------------- | -------- |
| `core` (default when unset) | Download the prebuilt **core** release; on failure → clone DuckDB + source-build the core set |
| `all`                       | Download the prebuilt **all** release; on failure → clone DuckDB + source-build the full set |
| `ext_a,ext_b,…`             | Custom comma-delimited extension list → **always** clone DuckDB + source-build exactly those |

Feature-set definitions (kept in sync between `package/android/build.gradle` and this workflow):

- **core** = `core_functions,parquet,json`
- **all**  = `core_functions,parquet,json,icu,sqlite_scanner,httpfs,fts,vss`
  (every extension that cross-compiles for Android/iOS; `delta` is excluded — it needs a Rust
  toolchain + vcpkg — as are the unvalidated `autocomplete`/`tpch`/`tpcds`. Use a custom
  `DUCKDB_FEATURES` list to add any of those.)

Set it as an environment variable (`DUCKDB_FEATURES=all ./gradlew …` / in CI) or as a Gradle
property (`-PDUCKDB_FEATURES=all`).

### How to release

1. Bump `version` in `package/package.json` and merge to the `production` branch.
2. Push `production` (or run the workflow manually via **workflow_dispatch**). The version is taken
   from `package/package.json` as-is and is used for both the npm version and the Release tag
   (`vX.Y.Z`) — always bump first.
3. Confirm the Release `vX.Y.Z` exists with the per-ABI `.so` assets at
   [github.com/CrunchyMonkies/react-native-duckdb/releases](https://github.com/CrunchyMonkies/react-native-duckdb/releases),
   and the npm package under
   [github.com/orgs/CrunchyMonkies/packages](https://github.com/orgs/CrunchyMonkies/packages).

### What the workflow does

Three jobs:

1. **`release-init`** — reads the version from `package/package.json` and creates the public Release
   `vX.Y.Z` if it does not already exist (so the parallel build matrix can upload into it).
2. **`build`** (matrix over `features: [core, all]`) — checks out **with the DuckDB submodule**
   (`submodules: recursive`); installs JDK 17, Bun `1.3.14`, the Android SDK, NDK `27.1.12297006`,
   CMake `3.22.1`; then cross-compiles `libRNDuckDB.so` for **all four ABIs** by running
   `:react-native-duckdb:assembleRelease -PRNDuckDB_prebuilt=false -PDUCKDB_FEATURES=<features>`
   through the example app's gradle context (the library can't build standalone because it depends on
   `react-native-nitro-modules`). It extracts each per-ABI `.so` from the AAR, names it
   `libRNDuckDB-<version>-<features>-<abi>.so`, writes a `.sha256` sidecar, and uploads them to the
   Release. The `core` and `all` matrix legs run in parallel, so wall-clock ≈ one `all` build.
3. **`publish-npm`** — builds the JS package, scopes the name to `@crunchymonkies/react-native-duckdb`,
   and runs `npm publish --ignore-scripts` to GitHub Packages.

Authentication uses the built-in `GITHUB_TOKEN` (`contents: write` for the Release, `packages: write`
for npm) — no extra secret is required.

### How consumers' builds pull the prebuilt library

When a consuming app builds, `package/android/build.gradle` resolves `DUCKDB_FEATURES` (default
`core`). For `core`/`all` it **attempts to download** the matching prebuilt
`libRNDuckDB-<version>-<features>-<abi>.so` for each target ABI from the public Release, verifies it
against the published `.sha256`, and skips the CMake build. No authentication is required (the Release
assets are public). Downloads are cached under the module's Gradle `build/prebuilt-jniLibs/<features>/`
directory, so only the first build hits the network.

If `DUCKDB_FEATURES` is a custom list, or a `core`/`all` download fails (offline, missing asset), the
build **falls back to compiling from source**. The build scripts ship inside the package
(`package/scripts`, included in the npm tarball) and the DuckDB sources are cloned at the pinned tag
on demand (via `package/scripts/clone-duckdb.sh`) into the installed package directory — so the
source build works from a published install (it just needs network + the native toolchain). iOS uses
the same mechanism at pod-install time (`package/scripts/build-duckdb-ios.sh`, which also honors
`DUCKDB_FEATURES`). Override knobs (env var, `gradle.properties`, or `-P…`):

- `DUCKDB_FEATURES=core|all|<csv>` — feature set (see table above).
- `RNDuckDB_prebuilt=false` — always build from source, never download.
- `RNDuckDB_prebuiltVersion=X.Y.Z` — pull a specific release version.
- `RNDuckDB_prebuiltRepo=owner/repo` — pull from a different repo/fork.
- `RNDuckDB_prebuiltBaseUrl=URL` — point at a fully custom asset base URL (e.g. a mirror).

### Limitations

- **Prebuilt feature sets are fixed.** Only `core` and `all` are published prebuilt; any other set
  triggers a source build. `httpfs`/`vss` are unavailable on the 32-bit ABIs by design, so the `all`
  prebuilt for `armeabi-v7a`/`x86` omits httpfs.
- **Source fallback needs a toolchain + network.** A custom/failed-download build requires git, the
  NDK, CMake and Node; out-of-tree extensions are git-fetched at CMake time, and `all` additionally
  builds OpenSSL/curl (64-bit). The `core` fallback is light (in-tree only). DuckDB is **not** shipped
  in the npm tarball; the fallback clones it on demand. For published consumers, prefer the
  `core`/`all` prebuilt download and keep the Release assets available for every published version.
- **Nitro/RN version coupling.** The binaries are compiled against
  `react-native-nitro-modules@0.33.9` / `react-native@0.82.1`. Consuming apps must use compatible
  Nitro and React Native versions, or the native module will fail to load.
- **Scoped name.** GitHub Packages requires the org scope, so the install/import name is
  `@crunchymonkies/react-native-duckdb` (the public npm package remains `react-native-duckdb`).
- **iOS is not covered** by this flow — iOS still builds from source at pod-install time.
