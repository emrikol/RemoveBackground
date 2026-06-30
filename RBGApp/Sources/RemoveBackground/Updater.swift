// SPDX-FileCopyrightText: 2026 emrikol
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import Combine
import Sparkle
import SwiftUI

/// Wraps Sparkle's updater for SwiftUI. Update checks are user-initiated via the
/// "Check for Updates…" menu item (SUEnableAutomaticChecks is off in Info.plist).
/// Sparkle transmits only app version, macOS version, and CPU arch when checking.
@MainActor
final class UpdaterViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: SparkleErrorLogger.shared,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

/// The "Check for Updates…" menu command. A View (not just a Button) so it can observe
/// `canCheckForUpdates` and disable itself while a check is already running.
struct CheckForUpdatesView: View {
    @ObservedObject var updater: UpdaterViewModel
    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
    }
}

/// Logs Sparkle errors (Sparkle shows its own user-facing dialogs). Code 1001 = "already
/// up to date", which isn't an error.
final class SparkleErrorLogger: NSObject, SPUUpdaterDelegate {
    static let shared = SparkleErrorLogger()
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let e = error as NSError
        guard e.code != 1001 else { return }
        NSLog("Sparkle update error: %@ [%@:%ld]", e.localizedDescription, e.domain, e.code)
    }
}
