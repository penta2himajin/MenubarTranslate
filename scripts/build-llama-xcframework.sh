#!/usr/bin/env bash
# Build llama.xcframework (macOS arm64 + Metal, static libllama) and install it
# at vendor/llama.xcframework.  Idempotent — skips the cmake build if the
# xcframework already exists and the pin matches.
#
# Usage:
#   ./scripts/build-llama-xcframework.sh
#
# After this runs once, `swift build` picks up the xcframework automatically
# (see the conditional binaryTarget in Package.swift).
# The xcframework is large; vendor/ is .gitignored — each developer runs this
# script once on a clean checkout.

set -euo pipefail

LLAMA_TAG="b9878"   # <-- single pin; bump here to upgrade
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$REPO_ROOT/vendor"
XCFW="$VENDOR/llama.xcframework"
WORK="$VENDOR/.llama-build"

echo "llama.cpp pin: $LLAMA_TAG"

# Idempotent: skip if already built at the same pin.
if [ -d "$XCFW" ] && [ -f "$XCFW/.pin" ] && [ "$(cat "$XCFW/.pin")" = "$LLAMA_TAG" ]; then
    echo "vendor/llama.xcframework already at $LLAMA_TAG — nothing to do."
    exit 0
fi

mkdir -p "$WORK"
cd "$WORK"

# Clone / update the source tree.
if [ ! -d "llama.cpp" ]; then
    git clone --depth 1 --branch "$LLAMA_TAG" https://github.com/ggml-org/llama.cpp.git
else
    git -C llama.cpp fetch --depth 1 origin "refs/tags/$LLAMA_TAG:refs/tags/$LLAMA_TAG" 2>/dev/null || true
    git -C llama.cpp checkout "$LLAMA_TAG" --quiet
fi

# Build macOS arm64 — Metal ON, static lib, no tests/examples (fast).
cmake -S llama.cpp -B build-macos-arm64 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DGGML_METAL=ON \
    -DLLAMA_STATIC=ON \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_EXAMPLES=OFF \
    -DLLAMA_BUILD_SERVER=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -GNinja 2>/dev/null || \
cmake -S llama.cpp -B build-macos-arm64 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DGGML_METAL=ON \
    -DLLAMA_STATIC=ON \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_EXAMPLES=OFF \
    -DLLAMA_BUILD_SERVER=OFF \
    -DBUILD_SHARED_LIBS=OFF

cmake --build build-macos-arm64 --target llama --parallel

# Locate the built static library and headers.
LIB="$(find build-macos-arm64 -name 'libllama.a' | head -1)"
GGML_LIB="$(find build-macos-arm64 -name 'libggml.a' | head -1)"
GGML_BLAS="$(find build-macos-arm64 -name 'libggml-blas.a' 2>/dev/null | head -1)"
GGML_METAL="$(find build-macos-arm64 -name 'libggml-metal.a' 2>/dev/null | head -1)"
GGML_BASE="$(find build-macos-arm64 -name 'libggml-base.a' 2>/dev/null | head -1)"
GGML_CPU="$(find build-macos-arm64 -name 'libggml-cpu.a' 2>/dev/null | head -1)"

HEADER_SRC="llama.cpp/include"
MODULE_DIR="$WORK/module-macos-arm64"
LIB_DIR="$WORK/fat-macos-arm64"
mkdir -p "$MODULE_DIR" "$LIB_DIR"

# Merge all static libs into one so SwiftPM sees a single binary.
EXTRA_LIBS=""
for L in "$GGML_LIB" "$GGML_BASE" "$GGML_CPU" "$GGML_METAL" "$GGML_BLAS"; do
    [ -n "$L" ] && [ -f "$L" ] && EXTRA_LIBS="$EXTRA_LIBS $L"
done
libtool -static -o "$LIB_DIR/libllama_merged.a" "$LIB" $EXTRA_LIBS 2>/dev/null || \
    cp "$LIB" "$LIB_DIR/libllama_merged.a"

# Build a minimal module.modulemap so Swift can import the C API as `llama`.
cp -R "$HEADER_SRC" "$MODULE_DIR/Headers"
# llama.h includes ggml.h / ggml-cpu.h / ggml-backend.h / ggml-opt.h / gguf.h,
# which live under ggml/include — copy them into the same Headers dir so the
# umbrella header can resolve them when Swift builds the clang module.
cp "$WORK/llama.cpp/ggml/include/"*.h "$MODULE_DIR/Headers/"
cat > "$MODULE_DIR/Headers/module.modulemap" <<'MODULEMAP'
module llama {
    umbrella header "llama.h"
    export *
}
MODULEMAP

# Assemble the xcframework (macOS slice only — sufficient for local dev).
rm -rf "$XCFW"
xcodebuild -create-xcframework \
    -library "$LIB_DIR/libllama_merged.a" \
    -headers "$MODULE_DIR/Headers" \
    -output "$XCFW"

# Stamp the pin so future runs are idempotent.
echo "$LLAMA_TAG" > "$XCFW/.pin"

echo "Built vendor/llama.xcframework at $LLAMA_TAG"
