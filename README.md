# Remove Background

[![License: PolyForm Noncommercial 1.0.0](https://img.shields.io/badge/license-PolyForm%20Noncommercial%201.0.0-D43C1E)](LICENSE)
[![Use: Non-commercial](https://img.shields.io/badge/use-non--commercial-D43C1E)](LICENSE)
[![Platform: macOS 14+](https://img.shields.io/badge/platform-macOS%2014%2B-555555)](#build)

A native macOS app that removes image backgrounds **entirely on-device** — nothing
ever leaves your Mac. Drop an image (or many), pick a model, and get a clean cut-out
with a before/after wipe, a background studio, zoom-to-inspect, and batch processing.

- **Models:** RMBG-2.0 (Core ML, default), BiRefNet / -lite / -portrait, BiRefNet-matting (ONNX)
- **Private:** all inference is local; models download once and cache under
  `~/Library/Application Support/RemoveBackground/`
- **No bundled weights:** the app ships with *no* model files — each is fetched at
  runtime from its own host the first time you use it.

## License

The app's **source code** is licensed under the **[PolyForm Noncommercial License
1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0)** — see `LICENSE`.

You may use, modify, and share it **for any non-commercial purpose**. You may **not**
use it commercially (e.g. selling it, or selling a product based on it). This is a
**source-available, non-commercial** license — *not* an OSI "open source" license.

This is also consistent with the app as a whole: its default model, **RMBG-2.0**, is
**CC BY-NC 4.0** (© BRIA AI), so the app is non-commercial regardless. The bundled
**ONNX Runtime** is MIT. Full attributions are in `THIRD_PARTY_NOTICES.md` and in the
app's **Licenses** panel.

## Build

Requires macOS 14+ (the Liquid Glass app icon renders on macOS 26+) and Xcode tools.

```sh
cd RBGApp
swift build -c release      # the app itself — needs no model files
./build_app.sh              # assemble + sign + install to ~/Applications, with the app icon
```

## Development

```sh
./scripts/install-hooks.sh   # pre-commit: SwiftFormat + SwiftLint; pre-push: CHANGELOG check
swiftformat RBGApp/Sources tools   # apply formatting (config: .swiftformat)
swiftlint lint                     # lint the app sources (config: .swiftlint.yml)
./audit.sh                         # pre-release gate: format/lint, release build, bundle checks
```

Conventions follow [`CHANGELOG.md`](CHANGELOG.md) (Keep a Changelog). Tag releases
with `scripts/create-release-tag.sh vX.Y.Z`, which validates the CHANGELOG first.

## Distributing a binary

You *can* hand out a free compiled build — the binary contains only your code +
ONNX Runtime (no models), so you never redistribute a restricted model. Checklist:

- [ ] **Free / non-commercial only** — both PolyForm-NC and RMBG-2.0 forbid selling it.
- [ ] **Ship the notices** — include `LICENSE` and `THIRD_PARTY_NOTICES.md` alongside
      the `.app` (the in-app first-launch non-commercial notice already travels inside it).
- [ ] **Notarize for public release** — the default build is ad-hoc signed, so Gatekeeper
      warns. For a real public download, sign with an Apple **Developer ID** and notarize.
- [ ] **No models bundled** — keep it that way; models stay runtime-downloaded.
