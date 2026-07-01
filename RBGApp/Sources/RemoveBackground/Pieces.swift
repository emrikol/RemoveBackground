// SPDX-FileCopyrightText: 2026 emrikol
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import AppKit
import CoreGraphics
import SwiftUI

// MARK: - Pieces

/// Transparency checkerboard shown behind a cut-out (adapts to light/dark).
struct Checkerboard: View {
    var square: CGFloat = 10
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let base = scheme == .dark ? Color(white: 0.17) : Color(white: 0.965)
        let tile = scheme == .dark ? Color(white: 0.24) : Color(white: 0.90)
        Canvas { ctx, size in
            let cols = Int(size.width / square) + 1, rows = Int(size.height / square) + 1
            for r in 0..<rows {
                for c in 0..<cols where (r + c) % 2 != 0 {
                    ctx.fill(Path(CGRect(x: CGFloat(c) * square, y: CGFloat(r) * square, width: square, height: square)),
                             with: .color(tile))
                }
            }
        }
        .background(base)
    }
}

/// A backdrop the cut-out can be previewed and exported on.
enum Backdrop: Hashable {
    case transparent
    case color(Color)
    case gradient([Color])

    static let presets: [Backdrop] = [
        .transparent,
        .color(.white),
        .color(.black),
        .gradient([Color(red: 1.0, green: 0.45, blue: 0.42), Color(red: 0.98, green: 0.30, blue: 0.52)]),
        .gradient([Color(red: 0.36, green: 0.66, blue: 0.96), Color(red: 0.20, green: 0.42, blue: 0.80)]),
        .gradient([Color(red: 0.96, green: 0.95, blue: 0.92), Color(red: 0.82, green: 0.85, blue: 0.88)]),
    ]

    @ViewBuilder var view: some View {
        switch self {
        case .transparent: Checkerboard()
        case let .color(c): c
        case let .gradient(cs): LinearGradient(colors: cs, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    var isTransparent: Bool {
        if case .transparent = self { return true } else { return false }
    }

    var label: String {
        switch self {
        case .transparent: return "Transparent"
        case let .color(c): return c == .white ? "White" : (c == .black ? "Black" : "Custom color")
        case .gradient: return "Gradient"
        }
    }
}

/// Flattens a transparent cut-out onto a backdrop for export/copy/drag (transparent → unchanged).
func flatten(_ cutout: CGImage, on backdrop: Backdrop) -> CGImage? {
    if backdrop.isTransparent { return cutout }
    let w = cutout.width, h = cutout.height
    let space = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    func cg(_ color: Color) -> CGColor {
        (NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)).cgColor
    }
    switch backdrop {
    case .transparent: break
    case let .color(c):
        ctx.setFillColor(cg(c)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    case let .gradient(colors):
        let arr = colors.map { cg($0) } as CFArray
        if let g = CGGradient(colorsSpace: space, colors: arr, locations: nil) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: h), end: CGPoint(x: w, y: 0), options: [])
        }
    }
    ctx.draw(cutout, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()
}

/// Subtle accent "scan" sweep while the model runs (respects Reduce Motion).
struct ScanShimmer: View {
    @State private var phase: CGFloat = -0.45
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geo in
            if reduceMotion {
                Color.clear
            } else {
                LinearGradient(colors: [.clear, Theme.accent.opacity(0.22), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: geo.size.height * 0.45)
                    .offset(y: geo.size.height * phase)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: false)) { phase = 1.0 }
                    }
            }
        }
        .allowsHitTesting(false)
    }
}

/// One model presented as a selectable card with a quality badge + live download state.
struct ModelCard: View {
    let spec: ModelSpec
    let selected: Bool
    let downloaded: Bool
    let badge: String
    let action: () -> Void
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shortName: String {
        spec.name.components(separatedBy: " — ").first ?? spec.name
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                Text(badge).sFont(10, .bold).tracking(0.8)
                    .foregroundStyle(selected ? Theme.accent : Theme.ink2)
                Text(shortName).sFont(14, .semibold).foregroundStyle(Theme.ink)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: downloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                        .sFont(10)
                    Text(downloaded ? "Ready" : "\(spec.approxMB) MB")
                        .sFont(11, .medium)
                }
                .foregroundStyle(downloaded ? Theme.ready : Theme.ink2)
            }
            .frame(minWidth: 132, alignment: .leading)
            .padding(.horizontal, 11).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 11).fill(selected ? Theme.accent.opacity(0.07) : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(selected ? Theme.accent : Theme.hairline,
                                                               lineWidth: selected ? 1.5 : 1))
            .shadow(color: .black.opacity(hover || selected ? 0.07 : 0.025), radius: hover || selected ? 6 : 3, y: 2)
        }
        .buttonStyle(.plain)
        .scaleEffect(hover && !reduceMotion ? 1.02 : 1.0)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.13), value: hover)
        .accessibilityLabel("\(shortName), \(badge), \(downloaded ? "ready" : "\(spec.approxMB) megabyte download")")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// A background swatch button with hover feedback.
struct Swatch: View {
    let backdrop: Backdrop
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            backdrop.view
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .stroke(selected ? Theme.accent : Theme.hairline, lineWidth: selected ? 2 : 1))
                .scaleEffect(hover ? 1.08 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.1), value: hover)
        .help(backdrop.label)
        .accessibilityLabel("\(backdrop.label) background")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// Empty-state hero: a small "wipe" mark (persimmon | transparency) echoing the
/// app icon and the core action, with a gentle idle float.
struct WipeHeroMark: View {
    var size: CGFloat = 112

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                LinearGradient(colors: [Color(.sRGB, red: 1.0, green: 0.44, blue: 0.30), Theme.accentSolid],
                               startPoint: .top, endPoint: .bottom)
                    .frame(width: size / 2)
                Checkerboard(square: size / 9).frame(width: size / 2)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            Rectangle().fill(.white).frame(width: 2, height: size)
            Circle().fill(.white).frame(width: size * 0.28, height: size * 0.28)
                .overlay(Image(systemName: "arrow.left.and.right")
                    .font(.system(size: size * 0.13, weight: .bold)).foregroundStyle(Theme.accentSolid))
                .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 7)
        .accessibilityHidden(true)
    }
}

/// The hero: original on the left, cut-out on the right, with a draggable wipe.
struct BeforeAfterWipe: View {
    let original: NSImage
    let cutout: NSImage?
    @Binding var fraction: CGFloat
    let busy: Bool
    var backdrop: Backdrop = .transparent
    var zoom: CGFloat = 1 // applied to the IMAGES only; the seam + handle stay screen-space
    @Binding var pan: CGSize
    @GestureState private var isDragging = false
    @FocusState private var focused: Bool
    @State private var dragMode: DragMode?
    @State private var panStart: CGSize = .zero

    private enum DragMode { case wipe, pan }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            // The image aspect-fits the whole card; zooming grows it into that full area (clipped
            // to the card), while the seam + handle stay in screen space at the image's fraction.
            let ar = original.size.width / max(original.size.height, 1)
            let fitW = min(w, h * ar), fitH = min(h, w / ar)
            let minX = (w - fitW) / 2
            let seamX = minX + fitW * fraction
            let off: CGSize = zoom > 1.01 ? pan : .zero
            ZStack(alignment: .topLeading) {
                Image(nsImage: original).resizable()
                    .aspectRatio(ar, contentMode: .fit)
                    .scaleEffect(zoom).offset(off)
                    .frame(width: w, height: h)
                    .accessibilityLabel("Original image")

                if let cutout {
                    ZStack {
                        backdrop.view
                        Image(nsImage: cutout).resizable()
                    }
                    .aspectRatio(ar, contentMode: .fit) // constrain the backdrop to the image, not the letterbox
                    .scaleEffect(zoom).offset(off)
                    .frame(width: w, height: h)
                    .mask(alignment: .trailing) { Rectangle().frame(width: max(0, w - seamX)) }
                    .accessibilityLabel("Cut-out with the background removed")

                    cornerLabel("ORIGINAL", alignment: .topLeading).opacity(fraction > 0.06 ? 1 : 0)
                    cornerLabel("CUT-OUT", alignment: .topTrailing).opacity(fraction < 0.94 ? 1 : 0)
                    handle(x: seamX, h: h, lineHeight: min(fitH * zoom, h))
                }

                if busy { ScanShimmer() }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard cutout != nil else { NSCursor.arrow.set(); return }
                switch phase {
                case let .active(p):
                    // Over the seam → resize (wipe); zoomed and away from it → grab (pan).
                    if zoom > 1.01, abs(p.x - seamX) > 26 { NSCursor.openHand.set() }
                    else { NSCursor.resizeLeftRight.set() }
                case .ended:
                    NSCursor.arrow.set()
                }
            }
            // One drag handles both: grab the seam (or drag anywhere when not zoomed) to wipe;
            // otherwise the drag pans the zoomed image. A single gesture means neither blocks the
            // other, so the comparison slider stays usable while zoomed.
            .gesture(cutout == nil ? nil : DragGesture(minimumDistance: 0)
                .updating($isDragging) { _, s, _ in s = true }
                .onChanged { v in
                    if dragMode == nil {
                        let onSeam = abs(v.startLocation.x - seamX) <= 26
                        if onSeam || zoom <= 1.01 { dragMode = .wipe } else { dragMode = .pan; panStart = pan }
                    }
                    switch dragMode {
                    case .wipe:
                        fraction = min(max((v.location.x - minX) / fitW, 0), 1)
                    case .pan:
                        let lx = (zoom - 1) * fitW / 2, ly = (zoom - 1) * fitH / 2
                        pan = CGSize(width: min(max(panStart.width + v.translation.width, -lx), lx),
                                     height: min(max(panStart.height + v.translation.height, -ly), ly))
                    case .none: break
                    }
                }
                .onEnded { _ in dragMode = nil })
            // Keyboard: focus the wipe (Tab) and nudge with ←/→.
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.accent, lineWidth: 2.5).opacity(focused ? 1 : 0))
            .focusable(cutout != nil)
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(.leftArrow) { fraction = max(0, fraction - 0.04); return .handled }
            .onKeyPress(.rightArrow) { fraction = min(1, fraction + 0.04); return .handled }
            // VoiceOver: expose a real, operable slider.
            .accessibilityElement(children: .ignore)
            .accessibilityRepresentation {
                if cutout != nil {
                    Slider(value: $fraction, in: 0...1)
                        .accessibilityLabel("Before and after reveal")
                        .accessibilityValue("\(Int((1 - fraction) * 100)) percent cut-out shown")
                } else {
                    Color.clear.accessibilityLabel("Original image")
                }
            }
        }
    }

    private func cornerLabel(_ text: String, alignment: Alignment) -> some View {
        Text(text).sFont(10, .bold).tracking(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(.black.opacity(0.45)))
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .allowsHitTesting(false)
    }

    /// Screen-space — outside the image's zoom — so the seam + handle stay a constant size.
    private func handle(x: CGFloat, h: CGFloat, lineHeight: CGFloat) -> some View {
        let wiping = isDragging && dragMode == .wipe
        return ZStack {
            Rectangle().fill(.white).frame(width: 2.5, height: lineHeight)
            Circle().fill(.white).frame(width: 32, height: 32)
                .overlay(Image(systemName: "arrow.left.and.right").sFont(12, .bold)
                    .foregroundStyle(Theme.ink))
                .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
                .scaleEffect(wiping ? 1.18 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: wiping)
        }
        .position(x: x, y: h / 2)
        .allowsHitTesting(false)
    }
}
