// SPDX-FileCopyrightText: 2026 emrikol
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import AppKit
import CoreGraphics
import SwiftUI

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

    /// Removes one image from the queue, keeping the selection sensible (and returning to the
    /// empty state if it was the last one). Disabled while a batch is processing.
    func removeItem(_ i: Int) {
        guard items.indices.contains(i), !isBusy else { return }
        let removedSelected = i == selectedIndex
        items.remove(at: i)
        if items.isEmpty {
            selectedIndex = 0; wipe = 0.5; errorDetail = ""
            status = "Drop an image to begin."
            return
        }
        if i < selectedIndex { selectedIndex -= 1 }
        selectedIndex = min(selectedIndex, items.count - 1)
        if removedSelected {
            wipe = 0.5
            errorDetail = items[selectedIndex].state == .failed ? items[selectedIndex].error : ""
        }
        status = isBatch ? "\(items.count) images · \(pendingCount) to process" : "Ready. Click “Remove Background”."
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
    func friendlyError(_ error: Error) -> String {
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
