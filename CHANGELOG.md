# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0] - 2026-11-01

### Added
- Menu bar app that plays a click as scrolling crosses each notch, for trackpads and wheel mice.
- Ten bundled click sounds (CC0 recordings from Freesound) with subtle pitch variation.
- Edge awareness: silent at the top or bottom of a page, while rubber-banding, and over the empty desktop. Direction and position are learned per app.
- Support for apps with dummy scroll bars (Microsoft Word) by tracking content position.
- Five-level trackpad haptics (Whisper to Heavy).
- Notch equalizer with three modes and optional sound-color tint.
- Settings for volume, click spacing (50 to 500 px), momentum, output device, launch at login, and clicking in apps that report no scroll position.
- Universal binary (Apple Silicon and Intel), macOS 14 or later.
- Developer diagnostics tool, docs renderer and packaging scripts.

### Notes
- Browsers and web-based apps do not report their scroll position, so Scrollo stays silent there by default.
- Releases are signed with a self-made certificate and are not notarized.

[Unreleased]: https://github.com/pushpam2404/scrollo/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/pushpam2404/scrollo/releases/tag/v1.0.0
