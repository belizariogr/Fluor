#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d "${TMPDIR:-/tmp}/Fluor-function-key-tests.XXXXXX")"
trap 'rm -rf "$TEMP"' EXIT
TEST_FRAMEWORKS="$(xcrun --show-sdk-platform-path)/Developer/Library/Frameworks"
TEST_LIBRARIES="$(xcrun --show-sdk-platform-path)/Developer/usr/lib"

xcrun swiftc -swift-version 5 -F "$TEST_FRAMEWORKS" -I "$TEST_LIBRARIES" -L "$TEST_LIBRARIES" \
  -Xlinker -rpath -Xlinker "$TEST_FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$TEST_LIBRARIES" \
  "$ROOT/Fluor/Models/FunctionKeyOverrides.swift" \
  "$ROOT/Fluor/Models/FunctionKeyMappingEngine.swift" \
  "$ROOT/Tests/FunctionKeyMappingTests.swift" \
  -o "$TEMP/function-key-tests"
"$TEMP/function-key-tests"

if [[ "${1:-}" == "--native" ]]; then
  xcrun swiftc -swift-version 5 \
    "$ROOT/Fluor/Models/FunctionKeyOverrides.swift" \
    "$ROOT/Fluor/Models/FunctionKeyMappingEngine.swift" \
    "$ROOT/Fluor/Misc/SystemFunctionKeyMappingBackend.swift" \
    "$ROOT/Tests/NativeFunctionKeyMappingCheck.swift" \
    -o "$TEMP/native-mapping-check"
  "$TEMP/native-mapping-check"
fi
