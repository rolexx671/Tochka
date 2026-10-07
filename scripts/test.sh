#!/bin/bash
# Compiles and runs every test in Tests/. Each test is a small executable that exits non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="build/tests"
mkdir -p "$OUT" build/verification
swiftc Sources/Remapping.swift Tests/RemappingTests.swift -o "$OUT/remapping" -framework Carbon -framework CoreGraphics
swiftc Sources/LaunchBehavior.swift Sources/Startup.swift Tests/LaunchBehaviorTests.swift -o "$OUT/launch" \
    -framework AppKit -framework Carbon -framework ServiceManagement
swiftc Sources/StatusBar.swift Tests/StatusBarTests.swift -o "$OUT/statusbar" -framework AppKit -framework CoreImage
"$OUT/remapping"
"$OUT/launch"
"$OUT/statusbar"
echo "Все тесты пройдены."
