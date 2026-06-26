#!/usr/bin/env bash
#
# Clone the DuckDB sources at the pinned tag into <target-dir>.
#
# Used by the Android source-build fallback (package/android/build.gradle) when the
# DuckDB submodule is not present — e.g. when a consumer requests a custom DUCKDB_FEATURES
# set, or a prebuilt release download failed. No-op if the target already has CMakeLists.txt.
#
# Usage: clone-duckdb.sh <target-dir> [version]
#   version defaults to the contents of <package>/vendor/duckdb/DUCKDB_VERSION (e.g. v1.4.4).
set -euo pipefail

TARGET_DIR="${1:?usage: clone-duckdb.sh <target-dir> [version]}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Scripts live in <package>/scripts, so the package root is one level up.
PACKAGE_DIR="$(dirname "$SCRIPT_DIR")"

VERSION="${2:-}"
if [ -z "$VERSION" ]; then
  VERSION_FILE="$PACKAGE_DIR/vendor/duckdb/DUCKDB_VERSION"
  if [ -f "$VERSION_FILE" ]; then
    VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
  else
    VERSION="v1.4.4"
  fi
fi

DUCKDB_URL="https://github.com/duckdb/duckdb.git"

if [ -f "$TARGET_DIR/CMakeLists.txt" ]; then
  echo "DuckDB sources already present at $TARGET_DIR; skipping clone."
  exit 0
fi

echo "Cloning DuckDB $VERSION into $TARGET_DIR ..."
mkdir -p "$(dirname "$TARGET_DIR")"
rm -rf "$TARGET_DIR"
git clone --depth 1 --branch "$VERSION" "$DUCKDB_URL" "$TARGET_DIR"

if [ ! -f "$TARGET_DIR/CMakeLists.txt" ]; then
  echo "error: DuckDB clone did not produce a CMakeLists.txt at $TARGET_DIR" >&2
  exit 1
fi

echo "DuckDB $VERSION ready at $TARGET_DIR"
