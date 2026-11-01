#!/bin/zsh
# Renders the README banner images from docs/assets/*.html with a headless Chromium browser.
set -e
cd "$(dirname "$0")/.."
BROWSER=""
for b in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" "/Applications/Chromium.app/Contents/MacOS/Chromium" "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"; do
  [ -x "$b" ] && BROWSER="$b" && break
done
[ -z "$BROWSER" ] && { echo "Need a Chromium-based browser (Chrome, Brave, Chromium or Edge) to render banners."; exit 1; }
render() { # name width height
  "$BROWSER" --headless=new --disable-gpu --hide-scrollbars --no-first-run --user-data-dir="$(mktemp -d)" \
    --force-device-scale-factor=2 --window-size=$2,$3 --virtual-time-budget=3000 \
    --screenshot="docs/images/$1.png" "file://$PWD/docs/assets/$1.html" >/dev/null 2>&1
  echo "wrote docs/images/$1.png"
}
render hero 1600 800
render social 1280 640
render visualizer 1200 360
