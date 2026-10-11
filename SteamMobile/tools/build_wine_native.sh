#!/bin/bash
# Real iOS Wine archives, from the exact Madeira source graph.
set -euo pipefail
R="$(cd "$1" && pwd)"
export PATH="$(brew --prefix bison)/bin:$(brew --prefix llvm)/bin:$PATH"
JOBS=$(sysctl -n hw.ncpu)

# Generate config.h and Wine's IDL headers with native host tools. No macOS
# object from this tree is linked into the iOS application.
mkdir -p "$R/wine/build-macos"
(
  cd "$R/wine/build-macos"
  ../configure --enable-archs=none --without-mingw --without-x --disable-tests
  make -j"$JOBS" include/all
)
test -s "$R/wine/build-macos/include/config.h"
test -s "$R/wine/build-macos/include/dwrite.h"
test -s "$R/wine/build-macos/include/mfobjects.h"

# The tracked crypto binaries lack their build headers. Build and stage the
# matching libraries and headers together, verifying upstream source tarballs.
(cd "$R/build/gnutls-ios/src" && shasum -a 256 -c SHA256SUMS)
bash "$R/build/gnutls-ios/build.sh"
for lib in gmp nettle hogweed gnutls; do
  cp "$R/toolchains/gnutls-ios/lib/lib${lib}.a" "$R/app/Madeira/"
done
bash "$R/build/freetype-ios/build.sh"
bash "$R/build/ntdll-unix/build.sh"
bash "$R/build/wineserver/build.sh"
bash "$R/build/win32u-unix/build.sh"
for lib in ntdll_unix wineserver win32u_unix; do
  test -s "$R/app/Madeira/lib${lib}.a"
  xcrun lipo -verify_arch arm64 "$R/app/Madeira/lib${lib}.a"
  xcrun ar -t "$R/app/Madeira/lib${lib}.a"
done
