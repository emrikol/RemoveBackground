// SPDX-FileCopyrightText: 2026 emrikol
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import CoreGraphics
import CoreML
import Foundation
import ImageIO
import OnnxRuntimeBindings
import UniformTypeIdentifiers

struct SegResult {
    let image: CGImage // original RGB with predicted alpha
    let mask: CGImage // grayscale matte at original size
    let time: TimeInterval
    let compute: String
}

protocol Segmenter: AnyObject {
    func removeBackground(from image: CGImage) throws -> SegResult
}

/// Readable errors for the segmentation path (replaces messageless `NSError`s).
enum SegError: LocalizedError {
    case resizeFailed
    case noModelOutput
    case compositeFailed
    var errorDescription: String? {
        switch self {
        case .resizeFailed: return "Could not resize the image."
        case .noModelOutput: return "The model returned no output."
        case .compositeFailed: return "Could not composite the mask onto the image."
        }
    }
}

// MARK: - Shared image ops

enum ImageOps {
    static func resize(_ image: CGImage, _ size: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        return ctx.makeImage()
    }

    /// Resized RGBA8 bytes (noneSkipLast) for `size`×`size`.
    static func rgba(_ image: CGImage, _ size: Int) -> [UInt8]? {
        var buf = [UInt8](repeating: 0, count: size * size * 4)
        buf.withUnsafeMutableBytes { raw in
            if let ctx = CGContext(data: raw.baseAddress, width: size, height: size, bitsPerComponent: 8,
                                   bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            {
                ctx.interpolationQuality = .high
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            }
        }
        return buf
    }

    static func chw(_ rgba: [UInt8], _ size: Int, mean: [Float], std: [Float]) -> [Float] {
        var out = [Float](repeating: 0, count: 3 * size * size)
        let plane = size * size
        for c in 0..<3 {
            let m = mean[c], s = std[c]
            for i in 0..<plane {
                out[c * plane + i] = (Float(rgba[i * 4 + c]) / 255.0 - m) / s
            }
        }
        return out
    }

    static func maskImage(_ pixels: [UInt8], _ side: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: side,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    static func resizeMask(_ mask: CGImage, _ w: Int, _ h: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(mask, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    static func applyMask(_ image: CGImage, _ mask: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard let octx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        octx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let op = octx.data?.bindMemory(to: UInt8.self, capacity: w * h * 4) else { return nil }
        guard let mctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                   space: CGColorSpaceCreateDeviceGray(),
                                   bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        mctx.draw(mask, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let mp = mctx.data?.bindMemory(to: UInt8.self, capacity: w * h) else { return nil }
        // The output context is premultipliedLast, so write premultiplied RGB (RGB×alpha)
        // alongside the alpha — this yields a clean transparent PNG without dark fringing.
        for i in 0..<(w * h) {
            let a = mp[i]
            op[i * 4 + 0] = UInt8(Int(op[i * 4 + 0]) * Int(a) / 255)
            op[i * 4 + 1] = UInt8(Int(op[i * 4 + 1]) * Int(a) / 255)
            op[i * 4 + 2] = UInt8(Int(op[i * 4 + 2]) * Int(a) / 255)
            op[i * 4 + 3] = a
        }
        return octx.makeImage()
    }

    static func composite(image: CGImage, maskPixels: [UInt8], side: Int) -> (CGImage, CGImage)? {
        guard let small = maskImage(maskPixels, side),
              let full = resizeMask(small, image.width, image.height),
              let out = applyMask(image, full) else { return nil }
        return (out, full)
    }
}

func sigmoidF(_ x: Float) -> Float {
    1 / (1 + expf(-x))
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "png", code: 1)
    }
    CGImageDestinationAddImage(dest, image, nil)
    if !CGImageDestinationFinalize(dest) { throw NSError(domain: "png", code: 2) }
}

func loadCGImage(_ path: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

/// Builds the engine for a model: a bundled Core ML model, or an ONNX model that is
/// downloaded on demand (reporting progress). Heavy loading runs off the main actor.
/// Single source of truth for engine construction — used by the UI and the test harness.
func makeEngine(for spec: ModelSpec, onProgress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> Segmenter {
    switch spec.engine {
    case .coreml:
        let url = try await ModelStore.ensureCoreML(spec, progress: onProgress)
        return try await Task.detached { try CoreMLSegmenter(spec: spec, modelURL: url) }.value
    case .ort:
        let path = try await ModelStore.ensure(spec, progress: onProgress)
        return try await Task.detached { try ORTSegmenter(spec: spec, modelPath: path.path) }.value
    }
}

// MARK: - CoreML engine (RMBG-2.0)

/// @unchecked Sendable: holds only an immutable MLModel, whose predictions are
/// thread-safe, and we invoke it from a single detached task at a time.
final class CoreMLSegmenter: Segmenter, @unchecked Sendable {
    private let model: MLModel
    private let spec: ModelSpec
    let compute: String

    init(spec: ModelSpec, modelURL: URL) throws {
        self.spec = spec
        // RMBG-2 fails ANE compilation and `.all` wastes minutes; GPU+CPU is fast.
        let cfg = MLModelConfiguration(); cfg.computeUnits = .cpuAndGPU
        model = try MLModel(contentsOf: modelURL, configuration: cfg)
        compute = "GPU+CPU"
    }

    func removeBackground(from image: CGImage) throws -> SegResult {
        let size = spec.inputSize
        guard let rgba = ImageOps.rgba(image, size) else { throw SegError.resizeFailed }
        let arr = try MLMultiArray(shape: [1, 3, NSNumber(value: size), NSNumber(value: size)], dataType: .float32)
        let chw = ImageOps.chw(rgba, size, mean: kImageNetMean, std: kImageNetStd)
        let dst = arr.dataPointer.bindMemory(to: Float32.self, capacity: chw.count)
        chw.withUnsafeBufferPointer { dst.update(from: $0.baseAddress!, count: chw.count) }

        let provider = try MLDictionaryFeatureProvider(dictionary: ["input": MLFeatureValue(multiArray: arr)])
        let t0 = CFAbsoluteTimeGetCurrent()
        let pred = try model.prediction(from: provider)
        let dt = CFAbsoluteTimeGetCurrent() - t0

        guard let out = pred.featureValue(for: spec.coremlOutputName ?? "output_3")?.multiArrayValue else {
            throw SegError.noModelOutput
        }
        let side = out.shape[2].intValue
        let count = side * side
        var mask = [UInt8](repeating: 0, count: count)
        if out.dataType == .float16 {
            let p = out.dataPointer.bindMemory(to: UInt16.self, capacity: count)
            for i in 0..<count {
                mask[i] = UInt8(max(0, min(1, Float(Float16(bitPattern: p[i])))) * 255)
            }
        } else {
            for i in 0..<count {
                mask[i] = UInt8(max(0, min(1, out[i].floatValue)) * 255)
            }
        }
        guard let (img, m) = ImageOps.composite(image: image, maskPixels: mask, side: side) else {
            throw SegError.compositeFailed
        }
        return SegResult(image: img, mask: m, time: dt, compute: compute)
    }
}

// MARK: - ONNX Runtime engine (BiRefNet variants)

/// @unchecked Sendable: holds an immutable ORT session, used from a single detached
/// task at a time (ONNX Runtime session.run is safe to call serially across threads).
final class ORTSegmenter: Segmenter, @unchecked Sendable {
    private let env: ORTEnv
    private let session: ORTSession
    private let spec: ModelSpec
    private let inputName: String
    private let outputName: String
    let compute: String

    init(spec: ModelSpec, modelPath: String) throws {
        self.spec = spec
        env = try ORTEnv(loggingLevel: .error)
        let opts = try ORTSessionOptions()
        var usedCoreML = spec.usesCoreMLEP
        if spec.usesCoreMLEP {
            do {
                // V2 options enable an on-disk cache of the compiled CoreML model, so the
                // (slow, ~85s) compile only happens on the very first run.
                let cacheDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                    .appendingPathComponent("RemoveBackground/coreml-cache", isDirectory: true)
                try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
                try opts.appendCoreMLExecutionProvider(withOptionsV2: [
                    "MLComputeUnits": "CPUAndGPU",
                    "ModelFormat": "NeuralNetwork",
                    "RequireStaticInputShapes": "1",
                    "ModelCacheDirectory": cacheDir.path,
                ])
            } catch {
                do { try opts.appendCoreMLExecutionProvider(with: ORTCoreMLExecutionProviderOptions()) }
                catch { usedCoreML = false }
            }
        }
        // else: matting → pure CPU EP (CoreML compiler deadlocks on its graph).
        session = try ORTSession(env: env, modelPath: modelPath, sessionOptions: opts)
        inputName = (try? session.inputNames())?.first ?? "input_image"
        outputName = (try? session.outputNames())?.last ?? "output_image"
        compute = usedCoreML ? "CoreML+CPU" : "CPU"
    }

    func removeBackground(from image: CGImage) throws -> SegResult {
        let size = spec.inputSize
        guard let rgba = ImageOps.rgba(image, size) else { throw SegError.resizeFailed }
        var chw = ImageOps.chw(rgba, size, mean: kImageNetMean, std: kImageNetStd)
        let data = NSMutableData(bytes: &chw, length: chw.count * MemoryLayout<Float>.size)
        let input = try ORTValue(tensorData: data, elementType: .float,
                                 shape: [1, 3, NSNumber(value: size), NSNumber(value: size)])

        let t0 = CFAbsoluteTimeGetCurrent()
        let outs = try session.run(withInputs: [inputName: input], outputNames: [outputName], runOptions: nil)
        let dt = CFAbsoluteTimeGetCurrent() - t0
        guard let val = outs[outputName] else { throw SegError.noModelOutput }
        let info = try val.tensorTypeAndShapeInfo()
        let shape = info.shape.map(\.intValue)
        let side = shape[shape.count - 1]
        let count = side * side
        let bytes = try val.tensorData() as Data
        let bpe = bytes.count / max(count, 1)
        var mask = [UInt8](repeating: 0, count: count)
        bytes.withUnsafeBytes { (p: UnsafeRawBufferPointer) in
            if bpe == 4 {
                let f = p.bindMemory(to: Float.self)
                for i in 0..<count {
                    let v = spec.applySigmoid ? sigmoidF(f[i]) : f[i]
                    mask[i] = UInt8(max(0, min(1, v)) * 255)
                }
            } else {
                let f = p.bindMemory(to: UInt16.self)
                for i in 0..<count {
                    let raw = Float(Float16(bitPattern: f[i]))
                    let v = spec.applySigmoid ? sigmoidF(raw) : raw
                    mask[i] = UInt8(max(0, min(1, v)) * 255)
                }
            }
        }
        guard let (img, m) = ImageOps.composite(image: image, maskPixels: mask, side: side) else {
            throw SegError.compositeFailed
        }
        return SegResult(image: img, mask: m, time: dt, compute: compute)
    }
}
