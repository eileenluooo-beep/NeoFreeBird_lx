#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"

build_variant() {
  local folder="$1" name="$2" load_only="$3"
  local objects=".build-objects/$(basename "$folder")"
  mkdir -p "$folder" "$objects"
  local compile_flags=(-target arm64-apple-ios15.0 -isysroot "$sdk"
    -fmodules -fblocks -Wall -Wextra -Werror -Wno-unused-parameter)
  # Runtime initializer IMPs keep their tested MRC ownership; asynchronous photo
  # jobs use ARC in separate translation units so both lifetimes remain correct.
  xcrun --sdk iphoneos clang "${compile_flags[@]}" -fno-objc-arc \
    -DNFB_LOAD_ONLY="$load_only" -c NFBActionBarDownload.m -o "$objects/actionbar.o"
  xcrun --sdk iphoneos clang "${compile_flags[@]}" -fobjc-arc \
    -c NFBPhotoSupport.m -o "$objects/photo-support.o"
  xcrun --sdk iphoneos clang "${compile_flags[@]}" -fobjc-arc \
    -c NFBPhotoDownloader.m -o "$objects/photo-downloader.o"
  xcrun --sdk iphoneos clang -target arm64-apple-ios15.0 -isysroot "$sdk" -dynamiclib \
    -framework Foundation -framework UIKit -framework CoreFoundation -framework CoreGraphics \
    -framework Photos -framework ImageIO -framework UniformTypeIdentifiers -framework QuartzCore -lobjc \
    -Wl,-install_name,@rpath/"$name" \
    "$objects/actionbar.o" "$objects/photo-support.o" "$objects/photo-downloader.o" -o "$folder/$name"
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
