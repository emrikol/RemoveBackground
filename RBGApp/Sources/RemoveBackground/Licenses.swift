// SPDX-FileCopyrightText: 2026 emrikol
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import SwiftUI

/// One attributable component (app code, a model, or a library).
struct LicenseEntry: Identifiable {
    let id = UUID()
    let name: String
    let license: String
    let holder: String
    let url: String
    var nonCommercial = false
}

enum AppLicenses {
    /// Single source of truth — mirrors THIRD_PARTY_NOTICES.md.
    static let entries: [LicenseEntry] = [
        LicenseEntry(name: "RemoveBackground (this app)", license: "PolyForm NC 1.0.0", holder: "© 2026 emrikol",
                     url: "https://github.com/emrikol", nonCommercial: true),
        LicenseEntry(name: "RMBG-2.0 — default model", license: "CC BY-NC 4.0 · non-commercial",
                     holder: "© BRIA AI", url: "https://huggingface.co/briaai/RMBG-2.0", nonCommercial: true),
        LicenseEntry(name: "BiRefNet / -lite / -portrait", license: "MIT", holder: "© Peng Zheng et al.",
                     url: "https://github.com/ZhengPeng7/BiRefNet"),
        LicenseEntry(name: "BiRefNet-matting (ONNX)", license: "MIT", holder: "© Peng Zheng et al.",
                     url: "https://huggingface.co/emrikol/birefnet-matting-onnx"),
        LicenseEntry(name: "ONNX Runtime", license: "MIT", holder: "© Microsoft",
                     url: "https://github.com/microsoft/onnxruntime"),
    ]
}

/// Shown once on first launch (acknowledgment) and re-openable anytime via the
/// "Licenses" button. `isFirstLaunch` toggles the heading + the action button.
struct LicenseSheet: View {
    let isFirstLaunch: Bool
    var onAcknowledge: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(isFirstLaunch ? "Before you start" : "Licenses")
                    .sFont(18, .bold)
                Label("This app is licensed for non-commercial use only.", systemImage: "exclamationmark.triangle.fill")
                    .sFont(13, .semibold).foregroundStyle(.orange)
                Text("Its default model, RMBG-2.0, is CC BY-NC 4.0 (© BRIA AI), and the app’s own code is PolyForm Noncommercial — both non-commercial. Each model and library below is under its own license.")
                    .sFont(12).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(AppLicenses.entries) { e in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.name).sFont(13, .medium)
                                Text(e.holder).sFont(11).foregroundStyle(.secondary)
                                if let u = URL(string: e.url) {
                                    Link(e.url, destination: u).sFont(11)
                                }
                            }
                            Spacer(minLength: 0)
                            Text(e.license).sFont(11, .medium)
                                .foregroundStyle(e.nonCommercial ? .orange : .secondary)
                                .multilineTextAlignment(.trailing).frame(width: 150, alignment: .trailing)
                        }
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        Divider().opacity(0.3)
                    }
                }
            }
            Divider()
            HStack {
                Text("Full text: LICENSE · THIRD_PARTY_NOTICES.md")
                    .sFont(11).foregroundStyle(.secondary)
                Spacer()
                if isFirstLaunch {
                    Button("I Understand") { onAcknowledge() }
                        .buttonStyle(.borderedProminent).tint(Theme.accentSolid).keyboardShortcut(.defaultAction)
                } else {
                    Button("Done") { onClose() }
                        .buttonStyle(.borderedProminent).tint(Theme.accentSolid).keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .frame(width: 540, height: 480)
    }
}
