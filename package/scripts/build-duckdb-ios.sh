#!/bin/bash
set -euo pipefail

# Build DuckDB static libraries for iOS (device + simulator)
# and create a combined xcframework.
# Called from RNDuckDB.podspec prepare_command.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Scripts live in <package>/scripts; the package root is one level up.
PACKAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Resolve the DuckDB sources: prefer the repo-root submodule (dev checkout), else a
# package-local checkout, cloning the pinned tag on demand (published npm consumers).
if [ -f "${PACKAGE_DIR}/../duckdb/CMakeLists.txt" ]; then
  DUCKDB_DIR="$(cd "${PACKAGE_DIR}/.." && pwd)/duckdb"
else
  DUCKDB_DIR="${PACKAGE_DIR}/duckdb"
  if [ ! -f "${DUCKDB_DIR}/CMakeLists.txt" ]; then
    echo "--- DuckDB sources not found; cloning into ${DUCKDB_DIR} ---"
    bash "${SCRIPT_DIR}/clone-duckdb.sh" "${DUCKDB_DIR}"
  fi
fi
BUILD_DIR="${DUCKDB_DIR}/build-ios"
JOBS="$(sysctl -n hw.ncpu)"
MIN_IOS="${1:-15.1}"

echo "=== react-native-duckdb: Building DuckDB for iOS (min=${MIN_IOS}, jobs=${JOBS}) ==="
echo "--- DuckDB source dir: ${DUCKDB_DIR} ---"

# Step 1: Configure extensions
echo "--- Configuring extensions ---"

# Feature-set selection mirrors the Android build (DUCKDB_FEATURES env var).
# core/all expand to fixed lists; any other value is a custom comma list; empty falls
# back to Podfile.properties.json / package.json discovery.
CORE_FEATURE_SET="core_functions,parquet,json"
# "all" excludes delta (needs Rust+vcpkg) and the unvalidated autocomplete/tpch/tpcds.
ALL_FEATURE_SET="core_functions,parquet,json,icu,sqlite_scanner,httpfs,fts,vss"
EXTENSIONS=""
case "$(printf '%s' "${DUCKDB_FEATURES:-}" | tr '[:upper:]' '[:lower:]')" in
  core) EXTENSIONS="$CORE_FEATURE_SET" ;;
  all)  EXTENSIONS="$ALL_FEATURE_SET" ;;
  "")   EXTENSIONS="" ;;
  *)    EXTENSIONS="${DUCKDB_FEATURES}" ;;
esac

# When DUCKDB_FEATURES is unset, try Podfile.properties.json (Expo managed workflow).
if [ -z "$EXTENSIONS" ]; then
  for CANDIDATE in \
    "${PACKAGE_DIR}/../ios/Podfile.properties.json" \
    "${PACKAGE_DIR}/../../ios/Podfile.properties.json" \
    "${PACKAGE_DIR}/../../../ios/Podfile.properties.json"; do
    if [ -f "$CANDIDATE" ]; then
      EXTENSIONS=$(node -e "
        const p = JSON.parse(require('fs').readFileSync('$CANDIDATE', 'utf8'));
        if (p['react-native-duckdb.extensions']) process.stdout.write(p['react-native-duckdb.extensions']);
      " 2>/dev/null || true)
      break
    fi
  done
fi

if [ -n "$EXTENSIONS" ]; then
  node "${SCRIPT_DIR}/configure-extensions.js" --duckdb-path "${DUCKDB_DIR}" --extensions "${EXTENSIONS}"
else
  node "${SCRIPT_DIR}/configure-extensions.js" --duckdb-path "${DUCKDB_DIR}"
fi

# Check if httpfs is in the generated extension config (needs OpenSSL + libcurl)
NEEDS_HTTPFS=false
EXT_CONFIG="${DUCKDB_DIR}/extension/extension_config_local.cmake"
if [ -f "$EXT_CONFIG" ] && grep -q "httpfs" "$EXT_CONFIG"; then
  NEEDS_HTTPFS=true
  echo "--- httpfs detected: will build OpenSSL + libcurl for each target ---"
fi

# Invalidate cached builds if extension config changed
EXT_CONFIG_HASH=$(md5 -q "${EXT_CONFIG}" 2>/dev/null || md5sum "${EXT_CONFIG}" 2>/dev/null | cut -d' ' -f1 || echo "none")
for BUILD_SUBDIR in "build-ios-iphoneos-arm64" "build-ios-iphonesimulator-arm64"; do
  CACHED_HASH_FILE="${DUCKDB_DIR}/${BUILD_SUBDIR}/.extension_config_hash"
  if [ -d "${DUCKDB_DIR}/${BUILD_SUBDIR}" ]; then
    if [ ! -f "$CACHED_HASH_FILE" ] || [ "$(cat "$CACHED_HASH_FILE")" != "$EXT_CONFIG_HASH" ]; then
      echo "--- Extension config changed, cleaning ${BUILD_SUBDIR} ---"
      rm -rf "${DUCKDB_DIR}/${BUILD_SUBDIR}"
    fi
  fi
done

# Shared cmake flags
CMAKE_COMMON=(
  -DBUILD_SHELL=OFF
  -DBUILD_UNITTESTS=OFF
  -DBUILD_BENCHMARKS=OFF
  -DENABLE_SANITIZER=OFF
  -DENABLE_UBSAN=OFF
  -DEXTENSION_STATIC_BUILD=OFF
  -DBUILD_EXTENSIONS_ONLY=OFF
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_CXX_STANDARD=20
  -DBUILD_SHARED_LIBS=OFF
)

build_arch() {
  local PLATFORM="$1"   # iphoneos | iphonesimulator
  local ARCH="$2"       # arm64 | x86_64
  local BUILD_SUBDIR="build-ios-${PLATFORM}-${ARCH}"
  local FULL_BUILD_DIR="${DUCKDB_DIR}/${BUILD_SUBDIR}"

  echo "--- Building DuckDB for ${PLATFORM} (${ARCH}) ---"

  # Map platform+arch to vendor directory name for OpenSSL/curl
  local MAPPED_ARCH=""
  if [ "$PLATFORM" = "iphoneos" ]; then
    MAPPED_ARCH="${ARCH}"
  elif [ "$PLATFORM" = "iphonesimulator" ]; then
    MAPPED_ARCH="simulator-${ARCH}"
  fi

  # Build OpenSSL + libcurl if httpfs is enabled
  local HTTPFS_CMAKE_FLAGS=()
  if [ "$NEEDS_HTTPFS" = true ]; then
    echo "   Building OpenSSL + libcurl for ios-${MAPPED_ARCH}..."
    "${SCRIPT_DIR}/build-openssl-curl.sh" ios "${MAPPED_ARCH}"
    HTTPFS_CMAKE_FLAGS=(
      -DOPENSSL_ROOT_DIR="${PACKAGE_DIR}/vendor/openssl/ios-${MAPPED_ARCH}"
      -DOPENSSL_INCLUDE_DIR="${PACKAGE_DIR}/vendor/openssl/ios-${MAPPED_ARCH}/include"
      -DOPENSSL_SSL_LIBRARY="${PACKAGE_DIR}/vendor/openssl/ios-${MAPPED_ARCH}/lib/libssl.a"
      -DOPENSSL_CRYPTO_LIBRARY="${PACKAGE_DIR}/vendor/openssl/ios-${MAPPED_ARCH}/lib/libcrypto.a"
      -DOPENSSL_USE_STATIC_LIBS=TRUE
      -DCURL_ROOT="${PACKAGE_DIR}/vendor/curl/ios-${MAPPED_ARCH}"
      -DCURL_INCLUDE_DIR="${PACKAGE_DIR}/vendor/curl/ios-${MAPPED_ARCH}/include"
      -DCURL_LIBRARY="${PACKAGE_DIR}/vendor/curl/ios-${MAPPED_ARCH}/lib/libcurl.a"
    )
  fi

  local SDK_PATH
  SDK_PATH="$(xcrun --sdk "${PLATFORM}" --show-sdk-path)"

  cmake -S "${DUCKDB_DIR}" -B "${FULL_BUILD_DIR}" -G "Unix Makefiles" \
    "${CMAKE_COMMON[@]}" \
    ${HTTPFS_CMAKE_FLAGS[@]+"${HTTPFS_CMAKE_FLAGS[@]}"} \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="${SDK_PATH}" \
    -DCMAKE_OSX_ARCHITECTURES="${ARCH}" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="${MIN_IOS}" \
    -DDUCKDB_EXPLICIT_PLATFORM="ios_${ARCH}" \
    2>&1 | tail -5

  cmake --build "${FULL_BUILD_DIR}" --config Release --target duckdb_static -j"${JOBS}" 2>&1 | tail -3

  # Combine all .a files into one per architecture
  local COMBINED="${FULL_BUILD_DIR}/libduckdb_combined.a"
  local ALL_LIBS=()

  # Find all .a files produced by the build
  while IFS= read -r -d '' lib; do
    ALL_LIBS+=("${lib}")
  done < <(find "${FULL_BUILD_DIR}" -name "*.a" -print0)

  # Include vendor OpenSSL + libcurl static libs when httpfs is enabled
  if [ "$NEEDS_HTTPFS" = true ]; then
    local VENDOR_SSL="${PACKAGE_DIR}/vendor/openssl/ios-${MAPPED_ARCH}/lib"
    local VENDOR_CURL="${PACKAGE_DIR}/vendor/curl/ios-${MAPPED_ARCH}/lib"
    for vendor_lib in "${VENDOR_SSL}/libssl.a" "${VENDOR_SSL}/libcrypto.a" "${VENDOR_CURL}/libcurl.a"; do
      if [ -f "$vendor_lib" ]; then
        ALL_LIBS+=("${vendor_lib}")
      else
        echo "WARNING: Expected vendor lib not found: ${vendor_lib}"
      fi
    done
  fi

  if [ ${#ALL_LIBS[@]} -eq 0 ]; then
    echo "ERROR: No .a files found in ${FULL_BUILD_DIR}"
    exit 1
  fi

  echo "   Combining ${#ALL_LIBS[@]} static libraries..."
  libtool -static -o "${COMBINED}" "${ALL_LIBS[@]}" 2>/dev/null
  echo "   Combined: ${COMBINED} ($(du -h "${COMBINED}" | cut -f1))"

  # Save extension config hash for cache invalidation
  echo "$EXT_CONFIG_HASH" > "${FULL_BUILD_DIR}/.extension_config_hash"
}

# Step 2: Build for device and simulator
build_arch "iphoneos" "arm64"
build_arch "iphonesimulator" "arm64"

# Step 3: Create xcframework
echo "--- Creating DuckDB.xcframework ---"
rm -rf "${BUILD_DIR}/DuckDB.xcframework"
mkdir -p "${BUILD_DIR}"

xcodebuild -create-xcframework \
  -library "${DUCKDB_DIR}/build-ios-iphoneos-arm64/libduckdb_combined.a" \
  -headers "${DUCKDB_DIR}/src/include" \
  -library "${DUCKDB_DIR}/build-ios-iphonesimulator-arm64/libduckdb_combined.a" \
  -headers "${DUCKDB_DIR}/src/include" \
  -output "${BUILD_DIR}/DuckDB.xcframework" \
  2>&1 | tail -3

# Step 4: Copy xcframework into the package root so CocoaPods can find it
# (vendored_frameworks paths must be within the pod source tree). PACKAGE_DIR is
# already the package root (defined at the top of this script).
rm -rf "${PACKAGE_DIR}/DuckDB.xcframework"
cp -R "${BUILD_DIR}/DuckDB.xcframework" "${PACKAGE_DIR}/DuckDB.xcframework"

# Step 5: Write extension metadata for podspec to read
EXT_META="${PACKAGE_DIR}/.duckdb-extensions.json"
if [ "$NEEDS_HTTPFS" = true ]; then
  echo '{"httpfs":true}' > "$EXT_META"
else
  echo '{}' > "$EXT_META"
fi

echo "=== DuckDB.xcframework created at ${PACKAGE_DIR}/DuckDB.xcframework ==="
