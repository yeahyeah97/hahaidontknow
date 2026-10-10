#!/bin/bash
set -euo pipefail
R="$(cd "$1" && pwd)"
JOBS=$(sysctl -n hw.ncpu)
LLVM="$R/toolchains/llvm-project/llvm"
HOST_BUILD="$R/toolchains/llvm-host-build"
IOS_BUILD="$R/toolchains/llvm-ios-build"
# Build llvm-tblgen on the runner; iOS executables cannot run on the host.
cmake -S "$LLVM" -B "$HOST_BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DLLVM_TARGETS_TO_BUILD= \
  -DLLVM_ENABLE_PROJECTS= -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF \
  -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF -DLLVM_ENABLE_TERMINFO=OFF
cmake --build "$HOST_BUILD" --target llvm-tblgen -j "$JOBS"
cmake -S "$LLVM" -B "$IOS_BUILD" -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_SYSTEM_PROCESSOR=arm64 \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=EXECUTABLE \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
  -DLLVM_HOST_TRIPLE=arm64-apple-ios17.0 -DLLVM_DEFAULT_TARGET_TRIPLE=arm64-apple-ios17.0 \
  -DLLVM_TARGET_ARCH=host -DLLVM_TARGETS_TO_BUILD= -DLLVM_ENABLE_PROJECTS= \
  -DLLVM_TABLEGEN="$HOST_BUILD/bin/llvm-tblgen" \
  -DLLVM_BUILD_TOOLS=OFF -DLLVM_INCLUDE_TOOLS=OFF \
  -DLLVM_BUILD_UTILS=OFF -DLLVM_INCLUDE_UTILS=OFF \
  -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF \
  -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF -DLLVM_ENABLE_TERMINFO=OFF \
  -DLLVM_ENABLE_LIBXML2=OFF -DLLVM_ENABLE_LIBEDIT=OFF
# Library/function probes must actually link. STATIC_LIBRARY made CMake
# falsely detect librt (and potentially unavailable functions) on iOS.
if grep -Eq '^HAVE_LIBRT:[^=]*=(1|ON|TRUE)$' "$IOS_BUILD/CMakeCache.txt"; then
  echo 'Invalid iOS configuration: librt was detected' >&2
  exit 1
fi
cmake --build "$IOS_BUILD" --target llvm-libraries -j "$JOBS"
bash "$R/build/dxmt-ios/build.sh"
test -s "$R/app/Madeira/libdxmt_combined.a"
xcrun lipo -verify_arch arm64 "$R/app/Madeira/libdxmt_combined.a"
