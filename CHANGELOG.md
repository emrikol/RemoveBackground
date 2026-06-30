# Changelog

All notable changes to Remove Background are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project aims to follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.2.0] - 2026-06-30

### Security
- Downloaded models are now pinned to immutable sources and **verified against a SHA-256
  checksum** before use — a tampered or swapped model is rejected and discarded.
- Hardened model-output handling: a model that misreports its output shape can no longer
  trigger an out-of-bounds read or an oversized allocation.

## [0.1.2] - 2026-06-30

### Changed
- The app now **checks for updates automatically** in the background and prompts when a
  new version is available (previously manual-only). It sends only the app version, macOS
  version, and CPU architecture when checking — nothing else.

## [0.1.1] - 2026-06-30

### Fixed
- Release builds now ship the **modern Liquid Glass (macOS 26) app icon**. The CI
  runner uses an older `actool` that can't compile the Icon Composer `main.icon`, so the
  pre-compiled icon is committed and bundled directly.

## [0.1.0] - 2026-06-30

### Added
- **Auto-update via Sparkle 2** — a "Check for Updates…" menu item; the framework is
  embedded and Developer-ID signable. (Appcast hosting + CI release pipeline to follow.)
- Batch processing: drop/open many images into a queue with a thumbnail strip
  (per-item status badges), **Process All** (sequential), and **Export All** to a folder.
- Zoom & inspect the cut-out — pinch / +− / double-click (1–6×), pan, Fit-to-window.
- Crafted empty-state hero and a tasteful motion pass (all Reduce-Motion aware).
- App icon — code-rendered concept finished in Icon Composer (Liquid Glass).
- Light/dark adaptive theme with measured WCAG contrast; app-level text scaling.
- VoiceOver support for the before/after wipe (real accessibility slider).
- Developer tooling: SwiftFormat + SwiftLint configs, git hooks, and `audit.sh`.

### Changed
- Relicensed the app's source from MIT to **PolyForm Noncommercial 1.0.0**
  (non-commercial, source-available); added SPDX headers and a README.
- All models — including RMBG-2.0 — are runtime-downloaded; nothing is bundled.
- Release builds optimize for size (`-Osize`).

### Fixed
- Batch queue no longer retains a decoded input `CGImage` per item (memory).
- Friendly, bounded error messages (no raw ONNX C++ exception dumps in the UI).
