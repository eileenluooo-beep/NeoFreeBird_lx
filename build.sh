#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun --sdk iphoneos clang \
  -target arm64-apple-ios15.0 -isysroot "$sdk" \
  -fno-objc-arc -fmodules -dynamiclib \
  -Wall -Wextra -Werror -Wno-unused-parameter \
  -framework Foundation -framework UIKit \
  -Wl,-install_name,@rpath/NFBActionBarDownload.dylib \
  NFBActionBarDownload.m -o build/NFBActionBarDownload.dylib
# Ad-hoc signing seals the output. The injector/signer must sign it appropriately
# for the user's installation; this is not a provisioning profile or Apple cert.
codesign --force --sign - build/NFBActionBarDownload.dylib
codesign --verify --strict build/NFBActionBarDownload.dylib
architectures="$(lipo -archs build/NFBActionBarDownload.dylib)"
printf 'Architectures: %s\n' "$architectures"
test "$architectures" = arm64
xcrun vtool -show-build build/NFBActionBarDownload.dylib
otool -L build/NFBActionBarDownload.dylib
(
  cd build
  shasum -a 256 NFBActionBarDownload.dylib > SHA256SUMS.sha256
  shasum -a 256 -c SHA256SUMS.sha256
)
