#!/bin/zsh
# Renders the README banner images from docs/assets/*.html using WebKit (no browser needed).
set -e
cd "$(dirname "$0")/.."
mkdir -p build/tools
cp Tools/render_html.swift build/tools/render_html_main.swift
mv build/tools/render_html_main.swift build/tools/main.swift
swiftc -O build/tools/main.swift -o build/tools/render_html
render() { # name width height
  build/tools/render_html "$PWD/docs/assets/$1.html" $2 $3 "$PWD/docs/images/$1.png"
}
render hero 1600 800
render social 1280 640
