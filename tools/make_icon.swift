// SPDX-FileCopyrightText: 2026 emrikol
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import AppKit
import SwiftUI

/// Brand colors
func P(_ r: Double, _ g: Double, _ b: Double) -> Color {
    Color(.sRGB, red: r, green: g, blue: b)
}

let persimmonTop = P(1.0, 0.44, 0.30) // warm coral
let persimmonBot = P(0.80, 0.22, 0.10) // deep persimmon

struct Checker: View {
    var square: CGFloat
    var body: some View {
        Canvas { ctx, size in
            let cols = Int(ceil(size.width / square)) + 1
            let rows = Int(ceil(size.height / square)) + 1
            for r in 0..<rows {
                for c in 0..<cols {
                    let light = (r + c) % 2 == 0
                    ctx.fill(
                        Path(CGRect(x: CGFloat(c) * square, y: CGFloat(r) * square, width: square, height: square)),
                        with: .color(light ? P(1, 1, 1) : P(0.906, 0.906, 0.906))
                    )
                }
            }
        }
    }
}

struct IconView: View {
    let canvas: CGFloat = 1024
    let tile: CGFloat = 824
    let radius: CGFloat = 185

    var body: some View {
        ZStack {
            ZStack {
                // before/after split: persimmon (the photo) | checkerboard (removed)
                HStack(spacing: 0) {
                    LinearGradient(colors: [persimmonTop, persimmonBot], startPoint: .top, endPoint: .bottom)
                        .frame(width: tile / 2)
                    Checker(square: tile / 20).frame(width: tile / 2)
                }
                .frame(width: tile, height: tile)

                // seam
                Rectangle().fill(.white).frame(width: 5, height: tile)
                    .position(x: tile / 2, y: tile / 2)

                // wipe handle (echoes the in-app control)
                Circle().fill(.white).frame(width: 150, height: 150)
                    .overlay(
                        Image(systemName: "arrow.left.and.right")
                            .font(.system(size: 58, weight: .bold))
                            .foregroundStyle(persimmonBot)
                    )
                    .shadow(color: .black.opacity(0.20), radius: 12, y: 3)
                    .position(x: tile / 2, y: tile / 2)
            }
            .frame(width: tile, height: tile)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .frame(width: canvas, height: canvas)
    }
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/icon-1024.png"
MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: IconView())
    renderer.scale = 1
    guard let cg = renderer.cgImage else { fputs("render failed\n", stderr); exit(1) }
    let rep = NSBitmapImageRep(cgImage: cg)
    guard let png = rep.representation(using: .png, properties: [:]) else { fputs("png failed\n", stderr); exit(1) }
    try! png.write(to: URL(fileURLWithPath: out))
    print("wrote \(out)  \(cg.width)x\(cg.height)")
}
