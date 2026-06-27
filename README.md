<p align="center">
  <img src="docs/assets/react-native-duckdb-banner.png" alt="React Native DuckDB" width="100%" />
</p>

<p align="center">
  <a href="https://www.npmjs.com/package/react-native-duckdb"><img src="https://img.shields.io/npm/v/react-native-duckdb.svg" alt="npm version" /></a>
  <a href="https://github.com/pranshuchittora/react-native-duckdb/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License" /></a>
  <img src="https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey.svg" alt="Platform" />
  <img src="https://img.shields.io/badge/DuckDB-v1.4.4-FFF100.svg" alt="DuckDB Version" />
</p>

---

The analytical database for React Native. Run OLAP queries, full-text search, and vector similarity search on iOS and Android with native C++ performance via [Nitro Modules](https://nitro.margelo.com/).

- Columnar OLAP engine (not row-based OLTP like SQLite)
- Full-text search with BM25 ranking and 27 language stemmers
- Vector similarity search with HNSW indexing for on-device RAG/AI
- Remote data queries over HTTPS (Parquet, CSV, JSON, Hugging Face datasets)
- Streaming results for large datasets without OOM
- Bulk insert via Appender API
- Columnar typed array access (Float64Array, BigInt64Array)
- 30+ DuckDB types including HUGEINT, DECIMAL, ARRAY, MAP, STRUCT
- Query cancellation, progress callbacks, JSON profiling
- Expo config plugin for managed workflow

## Try It Now

Download DuckDB Explorer — a free companion app to try everything before writing a single line of code. Interactive SQL runner, Hugging Face dataset browser, full-text search, vector similarity search, and more.

<p align="center">
  <a href="https://apps.apple.com/app/duckdb-explorer/id6742978562"><img src="https://img.shields.io/badge/App_Store-0D96F6?style=for-the-badge&logo=app-store&logoColor=white" alt="App Store" /></a>
  &nbsp;
  <a href="https://play.google.com/store/apps/details?id=com.rnduckdbexample"><img src="https://img.shields.io/badge/Google_Play-414141?style=for-the-badge&logo=google-play&logoColor=white" alt="Google Play" /></a>
</p>

<p align="center">
  <img src="docs/screenshots/screenshot-1.png" width="13%" />
  <img src="docs/screenshots/screenshot-2.png" width="13%" />
  <img src="docs/screenshots/screenshot-3.png" width="13%" />
  <img src="docs/screenshots/screenshot-4.png" width="13%" />
  <img src="docs/screenshots/screenshot-5.png" width="13%" />
  <img src="docs/screenshots/screenshot-6.png" width="13%" />
  <img src="docs/screenshots/screenshot-7.png" width="13%" />
</p>

## Installation

There are two ways to install, depending on whether you want to **build the native library from source** or **download prebuilt Android binaries**. Both ship the same JavaScript/TypeScript API.

### Option A — Public npm (builds from source)

```bash
npm install react-native-duckdb react-native-nitro-modules
```

DuckDB is cloned and compiled the first time you build the app. Android needs `git`, the Android NDK and CMake; iOS builds at `pod install` time and needs Xcode. For iOS, run `pod install` after installing.

### Option B — GitHub Packages (prebuilt Android binaries)

The `@crunchymonkies/react-native-duckdb` package is published to GitHub Packages and ships the Gradle logic that downloads prebuilt per-ABI Android binaries (`.so`) from the [CrunchyMonkies releases](https://github.com/CrunchyMonkies/react-native-duckdb/releases), falling back to a source build if a download isn't available.

Add a scope mapping to your project `.npmrc` so npm resolves `@crunchymonkies` from GitHub Packages:

```ini
@crunchymonkies:registry=https://npm.pkg.github.com
//npm.pkg.github.com/:_authToken=${GITHUB_TOKEN}
```

`GITHUB_TOKEN` must be a GitHub personal access token with the `read:packages` scope (required to install from GitHub Packages — the prebuilt `.so` themselves are on public Releases and need no auth). Then:

```bash
npm install @crunchymonkies/react-native-duckdb react-native-nitro-modules
```

Import from the scoped name in this case:

```ts
import { HybridDuckDB } from '@crunchymonkies/react-native-duckdb'
```

For iOS, run `pod install` — iOS always builds from source (see [Native Build & Distribution](#native-build--distribution)).

## Native Build & Distribution

On **Android**, the native DuckDB library is either **downloaded prebuilt** or **compiled from source**. On **iOS**, it is always compiled from source at `pod install` time. Both platforms honor the same `DUCKDB_FEATURES` selection.

### Feature sets — `DUCKDB_FEATURES`

| `DUCKDB_FEATURES` | Behavior |
| --- | --- |
| `core` (default) | Download the prebuilt **core** release; on failure → clone DuckDB and source-build the core set |
| `all` | Download the prebuilt **all** release; on failure → clone DuckDB and source-build the full set |
| `ext_a,ext_b,…` | Always source-build exactly the extensions you list |

- **core** = `core_functions,parquet,json`
- **all** = `core_functions,parquet,json,icu,sqlite_scanner,httpfs,fts,vss`

`delta`, `autocomplete`, `tpch` and `tpcds` are excluded from `all` (they need extra toolchains or are unvalidated) — pass an explicit comma-separated list to source-build them.

Set it via environment variable or Gradle property:

```bash
# Environment variable (Android + iOS)
DUCKDB_FEATURES=all npx react-native run-android

# Gradle property
./gradlew :react-native-duckdb:assembleRelease -PDUCKDB_FEATURES=all
```

Expo apps set the extension list through the config plugin (see the [Extensions](#extensions) section); iOS additionally reads the env var / `Podfile.properties.json`.

### Prebuilt binaries

Prebuilt Android binaries are published per release to **CrunchyMonkies**:

- **Releases (binaries):** https://github.com/CrunchyMonkies/react-native-duckdb/releases — per-ABI assets named `libRNDuckDB-<version>-<features>-<abi>.so` with a `.sha256` sidecar that the build verifies.
- **Package (GitHub Packages):** https://github.com/orgs/CrunchyMonkies/packages — the `@crunchymonkies/react-native-duckdb` npm package.

### Build override knobs (Android)

Set via environment variable, `gradle.properties`, or `-P` flags:

| Property | Effect |
| --- | --- |
| `RNDuckDB_prebuilt=false` | Force a source build, skip the prebuilt download |
| `RNDuckDB_prebuiltVersion` | Release version to pull (default: the package version) |
| `RNDuckDB_prebuiltRepo` | GitHub repo to pull from (default: `CrunchyMonkies/react-native-duckdb`) |
| `RNDuckDB_prebuiltBaseUrl` | Full base URL for assets (default: `https://github.com/<repo>/releases/download/v<version>`) |

### Caveats

- Only `core` and `all` are published as prebuilt; any custom feature list triggers a source build.
- `httpfs`/`vss` are unavailable on the 32-bit ABIs, so the `all` prebuilt omits them on `armeabi-v7a`/`x86`.
- A source fallback needs the toolchain (git, NDK, CMake, Node) and network access; out-of-tree extensions are fetched at build time and `all` also builds OpenSSL/curl. DuckDB is **not** shipped in the npm tarball — it is cloned on demand.
- **Nitro/RN version coupling.** The binaries are compiled against `react-native-nitro-modules@0.35.9` / `react-native@0.82.1`. Consuming apps must use compatible Nitro and React Native versions or the native module will fail to load.
- iOS is not covered by the prebuilt flow; it always builds from source at pod-install time.

See [RELEASE.md](RELEASE.md) for the full release and build reference.

## Quick Start

```ts
import { HybridDuckDB } from 'react-native-duckdb'

const db = HybridDuckDB.open(':memory:', {})

db.executeSync('CREATE TABLE users (id INTEGER, name VARCHAR, score DOUBLE)')
db.executeSync("INSERT INTO users VALUES (1, 'Alice', 95.5), (2, 'Bob', 87.3)")

const result = db.executeSync('SELECT * FROM users ORDER BY score DESC')
const rows = result.toRows()
// [{ id: 1, name: 'Alice', score: 95.5 }, { id: 2, name: 'Bob', score: 87.3 }]

db.close()
```

## Features

### Configuration

```ts
const db = HybridDuckDB.open(':memory:', {
  threads: '2',
  memory_limit: '256MB',
  default_order: 'DESC',
})
```

### Async Execution

```ts
const result = await db.execute('SELECT * FROM large_table WHERE category = ?', ['electronics'])
const rows = result.toRows()
```

### Prepared Statements

```ts
const stmt = db.prepare('SELECT * FROM users WHERE age > ?')
stmt.bind([21])
const result = stmt.executeSync()
stmt.finalize()
```

### Named Parameters

```ts
const result = db.executeSyncNamed(
  'SELECT * FROM users WHERE name = $name AND age > $age',
  { $name: 'Alice', $age: 21 }
)
```

### Query Cancellation

```ts
const promise = db.execute('SELECT * FROM generate_series(1, 100000000)')
setTimeout(() => db.cancel(), 50)
```

### Profiling

```ts
db.executeSync("PRAGMA enable_profiling='json'")
db.executeSync('SELECT * FROM large_table ORDER BY score DESC')
const profile = db.getProfilingInfo() // JSON string with timing breakdown
```

### Progress Callbacks

```ts
db.setProgressCallback((percentage) => {
  console.log(`Query progress: ${percentage}%`)
})
const result = await db.execute('SELECT * FROM big_join')
db.removeProgressCallback()
```

### Batch Execution

```ts
const { rowsAffected } = db.executeBatchSync([
  { query: 'INSERT INTO logs VALUES (?, ?)', params: [1, 'start'] },
  { query: 'INSERT INTO logs VALUES (?, ?)', params: [2, 'end'] },
])
```

### Transactions

```ts
import { executeTransaction } from 'react-native-duckdb'

const count = await executeTransaction(db, async (tx) => {
  tx.executeSync('INSERT INTO orders VALUES (1, 99.99)')
  tx.executeSync('UPDATE inventory SET stock = stock - 1 WHERE id = 1')
  return tx.executeSync('SELECT count(*) as n FROM orders').toRows()[0].n
})
// auto-commits on success, auto-rolls-back on error
```

### Multi-Database

```ts
db.attach('/path/to/other.duckdb', 'analytics', { readOnly: true })
const result = db.executeSync('SELECT * FROM analytics.events LIMIT 10')
db.detach('analytics')
```

### Database Paths

```ts
import { DOCUMENTS_PATH, LIBRARY_PATH } from 'react-native-duckdb'

const db = HybridDuckDB.open(`${LIBRARY_PATH}/analytics.duckdb`, {})
// iOS: NSLibraryDirectory (no iCloud backup)
// Android: getFilesDir()
```

See [docs/database-location.md](docs/database-location.md) for all available paths, backup behavior, and platform details.

### Delete Database

```ts
HybridDuckDB.deleteDatabase(`${DOCUMENTS_PATH}/old.duckdb`)
```

## Streaming Large Datasets

Process millions of rows chunk-by-chunk without loading everything into memory.

```ts
import { streamChunks } from 'react-native-duckdb'

const stream = await db.stream('SELECT * FROM large_table')
for await (const chunk of streamChunks(stream)) {
  processChunk(chunk.toRows())
}
```

See [docs/streaming.md](docs/streaming.md) for the Appender API, progress callbacks, and ETL patterns.

## Full-Text Search

BM25-ranked search with 27 language stemmers. Requires the `fts` extension.

```ts
db.executeSync("LOAD 'fts'")
db.executeSync("PRAGMA create_fts_index('docs', 'id', 'title', 'body', stemmer='english')")

const results = db.executeSync(`
  SELECT *, fts_main_docs.match_bm25(id, 'search query') AS score
  FROM docs WHERE score IS NOT NULL ORDER BY score DESC
`)
```

See [docs/fts.md](docs/fts.md) for multi-language stemming, field-specific search, and limitations.

## Vector Similarity Search

HNSW-indexed nearest-neighbor queries for on-device semantic search and RAG. Requires the `vss` extension.

```ts
db.executeSync("LOAD 'vss'")
db.executeSync('CREATE TABLE docs (id INTEGER, vec FLOAT[384])')
db.executeSync("CREATE INDEX idx ON docs USING HNSW (vec) WITH (metric = 'cosine')")

const similar = db.executeSync(`
  SELECT id, array_cosine_distance(vec, $query::FLOAT[384]) AS distance
  FROM docs ORDER BY distance LIMIT 10
`)
```

See [docs/vss.md](docs/vss.md) for distance metrics, use cases, and HNSW tuning.

## Extensions

Extensions are statically linked at build time, which means your selection also determines whether a prebuilt binary can be used or a source build is required — see [Native Build & Distribution](#native-build--distribution) and the `DUCKDB_FEATURES` feature sets. Configure in `package.json` (bare) or `app.json` (Expo):

```json
{
  "react-native-duckdb": {
    "build": {
      "extensions": ["core_functions", "parquet", "json"]
    }
  }
}
```

| Extension | Description |
|-----------|-------------|
| `core_functions` | Essential SQL functions (sum, avg, uuid, etc.) — **recommended** |
| `parquet` | Apache Parquet file format |
| `json` | JSON file format |
| `httpfs` | Remote file access over HTTPS |
| `fts` | BM25 full-text search |
| `vss` | HNSW vector similarity search |
| `sqlite_scanner` | Read SQLite databases |
| `icu` | Unicode collation and locale |
| `delta` | Delta Lake table format |
| `autocomplete` | SQL autocomplete |
| `tpch` / `tpcds` | Benchmark data generators |

See [docs/extensions.md](docs/extensions.md) for configuration details and per-extension guides.

**Expo:** Add to `app.json` plugins:

```json
["react-native-duckdb", { "extensions": ["core_functions", "parquet"] }]
```

See [docs/expo.md](docs/expo.md) for the full Expo guide.

## How It Compares

react-native-duckdb is an **OLAP** (Online Analytical Processing) database — optimized for analytical queries over large datasets. The libraries below are **OLTP** (Online Transaction Processing) databases — optimized for many small read/write transactions typical in app state management.

These are complementary paradigms. Use SQLite-based libraries for your app's transactional data (users, settings, state). Use DuckDB for analytics, search, and data processing.

| Feature | react-native-duckdb | nitro-sqlite | op-sqlite | WatermelonDB |
|---------|---------------------|--------------|-----------|--------------|
| **Engine** | DuckDB (columnar OLAP) | SQLite (row OLTP) | SQLite (row OLTP) | SQLite (row OLTP) |
| **Native bridge** | Nitro Modules (JSI) | Nitro Modules (JSI) | JSI | JSI |
| **Parquet/CSV/JSON file queries** | Yes | No | No | No |
| **Remote data (HTTPS)** | Yes (httpfs) | No | No | No |
| **Full-text search** | BM25 with 27 stemmers | FTS5 (compile flag) | FTS5 (compile flag) | No |
| **Vector search (HNSW)** | Yes | No | sqlite-vec plugin | No |
| **Columnar typed arrays** | Yes (Float64Array, etc.) | No | No | No |
| **Streaming results** | Yes (chunk-by-chunk) | No | No | No |
| **Bulk insert (Appender)** | Yes | No | No | Batch insert |
| **Query progress callbacks** | Yes | No | No | No |
| **Reactive queries** | No | No | Yes | Yes |
| **ORM / Model layer** | No (raw SQL) | TypeORM compatible | TypeORM compatible | Built-in |
| **Sync protocol** | No | No | No | Built-in |
| **Encryption** | No | No | SQLCipher | No |
| **Expo plugin** | Yes | No | No | No |

## Documentation

| Guide | Description |
|-------|-------------|
| [API Reference](docs/API.md) | Complete API surface — every method, property, and type |
| [Extensions](docs/extensions.md) | Configuration, available extensions, per-extension usage |
| [Streaming & Appender](docs/streaming.md) | Chunk-by-chunk processing, bulk insert, ETL patterns |
| [Type System](docs/types.md) | DuckDB → JavaScript type mapping for all 30+ types |
| [Transactions](docs/transactions.md) | ACID transactions, batch execution, multi-database |
| [Database Location](docs/database-location.md) | Storage paths, iCloud/Auto Backup, platform defaults |
| [Full-Text Search](docs/fts.md) | BM25 indexing, stemmers, field search, limitations |
| [Vector Search](docs/vss.md) | HNSW indexes, distance metrics, RAG patterns |
| [Remote Data](docs/remote-data.md) | httpfs, Hugging Face datasets, S3, TLS config |
| [Expo Setup](docs/expo.md) | Config plugin, extension flow, migration guide |
| [Bare Workflow](docs/bare-workflow.md) | iOS/Android setup without Expo |

## Built with AI

I started working on this library in late 2023. The initial prototype took a full week and could barely run basic SQL statements — no extensions, no streaming, no type system. It proved the concept but was nowhere near production quality.

Fast forward to Feb 2026: with the help of LLMs, I rebuilt the entire library from scratch — production-grade, fully documented, with 11 statically-linked extensions, 30+ type mappings, streaming, vector search, full-text search, and an example app that doubles as a DuckDB dev studio. **The entire rebuild took under one week.**

The stack: [Claude Opus 4 (claude-4-6)](https://www.anthropic.com/) running through [opencode](https://opencode.ai/), orchestrated by the [Get Shit Done](https://github.com/nicekitchen/get-shit-done) framework for structured multi-phase execution. The total inference cost was roughly **~$1,500**.

But here's the thing — AI didn't make the decisions. I have extensive experience building React Native libraries, especially data libraries, and every architectural choice, every API design trade-off, every verification pass, every device test was done by a real human. The AI handled the volume; I handled the vision.

We're at the beginning of something massive. A single developer with the right tools can now ship what used to require a dedicated team and months of runway. The barrier to building ambitious software is collapsing. This library is proof.

## License

MIT

---

<sub>Inspired by [react-native-nitro-sqlite](https://github.com/margelo/react-native-nitro-sqlite) and [op-sqlite](https://github.com/OP-Engineering/op-sqlite). Built with [DuckDB](https://duckdb.org) and [Nitro Modules](https://nitro.margelo.com). See [RELEASE.md](RELEASE.md) for release security details.</sub>
