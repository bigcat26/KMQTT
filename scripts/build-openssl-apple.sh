#!/bin/bash
# Builds OpenSSL 1.1.1w for all Apple targets used by
# kmqtt-common/src/nativeInterop/openssl.def, into a repo-relative
# `openssl-apple/` directory (this repo's parent dir of kmqtt-common).
#
# This replaces the old workflow of manually building OpenSSL somewhere on
# your machine and hand-editing openssl.def to point at it. Run this script
# once, then run cinterop / the kmqtt-common Klibrary gradle tasks - they
# will pick up the output automatically via the relative paths already
# configured in openssl.def.
#
# Usage: ./scripts/build-openssl-apple.sh [openssl-version]
set -euo pipefail

OPENSSL_VERSION="${1:-1.1.1w}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${ROOT_DIR}/.build/openssl-apple-src"
OUT_DIR="${ROOT_DIR}/openssl-apple"

mkdir -p "${WORK_DIR}"

# --- iOS / tvOS / watchOS via OpenSSL-for-iPhone -----------------------------
if [ ! -d "${WORK_DIR}/OpenSSL-for-iPhone" ]; then
    git clone --depth 1 https://github.com/x2on/OpenSSL-for-iPhone.git "${WORK_DIR}/OpenSSL-for-iPhone"
fi

pushd "${WORK_DIR}/OpenSSL-for-iPhone" >/dev/null
./build-libssl.sh --version="${OPENSSL_VERSION}"
popd >/dev/null

mkdir -p "${OUT_DIR}/bin"
# The build script emits versioned SDK dir names, e.g.
# "iPhoneOS17.2-arm64.sdk". Strip the SDK version suffix so the resulting
# path is stable across Xcode versions and matches openssl.def.
for sdk_dir in "${WORK_DIR}/OpenSSL-for-iPhone/bin"/*.sdk; do
    [ -d "${sdk_dir}" ] || continue
    base="$(basename "${sdk_dir}")"
    # e.g. iPhoneOS17.2-arm64.sdk -> iPhoneOS-arm64.sdk
    normalized="$(echo "${base}" | sed -E 's/^([A-Za-z]+)[0-9.]*-(.*)$/\1-\2/')"
    rm -rf "${OUT_DIR}/bin/${normalized}"
    cp -R "${sdk_dir}" "${OUT_DIR}/bin/${normalized}"
done

# --- macOS x64/arm64 built directly from openssl source ---------------------
if [ ! -d "${WORK_DIR}/openssl-${OPENSSL_VERSION}" ]; then
    curl -fsSL "https://github.com/openssl/openssl/releases/download/OpenSSL_$(echo "${OPENSSL_VERSION}" | tr . _)/openssl-${OPENSSL_VERSION}.tar.gz" \
        -o "${WORK_DIR}/openssl-${OPENSSL_VERSION}.tar.gz"
    tar -xzf "${WORK_DIR}/openssl-${OPENSSL_VERSION}.tar.gz" -C "${WORK_DIR}"
fi

build_macos() {
    local arch_target="$1"  # darwin64-x86_64-cc | darwin64-arm64-cc
    local out_name="$2"     # mac-x64 | mac-arm64

    local build_dir="${WORK_DIR}/build-${out_name}"
    rm -rf "${build_dir}"
    cp -R "${WORK_DIR}/openssl-${OPENSSL_VERSION}" "${build_dir}"

    pushd "${build_dir}" >/dev/null
    ./Configure "${arch_target}" no-shared no-tests --prefix="${OUT_DIR}/${out_name}"
    make -j"$(sysctl -n hw.ncpu)"
    make install_sw
    popd >/dev/null
}

build_macos darwin64-x86_64-cc mac-x64
build_macos darwin64-arm64-cc mac-arm64

echo "OpenSSL for Apple targets built at ${OUT_DIR}"
