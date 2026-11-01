# Development

## Requirements

- macOS 14 or later
- Xcode Command Line Tools: `xcode-select --install` (full Xcode is **not** required)

There are no third-party dependencies and no Xcode project; the app is built with `swiftc` by `build.sh`.

## Build and run

```sh
./build.sh                 # build + install to ~/Applications
./build.sh --no-install    # build/Scrollo.app only
open ~/Applications/Scrollo.app
```

The Swift language mode is pinned to 5 (`-swift-version 5`) because the event-tap callback and the global audio state would otherwise need extensive `Sendable` annotations.

## Keeping the Accessibility grant across rebuilds

macOS ties the Accessibility grant to the app's **code signature**. An ad-hoc signature changes on every build, so the grant is lost each time. A stable self-signed certificate fixes that. Create one once (Keychain Access → Certificate Assistant → *Create a Certificate…*, name **Scrollo Local Signing**, type *Code Signing*), or from the terminal:

```sh
cat > /tmp/cs.cnf <<'CNF'
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=Scrollo Local Signing
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -keyout /tmp/key.pem -out /tmp/cert.pem -days 3650 -config /tmp/cs.cnf
openssl pkcs12 -export -inkey /tmp/key.pem -in /tmp/cert.pem -out /tmp/id.p12 -name "Scrollo Local Signing" -passout pass:temp
security import /tmp/id.p12 -k ~/Library/Keychains/login.keychain-db -P temp -T /usr/bin/codesign
rm /tmp/key.pem /tmp/cert.pem /tmp/id.p12 /tmp/cs.cnf
```

`build.sh` uses an identity named `Scrollo Local Signing` when it exists and falls back to ad-hoc otherwise. Grant Accessibility once after the first build with it and it will survive rebuilds.

## Project layout

| Path | Purpose |
|---|---|
| `Sources/ScrollMonitor.swift` | Event tap, click timing, the entry point of every decision |
| `Sources/ScrollProbe.swift` | Scroll position reading and the click/silence verdict ([how it works](HOW_IT_WORKS.md)) |
| `Sources/AudioPlayer.swift`, `SoundBank.swift` | Audio engine and the bundled sounds |
| `Sources/Haptics.swift` | Trackpad haptics |
| `Sources/Visualizer.swift` | Notch equalizer |
| `Sources/Settings.swift`, `Views.swift`, `main.swift` | Preferences, UI, app lifecycle |
| `Sources/Diagnostics.swift` | Developer test tool (below) |
| `Tools/render_docs.swift` | Renders the real UI for the docs |
| `icon/` | Icon generator (`make_icon.swift`) and outputs |
| `scripts/` | Build, packaging and rendering scripts |

## Diagnostics tool

A hidden tool drives another app with synthetic scrolls and reports how Scrollo behaves, which is how the edge logic was developed and verified. It is off by default:

```sh
defaults write com.pushpam.scrollo debugProbe -bool true      # then relaunch Scrollo
echo "app=com.apple.Preview" > ~/Library/Logs/Scrollo.probe    # bundle id of the app to test
tail -f ~/Library/Logs/Scrollo.log | grep PROBE
```

It activates the app, dumps what its scroll area reports, drives the content to each end, and counts the clicks that **would** have played while pushing into an edge (should be about 0), flicking at an edge (about 0) and scrolling away (above 0). It moves your pointer and scrolls the app's front window, so use a throwaway document.

Turn it off again with `defaults delete com.pushpam.scrollo debugProbe`.

## Regenerating images

```sh
./scripts/render-docs.sh      # screenshots from the real SwiftUI views (needs a GUI session)
./scripts/render-banners.sh   # hero, social card, visualizer (needs Chrome, Brave, Chromium or Edge)
```

The icon is drawn in code:

```sh
swiftc -O icon/make_icon.swift -o /tmp/make_icon && /tmp/make_icon icon/icon1024.png
```

then convert to `.icns` with `iconutil` (see `scripts/make-icns.sh`).

## Conventions

- Match the surrounding style; comments explain *why*, not *what*.
- No third-party dependencies.
- Anything that touches Accessibility must have a timeout and must fail quietly.
