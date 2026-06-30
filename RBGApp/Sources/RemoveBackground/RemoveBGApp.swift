// SPDX-FileCopyrightText: 2026 emrikol
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import AppKit
import CoreGraphics
import SwiftUI

@main
struct RemoveBGApp: App {
    #if DEBUG
        // Debug-only: enables the RBG_HEADLESS self-test harness below.
        @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    /// Owned here so the menu bar and the window share one model.
    @StateObject private var model = AppModel()
    @StateObject private var updater = UpdaterViewModel()

    var body: some Scene {
        WindowGroup("Remove Background") {
            ContentView(model: model)
                .frame(minWidth: 900, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            AppCommands(model: model)
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updater)
            }
        }
    }
}

// MARK: - Menu bar

/// Native File / Image menus driving the shared model (keyboard shortcuts live here).
struct AppCommands: Commands {
    @ObservedObject var model: AppModel
    @AppStorage("uiScale") private var uiScale: Double = 1.0

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Image…") { model.openImage() }
                .keyboardShortcut("o", modifiers: .command)
            Button("New") { model.reset() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(model.inputImage == nil)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save Cut-Out…") { model.save() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!model.hasOutput)
        }
        CommandMenu("Image") {
            Button(model.hasOutput ? "Run Again" : "Remove Background") {
                Task { await model.process() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.inputImage == nil || model.isBusy)

            Button("Copy Cut-Out") { model.copy() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!model.hasOutput)

            Divider()
            Button("Reset Comparison") { model.resetWipe() }
                .disabled(!model.hasOutput)
        }
        CommandGroup(after: .toolbar) {
            Button("Larger Text") { uiScale = min(1.5, uiScale + 0.1) }
                .keyboardShortcut("=", modifiers: .command)
            Button("Smaller Text") { uiScale = max(0.8, uiScale - 0.1) }
                .keyboardShortcut("-", modifiers: .command)
            Button("Actual Size (Text)") { uiScale = 1.0 }
                .keyboardShortcut("0", modifiers: .command)
        }
    }
}

#if DEBUG
    /// Debug-only, window-independent self-test. `RBG_HEADLESS=<modelId>|<in>|<out.png>`
    /// runs the real engine for that model and quits — fires on launch regardless of UI.
    final class AppDelegate: NSObject, NSApplicationDelegate {
        func applicationDidFinishLaunching(_: Notification) {
            guard let spec = ProcessInfo.processInfo.environment["RBG_HEADLESS"] else { return }
            let p = spec.components(separatedBy: "|")
            guard p.count == 3, let cg = loadCGImage(p[1]) else {
                FileHandle.standardError.write(Data("HEADLESS_FAIL bad-args\n".utf8)); NSApp.terminate(nil); return
            }
            let model = Models.by(id: p[0])
            Task.detached {
                let t0 = CFAbsoluteTimeGetCurrent()
                do {
                    let engine = try await makeEngine(for: model)
                    let r = try engine.removeBackground(from: cg)
                    try writePNG(r.image, to: URL(fileURLWithPath: p[2]))
                    let total = CFAbsoluteTimeGetCurrent() - t0
                    FileHandle.standardError.write(Data("HEADLESS_DONE compute=\(r.compute) infer=\(String(format: "%.1f", r.time))s total=\(String(format: "%.1f", total))s\n".utf8))
                } catch {
                    FileHandle.standardError.write(Data("HEADLESS_FAIL \(error)\n".utf8))
                }
                await MainActor.run { NSApp.terminate(nil) }
            }
        }
    }
#endif
