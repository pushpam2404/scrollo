#!/bin/zsh
# Renders the real UI to docs/images/ using the app's own SwiftUI sources.
set -e
cd "$(dirname "$0")/.."
mkdir -p build/tools docs/images
cp Tools/render_docs.swift build/tools/main.swift          # top-level code must live in a file named main.swift
SRC=(Sources/*.swift)
SRC=(${SRC:#Sources/main.swift})                            # everything except the app's own entry point
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos14.0" $SRC build/tools/main.swift -o build/tools/render_docs
build/tools/render_docs docs/images
