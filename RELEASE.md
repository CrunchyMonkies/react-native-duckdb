# Release Process

There are **two** independent release channels:

| Channel | Trigger | Registry | Native code |
| --- | --- | --- | --- |
| **Public (npm.org)** | push a `v*` tag | npmjs.org, package name `react-native-duckdb` | source only — compiled on the consumer's machine |
| **CrunchyMonkies prebuilt** | push to the `production` branch | GitHub Packages, scoped name `@crunchymonkies/react-native-duckdb` | prebuilt `libRNDuckDB.so` for all four Android ABIs, bundled in the tarball |

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

## Prebuilt Android release (GitHub Packages)

The [`production-release` workflow](.github/workflows/production-release.yml) publishes a
**prebuilt Android** build to the CrunchyMonkies GitHub Packages npm registry. Unlike the public
npm package (which compiles DuckDB on the consumer's machine), this package ships compiled
`libRNDuckDB.so` binaries so consuming apps skip the native build entirely.

### How to release

1. Bump `version` in `package/package.json` and merge to the `production` branch.
2. Push `production` (or run the workflow manually via **workflow_dispatch**). The version is taken
   from `package/package.json` as-is — publishing fails if that version already exists in the
   registry, so always bump first.
3. Confirm the package appears under
   [github.com/orgs/CrunchyMonkies/packages](https://github.com/orgs/CrunchyMonkies/packages).

### What the workflow does

1. Checks out the repo **with the DuckDB submodule** (`submodules: recursive`).
2. Installs JDK 17, Bun, Node, the Android SDK, NDK `27.1.12297006`, and CMake `3.22.1`.
3. Cross-compiles `libRNDuckDB.so` for **all four ABIs** — `armeabi-v7a`, `x86`, `x86_64`,
   `arm64-v8a` — by running `:react-native-duckdb:assembleRelease` through the example app's gradle
   context (the library cannot build standalone because it depends on `react-native-nitro-modules`).
4. Extracts the per-ABI `.so` from the produced AAR into `package/android/src/main/jniLibs/<abi>/`.
5. Builds the JS package, scopes the name to `@crunchymonkies/react-native-duckdb`, verifies all
   four `.so` are in the tarball, and runs `npm publish --ignore-scripts` to GitHub Packages.

Authentication uses the built-in `GITHUB_TOKEN` (`packages: write`) — no extra secret is required.

### How consumers use the prebuilt package

The package ships `android/src/main/jniLibs/<abi>/libRNDuckDB.so`. The library's
`package/android/build.gradle` auto-detects these prebuilt binaries and **skips the CMake source
build**, so consuming apps do not need the NDK, the DuckDB submodule, or OpenSSL/curl. To force a
source build instead (e.g. to customize the bundled extensions), set `-PRNDuckDB_prebuilt=false`.

### Limitations

- **Fixed extension set.** The prebuilt `.so` bakes in the extensions configured at build time
  (currently the example app's set: `core_functions, parquet, json, icu, sqlite_scanner, httpfs,
  fts, vss`). Consumers cannot reconfigure extensions without a source build
  (`-PRNDuckDB_prebuilt=false`). `httpfs`/`vss` are unavailable on the 32-bit ABIs by design.
- **Nitro/RN version coupling.** The binaries are compiled against
  `react-native-nitro-modules@0.33.9` / `react-native@0.82.1`. Consuming apps must use compatible
  Nitro and React Native versions, or the native module will fail to load.
- **Scoped name.** GitHub Packages requires the org scope, so the install/import name is
  `@crunchymonkies/react-native-duckdb` (the public npm package remains `react-native-duckdb`).
- **iOS is not covered** by this flow — iOS still builds from source at pod-install time.
