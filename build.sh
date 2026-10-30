#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"

build_variant() {
  local folder="$1" name="$2" load_only="$3"
  mkdir -p "$folder"
  xcrun --sdk iphoneos clang \
    -target arm64-apple-ios15.0 -isysroot "$sdk" \
    -fno-objc-arc -fmodules -fblocks -dynamiclib \
    -Wall -Wextra -Werror -Wno-unused-parameter \
    -DNFB_LOAD_ONLY="$load_only" \
    -framework Foundation -framework UIKit -lobjc \
    -Wl,-install_name,@rpath/"$name" \
    NFBActionBarDownload.m -o "$folder/$name"
  # The injector/signer must sign the library for the actual installation.
  codesign --force --sign - "$folder/$name"
  codesign --verify --strict "$folder/$name"
  local architectures
  architectures="$(lipo -archs "$folder/$name")"
  printf '%s architectures: %s\n' "$name" "$architectures"
  test "$architectures" = arm64
  xcrun vtool -show-build "$folder/$name" | tee "$folder/platform.txt"
  otool -L "$folder/$name" | tee "$folder/dependencies.txt"
  # Exclude the binary label and its own LC_ID_DYLIB line before comparison.
  sed '1,2d' "$folder/dependencies.txt" > "$folder/linked-libraries.txt"
  printf 'NFB_LOAD_ONLY=%s\n' "$load_only" > "$folder/variant.txt"
  (
    cd "$folder"
    shasum -a 256 "$name" > SHA256SUMS.sha256
    shasum -a 256 -c SHA256SUMS.sha256
  )
}

build_variant build/load-test NFBActionBarLoadProbe.dylib 1
build_variant build/shortcut NFBActionBarDownload.dylib 0
cmp build/load-test/linked-libraries.txt build/shortcut/linked-libraries.txt
printf 'Both variants link the same system libraries.\n'
