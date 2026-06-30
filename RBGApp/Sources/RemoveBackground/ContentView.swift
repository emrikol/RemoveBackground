// SPDX-FileCopyrightText: 2026 emrikol
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Theme (editorial · adapts to system light/dark)

extension Color {
    /// Resolves to a different value in light vs dark appearance — live with the system.
    static func dynamic(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

enum Theme {
    /// Light = warm paper white; Dark = deep near-black studio.
    static let canvas = Color.dynamic(NSColor(srgbRed: 0.980, green: 0.976, blue: 0.965, alpha: 1),
                                      NSColor(srgbRed: 0.086, green: 0.086, blue: 0.098, alpha: 1))
    static let card = Color.dynamic(.white,
                                    NSColor(srgbRed: 0.149, green: 0.153, blue: 0.169, alpha: 1))
    static let ink = Color.dynamic(NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1),
                                   NSColor(srgbRed: 0.95, green: 0.95, blue: 0.94, alpha: 1))
    static let ink2 = Color.dynamic(NSColor(srgbRed: 0.40, green: 0.40, blue: 0.42, alpha: 1),
                                    NSColor(srgbRed: 0.64, green: 0.64, blue: 0.67, alpha: 1))
    static let hairline = Color.dynamic(NSColor(white: 0, alpha: 0.09),
                                        NSColor(white: 1, alpha: 0.12))
    /// Accent for TEXT / rings / icons — deep persimmon in light (AA on cream),
    /// brighter coral in dark (AA on near-black). Measured ≥4.5:1 both modes.
    static let accent = Color.dynamic(NSColor(srgbRed: 0.80, green: 0.22, blue: 0.11, alpha: 1),
                                      NSColor(srgbRed: 1.0, green: 0.435, blue: 0.361, alpha: 1))
    // Accent for FILLED buttons (white label). Constant deep persimmon: white-on-it ≈5:1 both modes.
    static let accentSolid = Color(red: 0.80, green: 0.22, blue: 0.11)
    static let ready = Color.dynamic(NSColor(srgbRed: 0.18, green: 0.52, blue: 0.33, alpha: 1),
                                     NSColor(srgbRed: 0.40, green: 0.80, blue: 0.55, alpha: 1))

    static func serif(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// Tracked uppercase section label, editorial style.
    static func label(_ text: String) -> some View {
        Text(text).sFont(11, .semibold).tracking(1.5)
            .foregroundStyle(Theme.ink2)
    }
}

// MARK: - Scalable type (app-level text size — see the View ▸ Text Size menu)

struct UIScaleKey: EnvironmentKey { static let defaultValue: CGFloat = 1.0 }
extension EnvironmentValues {
    var uiScale: CGFloat {
        get { self[UIScaleKey.self] }
        set { self[UIScaleKey.self] = newValue }
    }
}

private struct ScaledFontModifier: ViewModifier {
    @Environment(\.uiScale) private var scale
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight, design: design))
    }
}

extension View {
    /// Like `.font(.system(size:weight:design:))` but multiplied by the app text-size scale.
    func sFont(_ size: CGFloat, _ weight: Font.Weight = .regular, _ design: Font.Design = .default) -> some View {
        modifier(ScaledFontModifier(size: size, weight: weight, design: design))
    }
}

// MARK: - Model

/// One image in the batch queue.
struct BatchItem: Identifiable {
    let id = UUID()
    var image: NSImage
    // The decoded input CGImage is intentionally NOT stored — it's derived on demand at
    // process time (cheap, and `NSImage` caches its rep). Holding one per queued item
    // would pin a full decoded bitmap for every image in the batch.
    var output: NSImage?
    var outputCG: CGImage?
    var state: ItemState = .pending
    var info: String = ""
    var error: String = ""
}

enum ItemState { case pending, processing, done, failed }

@MainActor
final class AppModel: ObservableObject {
    // The queue is the single source of truth; the "active" image is items[selectedIndex].
    @Published var items: [BatchItem] = []
    @Published var selectedIndex = 0
    @Published var status = "Drop an image to begin."
    @Published var isBusy = false
    @Published var progress: Double?
    @Published var selectedID = Models.all[0].id
    @Published var backdrop: Backdrop = .transparent
    @Published var wipe: CGFloat = 0.5
    @Published var errorDetail = "" // raw technical detail (shown only as a tooltip)

    private var engines: [String: Segmenter] = [:]

    var spec: ModelSpec {
        Models.by(id: selectedID)
    }

    var active: BatchItem? {
        items.indices.contains(selectedIndex) ? items[selectedIndex] : nil
    }

    var inputImage: NSImage? {
        active?.image
    }

    var outputImage: NSImage? {
        active?.output
    }

    var info: String {
        active?.info ?? ""
    }

    var hasOutput: Bool {
        active?.output != nil
    }

    var isBatch: Bool {
        items.count > 1
    }

    var pendingCount: Int {
        items.filter { $0.state != .done }.count
    }

    var doneCount: Int {
        items.filter { $0.state == .done }.count
    }

    func load(_ image: NSImage) {
        load([image])
    }

    func load(_ images: [NSImage]) {
        let fresh = images.compactMap { img -> BatchItem? in
            // Validate decodability now; the CGImage itself is re-derived at process time
            // rather than retained for every queued item.
            guard img.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil else { return nil }
            return BatchItem(image: img)
        }
        guard !fresh.isEmpty else { status = "Couldn’t read that image."; return }
        if items.isEmpty { items = fresh; selectedIndex = 0 } else { selectedIndex = items.count; items += fresh }
        wipe = 0.5; errorDetail = ""
        status = isBatch ? "\(items.count) images · \(pendingCount) to process" : "Ready. Click “Remove Background”."
    }

    func loadFromURL(_ url: URL) {
        guard let img = NSImage(contentsOf: url) else { status = "Couldn’t open that file."; return }
        load(img)
    }

    func loadURLs(_ urls: [URL]) {
        let imgs = urls.compactMap { NSImage(contentsOf: $0) }
        if imgs.isEmpty { status = "Couldn’t open those files." } else { load(imgs) }
    }

    /// Switch model; clears results so they re-run with the new one.
    func select(_ id: String) {
        guard id != selectedID, !isBusy else { return }
        selectedID = id
        for i in items.indices {
            items[i].output = nil; items[i].outputCG = nil; items[i].info = ""; items[i].state = .pending
        }
        wipe = 0.5; errorDetail = ""
        if !items.isEmpty {
            status = isBatch ? "\(items.count) images · \(pendingCount) to process" : "Ready. Click “Remove Background”."
        }
    }

    func selectItem(_ i: Int) {
        guard items.indices.contains(i), !isBusy else { return }
        selectedIndex = i; wipe = 0.5
        errorDetail = items[i].state == .failed ? items[i].error : ""
    }

    private func ensureEngine(_ spec: ModelSpec) async throws -> Segmenter {
        if let e = engines[spec.id] { return e }
        if spec.engine == .ort {
            status = "Preparing \(spec.name.components(separatedBy: " — ").first ?? spec.name)…"
        }
        let e = try await makeEngine(for: spec) { p in
            Task { @MainActor in
                self.progress = p
                self.status = "Downloading model… \(Int(p * 100))%  (\(spec.approxMB) MB, one-time)"
            }
        }
        progress = nil
        engines[spec.id] = e
        return e
    }

    func process() async {
        guard !isBusy, !items.isEmpty else { return }
        isBusy = true; errorDetail = ""
        if isBatch {
            let queue = items.indices.filter { items[$0].state != .done }
            for (n, i) in queue.enumerated() {
                status = "Removing backgrounds… \(n + 1) of \(queue.count)"
                await processItem(i)
            }
            status = "Done ✓  \(doneCount) of \(items.count)"
            announce("Finished \(doneCount) of \(items.count) images.")
        } else {
            status = "Removing background…"
            await processItem(selectedIndex)
        }
        isBusy = false; progress = nil
    }

    private func processItem(_ i: Int) async {
        guard items.indices.contains(i) else { return }
        items[i].state = .processing; items[i].error = ""
        guard let cg = items[i].image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            items[i].state = .failed; items[i].error = "Couldn’t read that image."
            if !isBatch { errorDetail = items[i].error; status = "Couldn’t read that image." }
            return
        }
        let spec = spec
        do {
            let engine = try await ensureEngine(spec)
            progress = nil
            let result = try await Task.detached(priority: .userInitiated) { try engine.removeBackground(from: cg) }.value
            guard items.indices.contains(i) else { return }
            items[i].outputCG = result.image
            items[i].output = NSImage(cgImage: result.image, size: NSSize(width: result.image.width, height: result.image.height))
            items[i].info = "\(result.image.width) × \(result.image.height) · \(result.compute) · \(String(format: "%.1f", result.time))s"
            items[i].state = .done
            if !isBatch { status = "Done ✓"; announce("Background removed. \(items[i].info)") }
        } catch {
            guard items.indices.contains(i) else { return }
            items[i].state = .failed
            items[i].error = error.localizedDescription
            if !isBatch {
                errorDetail = error.localizedDescription
                status = friendlyError(error)
                announce("Background removal failed. \(status)")
            }
        }
    }

    /// Posts a VoiceOver announcement so completion/failure isn't silent for screen-reader users.
    private func announce(_ message: String) {
        guard let target = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        NSAccessibility.post(element: target, notification: .announcementRequested,
                             userInfo: [.announcement: message,
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    /// Turns a raw engine/network error into a short, human, non-scary message.
    private func friendlyError(_ error: Error) -> String {
        if (error as NSError).domain == NSURLErrorDomain {
            return "Download failed — check your connection and Run Again."
        }
        let name = spec.name.components(separatedBy: " — ").first ?? "the model"
        return "Couldn’t load \(name) — the download may be incomplete. Run Again to retry."
    }

    /// The cut-out flattened onto the chosen backdrop (or the transparent cut-out itself).
    func exportCG() -> CGImage? {
        guard let cg = active?.outputCG else { return nil }
        return flatten(cg, on: backdrop)
    }

    func save() {
        guard let cg = exportCG() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = backdrop.isTransparent ? "cutout-no-bg.png" : "cutout.png"
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            try? writePNG(cg, to: url)
        }
    }

    func copy() {
        guard let cg = exportCG() else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))])
        status = "Copied to clipboard ✓"
    }

    /// Writes the current export to a temp PNG for drag-out, returns its URL.
    func exportTempPNG() -> URL? {
        guard let cg = exportCG() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cutout-no-bg.png")
        try? writePNG(cg, to: url)
        return url
    }

    /// Export every finished cut-out to a chosen folder (batch).
    func exportAll() {
        let bd = backdrop
        let exports: [(Int, CGImage)] = items.enumerated().compactMap { i, it in
            guard it.state == .done, let cg = it.outputCG, let f = flatten(cg, on: bd) else { return nil }
            return (i, f)
        }
        guard !exports.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.prompt = "Export \(exports.count)"; panel.message = "Choose a folder for the cut-outs"
        panel.begin { resp in
            guard resp == .OK, let dir = panel.url else { return }
            for (i, cg) in exports {
                try? writePNG(cg, to: dir.appendingPathComponent(String(format: "cutout-%02d.png", i + 1)))
            }
            Task { @MainActor in self.status = "Exported \(exports.count) cut-outs ✓" }
        }
    }

    func reset() {
        items = []; selectedIndex = 0
        status = "Drop an image to begin."; wipe = 0.5; errorDetail = ""
    }

    func resetWipe() {
        wipe = 0.5
    }

    func openImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { loadURLs(panel.urls) }
    }

    func isDownloaded(_ spec: ModelSpec) -> Bool {
        ModelStore.isDownloaded(spec)
    }
}

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var float = false

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
        .offset(y: float ? -5 : 0)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { float = true }
        }
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
    var interactive: Bool = true // false while zoomed (drag pans instead of wipes)
    @GestureState private var isDragging = false
    @FocusState private var focused: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                Image(nsImage: original).resizable().scaledToFit()
                    .frame(width: w, height: h)
                    .accessibilityLabel("Original image")

                if let cutout {
                    ZStack {
                        backdrop.view
                        Image(nsImage: cutout).resizable().scaledToFit()
                    }
                    .frame(width: w, height: h)
                    .mask(alignment: .trailing) { Rectangle().frame(width: max(0, w * (1 - fraction))) }
                    .accessibilityLabel("Cut-out with the background removed")

                    cornerLabel("ORIGINAL", alignment: .topLeading).opacity(fraction > 0.06 ? 1 : 0)
                    cornerLabel("CUT-OUT", alignment: .topTrailing).opacity(fraction < 0.94 ? 1 : 0)
                    handle(w: w, h: h)
                }

                if busy { ScanShimmer() }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard cutout != nil else { return }
                if case .active = phase { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() }
            }
            .gesture(cutout == nil || !interactive ? nil : DragGesture(minimumDistance: 0)
                .updating($isDragging) { _, s, _ in s = true }
                .onChanged { v in fraction = min(max(v.location.x / w, 0), 1) })
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

    private func handle(w: CGFloat, h: CGFloat) -> some View {
        let x = w * fraction
        return ZStack {
            Rectangle().fill(.white).frame(width: 2.5, height: h)
            Circle().fill(.white).frame(width: 32, height: 32)
                .overlay(Image(systemName: "arrow.left.and.right").sFont(12, .bold)
                    .foregroundStyle(Theme.ink))
                .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
                .scaleEffect(isDragging ? 1.18 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isDragging)
        }
        .position(x: x, y: h / 2)
        .allowsHitTesting(false)
    }
}

// MARK: - Root

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var dragOver = false
    @AppStorage("acknowledgedNonCommercial_v1") private var acknowledged = false
    @AppStorage("lastModelID") private var lastModelID = Models.all[0].id
    @AppStorage("uiScale") private var uiScale: Double = 1.0
    @State private var showLicenses = false
    @State private var customColor: Color = .white
    @State private var dragOutHover = false
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    @State private var pan: CGSize = .zero
    @GestureState private var dragPan: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var zoomLevel: CGFloat {
        min(max(zoom * pinch, 1), 6)
    }

    private func stepZoom(_ d: CGFloat) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            zoom = min(max(zoom + d, 1), 6); if zoom <= 1.01 { zoom = 1; pan = .zero }
        }
    }

    private func resetZoom() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { zoom = 1; pan = .zero }
    }

    private func badge(_ id: String) -> String {
        switch id {
        case "rmbg2": return "RECOMMENDED"
        case "birefnet": return "MAX QUALITY"
        case "birefnet_lite": return "FASTEST"
        case "birefnet_portrait": return "PORTRAITS"
        case "birefnet_matting": return "SOFT ALPHA"
        default: return "MODEL"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            brandBar
            Divider().overlay(Theme.hairline)
            modelRow
            if model.isBatch { batchStrip.transition(.opacity) }
            content
            if model.hasOutput { studioRow.transition(.move(edge: .bottom).combined(with: .opacity)) }
            actionBar
        }
        .background(Theme.canvas)
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.85), value: model.hasOutput)
        .environment(\.uiScale, CGFloat(min(max(uiScale, 0.8), 1.5)))
        .onDrop(of: [.fileURL, .image], isTargeted: $dragOver) { handleDrop($0) }
        .onPasteCommand(of: [.fileURL, .image]) { _ = handleDrop($0) }
        .overlay(alignment: .top) {
            if dragOver {
                Label("Drop to load image", systemImage: "tray.and.arrow.down.fill")
                    .sFont(13, .semibold).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Theme.accentSolid, in: Capsule()).padding(.top, 12).transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: dragOver)
        .onChange(of: model.outputImage != nil) { _, hasOutput in
            guard hasOutput else { return }
            model.wipe = 1.0
            withAnimation(reduceMotion ? nil : .spring(response: 0.65, dampingFraction: 0.72)) { model.wipe = 0.5 }
        }
        .onAppear {
            if !acknowledged { showLicenses = true }
            if Models.all.contains(where: { $0.id == lastModelID }) { model.selectedID = lastModelID }
        }
        .onChange(of: model.selectedID) { _, id in lastModelID = id }
        .sheet(isPresented: $showLicenses) {
            LicenseSheet(isFirstLaunch: !acknowledged,
                         onAcknowledge: { acknowledged = true; showLicenses = false },
                         onClose: { showLicenses = false })
                .environment(\.uiScale, CGFloat(min(max(uiScale, 0.8), 1.5))) // sheets get a fresh environment
        }
    }

    private var brandBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Remove Background").sFont(22, .bold, .serif).foregroundStyle(Theme.ink)
            Spacer()
            Label("on-device · private", systemImage: "lock.fill")
                .sFont(11, .medium).foregroundStyle(Theme.ink2)
            Button(action: { showLicenses = true }) { Image(systemName: "info.circle") }
                .buttonStyle(.plain).foregroundStyle(Theme.ink2)
                .help("Licenses · non-commercial use")
                .accessibilityLabel("Licenses and non-commercial use notice")
        }
        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
    }

    private var modelRow: some View {
        VStack(spacing: 7) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ForEach(Models.all) { m in
                        ModelCard(spec: m, selected: m.id == model.selectedID,
                                  downloaded: model.isDownloaded(m), badge: badge(m.id)) { model.select(m.id) }
                    }
                }
                .padding(.horizontal, 20)
            }
            .disabled(model.isBusy)
            .opacity(model.isBusy ? 0.55 : 1)
            HStack(spacing: 6) {
                Text(model.spec.blurb).foregroundStyle(Theme.ink2)
                Text("· \(model.spec.license)").foregroundStyle(model.spec.license.contains("NC") ? Theme.accent : Theme.ink2)
            }
            .sFont(11).padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
    }

    private var primaryActionTitle: String {
        if model.isBatch { return model.pendingCount > 0 ? "Remove All (\(model.pendingCount))" : "Run All Again" }
        return model.hasOutput ? "Run Again" : "Remove Background"
    }

    private var batchStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { i, item in
                    Button { model.selectItem(i) } label: { thumb(item, index: i) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 3)
        }
        .frame(height: 80)
    }

    private func thumb(_ item: BatchItem, index: Int) -> some View {
        let selected = index == model.selectedIndex
        return Image(nsImage: item.output ?? item.image)
            .resizable().scaledToFill()
            .frame(width: 64, height: 64).clipped()
            .background(Checkerboard(square: 8))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? Theme.accent : Theme.hairline, lineWidth: selected ? 2.5 : 1))
            .overlay(alignment: .bottomTrailing) { stateBadge(item.state).padding(4) }
            .shadow(color: .black.opacity(selected ? 0.18 : 0), radius: 5, y: 2)
            .accessibilityLabel("Image \(index + 1) of \(model.items.count), \(stateText(item.state))\(selected ? ", selected" : "")")
    }

    @ViewBuilder private func stateBadge(_ s: ItemState) -> some View {
        switch s {
        case .processing:
            ProgressView().controlSize(.small).scaleEffect(0.7)
                .frame(width: 18, height: 18).background(Circle().fill(.regularMaterial))
        case .done:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 16)).foregroundStyle(.white, Theme.ready)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").font(.system(size: 16)).foregroundStyle(.white, .red)
        case .pending:
            EmptyView()
        }
    }

    private func stateText(_ s: ItemState) -> String {
        switch s {
        case .pending: return "pending"
        case .processing: return "processing"
        case .done: return "done"
        case .failed: return "failed"
        }
    }

    private var content: some View {
        Group {
            if model.inputImage == nil { dropZone.transition(.opacity) } else { canvas.transition(.opacity) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: model.inputImage == nil)
    }

    private var canvas: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(Theme.card)
                .shadow(color: .black.opacity(0.05), radius: 14, y: 5)
            if let input = model.inputImage {
                // Size the wipe to the image's aspect ratio so it sits centered and tight,
                // matted by the surrounding card. Pinch / +- to zoom, drag to pan when zoomed.
                BeforeAfterWipe(original: input, cutout: model.outputImage, fraction: $model.wipe,
                                busy: model.isBusy, backdrop: model.backdrop, interactive: zoomLevel <= 1.01)
                    .aspectRatio(input.size.width / max(input.size.height, 1), contentMode: .fit)
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.hairline, lineWidth: 1)) // print frame
                    .scaleEffect(zoomLevel)
                    .offset(x: pan.width + dragPan.width, y: pan.height + dragPan.height)
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
                    .padding(18)
                    .gesture(MagnifyGesture()
                        .updating($pinch) { v, s, _ in s = v.magnification }
                        .onEnded { v in zoom = min(max(zoom * v.magnification, 1), 6); if zoom <= 1.01 { zoom = 1; pan = .zero } })
                    .simultaneousGesture(zoomLevel > 1.01 ? DragGesture()
                        .updating($dragPan) { v, s, _ in s = v.translation }
                        .onEnded { v in
                            let lim = (zoom - 1) * 420
                            pan.width = min(max(pan.width + v.translation.width, -lim), lim)
                            pan.height = min(max(pan.height + v.translation.height, -lim), lim)
                        } : nil)
                    .onTapGesture(count: 2) { zoom > 1 ? resetZoom() : stepZoom(1.5) }
            }
            if model.isBusy, model.outputImage == nil {
                VStack(spacing: 10) {
                    if let p = model.progress {
                        ProgressView(value: p).progressViewStyle(.linear).frame(width: 200).tint(Theme.accent)
                        Text("Downloading model… \(Int(p * 100))%").sFont(12).foregroundStyle(Theme.ink2)
                    } else {
                        ProgressView().controlSize(.large)
                        Text("Removing background…").sFont(12).foregroundStyle(Theme.ink2)
                    }
                }
                .padding(18).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .combine)
            }
            if model.inputImage != nil { zoomControls }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14)) // keep zoomed content inside the card
        .padding(.vertical, 4)
        .onChange(of: model.info) { _, _ in resetZoom() } // new image / new result → back to fit
    }

    private var zoomControls: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                HStack(spacing: 4) {
                    Button { stepZoom(-0.5) } label: { Image(systemName: "minus") }
                        .disabled(zoomLevel <= 1.01).accessibilityLabel("Zoom out")
                    Text("\(Int(zoomLevel * 100))%").sFont(11, .medium).monospacedDigit().frame(width: 42)
                        .accessibilityLabel("Zoom \(Int(zoomLevel * 100)) percent")
                    Button { stepZoom(0.5) } label: { Image(systemName: "plus") }
                        .disabled(zoomLevel >= 5.99).accessibilityLabel("Zoom in")
                    if zoom > 1 {
                        Divider().frame(height: 14)
                        Button { resetZoom() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                            .help("Fit").accessibilityLabel("Fit to window")
                    }
                }
                .buttonStyle(.plain).foregroundStyle(Theme.ink).sFont(12, .semibold)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(Theme.hairline))
                .padding(28)
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 18) {
            WipeHeroMark().padding(.bottom, 2)
            Text("Drop an image to remove its background").sFont(21, .semibold, .serif).foregroundStyle(Theme.ink)
            Text("Drop · paste · or choose  —  PNG, JPG, WebP, HEIC, processed entirely on your Mac")
                .sFont(12).foregroundStyle(Theme.ink2)
            Button("Choose Image…") { model.openImage() }
                .buttonStyle(.borderedProminent).tint(Theme.accentSolid).controlSize(.large)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(48)
        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.card)
            .shadow(color: .black.opacity(0.05), radius: 14, y: 5))
        .overlay(RoundedRectangle(cornerRadius: 20)
            .strokeBorder(style: StrokeStyle(lineWidth: dragOver ? 2.5 : 1.5, dash: [9]))
            .foregroundStyle(dragOver ? Theme.accent : Theme.hairline))
        .scaleEffect(dragOver && !reduceMotion ? 1.004 : 1.0)
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Image drop zone. Drop, paste, or choose an image.")
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            if model.inputImage != nil {
                Button(action: { Task { await model.process() } }) {
                    Label(primaryActionTitle, systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent).tint(Theme.accentSolid).controlSize(.large)
                .disabled(model.isBusy).keyboardShortcut(.defaultAction)

                if model.isBatch {
                    Button(action: { model.exportAll() }) { Label("Export All…", systemImage: "square.and.arrow.down.on.square") }
                        .buttonStyle(.bordered).controlSize(.large).disabled(model.doneCount == 0)
                } else {
                    Button(action: { model.save() }) { Label("Save PNG", systemImage: "square.and.arrow.down") }
                        .buttonStyle(.bordered).controlSize(.large).disabled(!model.hasOutput)
                    Button(action: { model.copy() }) { Label("Copy", systemImage: "doc.on.doc") }
                        .buttonStyle(.bordered).controlSize(.large).disabled(!model.hasOutput)
                }

                Button(action: { model.reset() }) { Label("New", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(.bordered).controlSize(.large)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if model.isBusy { ProgressView().controlSize(.small) }
                    if !model.errorDetail.isEmpty {
                        Image(systemName: "exclamationmark.triangle.fill").sFont(11)
                    }
                    Text(model.status).sFont(12, .medium)
                        .lineLimit(2).multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(model.errorDetail.isEmpty ? Theme.ink : Color.red)
                .frame(maxWidth: 340, alignment: .trailing)
                .help(model.errorDetail) // raw technical detail on hover only
                if !model.info.isEmpty { Text(model.info).sFont(11).foregroundStyle(Theme.ink2) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Status: \(model.status). \(model.info)")
            .accessibilityAddTraits(.updatesFrequently)
        }
        .padding(.horizontal, 20).padding(.vertical, 13)
        .background(Theme.card.overlay(Divider().overlay(Theme.hairline), alignment: .top))
    }

    private var studioRow: some View {
        HStack(spacing: 9) {
            Theme.label("BACKGROUND")
            ForEach(Array(Backdrop.presets.enumerated()), id: \.offset) { _, b in
                Swatch(backdrop: b, selected: model.backdrop == b) { model.backdrop = b }
            }
            ColorPicker("", selection: $customColor, supportsOpacity: false)
                .labelsHidden().frame(width: 30)
                .onChange(of: customColor) { _, c in model.backdrop = .color(c) }
                .help("Custom background color")
            Spacer()
            dragOutChip
        }
        .padding(.horizontal, 20).padding(.vertical, 9)
    }

    private var dragOutChip: some View {
        Label("Drag out", systemImage: "arrow.up.forward.square")
            .sFont(11, .medium)
            .foregroundStyle(dragOutHover ? Theme.accent : Theme.ink2)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(dragOutHover ? Theme.accent.opacity(0.6) : Theme.hairline)))
            .onDrag {
                if let url = model.exportTempPNG() { return NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                return NSItemProvider()
            }
            .onHover { dragOutHover = $0 }
            .animation(.easeOut(duration: 0.12), value: dragOutHover)
            .help("Drag the cut-out into Finder, Keynote, Messages…")
            .accessibilityLabel("Drag the cut-out out to another app")
    }

    @discardableResult private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        // Files (one or many) → load them all into the queue, preserving order.
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        if !fileProviders.isEmpty {
            var urls = [URL?](repeating: nil, count: fileProviders.count)
            let group = DispatchGroup()
            for (i, p) in fileProviders.enumerated() {
                group.enter()
                p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    if let u = item as? URL { urls[i] = u }
                    else if let d = item as? Data { urls[i] = URL(dataRepresentation: d, relativeTo: nil) }
                    group.leave()
                }
            }
            group.notify(queue: .main) { model.loadURLs(urls.compactMap { $0 }) }
            return true
        }
        // A pasted/dragged image object (no file URL).
        if let provider = providers.first, provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { obj, _ in
                if let img = obj as? NSImage { DispatchQueue.main.async { model.load(img) } }
            }
            return true
        }
        return false
    }
}
