#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SOURCE_DIR="${ROOT_DIR}/boringssl"
BUILD_DIR="${ROOT_DIR}/build"
OUTPUT_DIR="${ROOT_DIR}/dist"

RID="${1:?Usage: build.sh <rid> [upstream-sha]}"
UPSTREAM_SHA="${2:-HEAD}"

case "${RID}" in
  linux-x64|linux-arm64|osx-x64|osx-arm64)
    ;;
  *)
    echo "Unsupported RID for build.sh: ${RID}" >&2
    exit 2
    ;;
esac

REQUIRED_TOOLS=(git cmake ninja python3 go perl)
if [[ "${RID}" == "linux-x64" || "${RID}" == "osx-x64" ]]; then
  REQUIRED_TOOLS+=(nasm)
fi

for tool in "${REQUIRED_TOOLS[@]}"; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "Required tool not found: ${tool}" >&2
    exit 1
  fi
done

echo "========================================"
echo " BoringSSL shared-library build"
echo " RID: ${RID}"
echo " Upstream revision: ${UPSTREAM_SHA}"
echo "========================================"

if [[ ! -d "${SOURCE_DIR}/.git" ]]; then
  rm -rf "${SOURCE_DIR}"
  git clone --filter=blob:none https://github.com/google/boringssl.git "${SOURCE_DIR}"
fi

git -C "${SOURCE_DIR}" fetch origin --prune
if [[ "${UPSTREAM_SHA}" != "HEAD" ]]; then
  git -C "${SOURCE_DIR}" fetch origin "${UPSTREAM_SHA}"
fi
git -C "${SOURCE_DIR}" checkout --detach "${UPSTREAM_SHA}"

rm -rf "${BUILD_DIR}"

cmake \
  -S "${SOURCE_DIR}" \
  -B "${BUILD_DIR}" \
  -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=ON

cmake --build "${BUILD_DIR}" --parallel

python3 "${ROOT_DIR}/scripts/package.py" \
  --source "${SOURCE_DIR}" \
  --build "${BUILD_DIR}" \
  --rid "${RID}" \
  --output "${OUTPUT_DIR}" \
  --upstream-sha "${UPSTREAM_SHA}"

ZIP_PATH="${OUTPUT_DIR}/boringssl-${RID}.zip"
if [[ ! -f "${ZIP_PATH}" ]]; then
  echo "Expected output package was not created: ${ZIP_PATH}" >&2
  exit 1
fi

echo "Build and packaging completed: ${ZIP_PATH}"