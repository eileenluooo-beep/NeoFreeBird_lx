#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .test-build
sdk="$(xcrun --sdk macosx --show-sdk-path)"
xcrun --sdk macosx clang \
  -isysroot "$sdk" -fno-objc-arc \
  -Wall -Wextra -Werror -Wno-unused-parameter \
  -framework Foundation tests/runtime-smoke.m -o .test-build/runtime-smoke
.test-build/runtime-smoke | tee .test-build/runtime-smoke.txt
