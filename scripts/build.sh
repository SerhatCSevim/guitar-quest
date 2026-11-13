#!/bin/zsh
# Thin wrapper around `swift build` that works with the command line tools: the macOS 27 SDK's SwiftUI uses
# macros whose plugin only ships inside Xcode, so we point the compiler at it. Extra args are passed through.
# Usage: scripts/build.sh [swift build args…]    e.g. scripts/build.sh --product GuitarQuest -c release
set -euo pipefail
cd "$(dirname "$0")/.."
PLUG=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins
ARGS=()
if [[ -d "$PLUG" && "$(xcode-select -p)" != *Xcode.app* ]]; then ARGS+=(-Xswiftc -plugin-path -Xswiftc "$PLUG"); fi
exec swift build "${ARGS[@]}" "$@"
