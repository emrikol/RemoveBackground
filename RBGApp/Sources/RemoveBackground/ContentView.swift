// SPDX-FileCopyrightText: 2026 emrikol
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

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
                        .overlay(alignment: .topTrailing) {
                            if !model.isBusy {
                                Button { model.removeItem(i) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 17))
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                        .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
                                }
                                .buttonStyle(.plain)
                                .padding(2)
                                .help("Remove from queue")
                                .accessibilityLabel("Remove image \(i + 1) from the queue")
                            }
                        }
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
                                busy: model.isBusy, backdrop: model.backdrop, zoom: zoomLevel, pan: $pan)
                    .gesture(MagnifyGesture()
                        .updating($pinch) { v, s, _ in s = v.magnification }
                        .onEnded { v in zoom = min(max(zoom * v.magnification, 1), 6); if zoom <= 1.01 { zoom = 1; pan = .zero } })
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
