// SPDX-FileCopyrightText: 2026 emrikol
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import AppKit
import SwiftUI

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
