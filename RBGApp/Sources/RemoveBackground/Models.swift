// SPDX-FileCopyrightText: 2026 emrikol
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import CoreML
import Foundation

enum Engine { case coreml, ort }

/// One selectable background-removal model. Every model is downloaded on demand and
/// cached — nothing is bundled in the app.
struct ModelSpec: Identifiable, Hashable {
    let id: String
    let name: String
    let blurb: String
    let license: String
    let engine: Engine

    // CoreML: a multi-file `.mlpackage` downloaded from `coremlBaseURL` (one entry per
    // relative path in `coremlFiles`), reconstructed, then compiled to `.mlmodelc`.
    let coremlBaseURL: String?
    let coremlFiles: [String]
    let coremlOutputName: String? // e.g. "output_3"

    // ORT: a single `.onnx` downloaded on demand.
    let downloadURL: URL?
    let fileName: String?

    let approxMB: Int

    // shared preprocessing / output handling
    let inputSize: Int
    let applySigmoid: Bool // ORT BiRefNet logits need sigmoid; RMBG-2 CoreML already sigmoid

    /// For ORT models: run via the Core ML execution provider. Set false for matting —
    /// its grid_sample-heavy graph deadlocks the Core ML/ANE compiler, so it uses CPU.
    /// Ignored for the Core ML engine.
    let usesCoreMLEP: Bool

    static func == (a: ModelSpec, b: ModelSpec) -> Bool {
        a.id == b.id
    }

    func hash(into h: inout Hasher) {
        h.combine(id)
    }
}

// ImageNet normalization — used by RMBG-2 and all BiRefNet variants.
let kImageNetMean: [Float] = [0.485, 0.456, 0.406]
let kImageNetStd: [Float] = [0.229, 0.224, 0.225]

enum Models {
    static let all: [ModelSpec] = [
        ModelSpec(
            id: "rmbg2",
            name: "RMBG-2.0 — balanced (recommended)",
            blurb: "Balanced and BRIA-trained — excellent all-round quality, on the GPU in seconds.",
            license: "CC-BY-NC-4.0 (non-commercial)",
            engine: .coreml,
            coremlBaseURL: "https://huggingface.co/VincentGOURBIN/RMBG-2-CoreML/resolve/main/RMBG-2-native.mlpackage",
            coremlFiles: [
                "Manifest.json",
                "Data/com.apple.CoreML/model.mlmodel",
                "Data/com.apple.CoreML/weights/weight.bin",
            ],
            coremlOutputName: "output_3",
            downloadURL: nil, fileName: nil,
            approxMB: 461,
            inputSize: 1024, applySigmoid: false, usesCoreMLEP: true
        ),
        ModelSpec(
            id: "birefnet",
            name: "BiRefNet (full) — maximum quality",
            blurb: "The original BiRefNet at full size — the sharpest edges and hair.",
            license: "MIT",
            engine: .ort,
            coremlBaseURL: nil, coremlFiles: [], coremlOutputName: nil,
            downloadURL: URL(string: "https://huggingface.co/onnx-community/BiRefNet-ONNX/resolve/main/onnx/model_fp16.onnx"),
            fileName: "birefnet_fp16.onnx",
            approxMB: 467,
            inputSize: 1024, applySigmoid: true, usesCoreMLEP: true
        ),
        ModelSpec(
            id: "birefnet_lite",
            name: "BiRefNet-lite — fast",
            blurb: "Lighter and quicker. Still very good for everyday cutouts.",
            license: "MIT",
            engine: .ort,
            coremlBaseURL: nil, coremlFiles: [], coremlOutputName: nil,
            downloadURL: URL(string: "https://huggingface.co/onnx-community/BiRefNet_lite-ONNX/resolve/main/onnx/model_fp16.onnx"),
            fileName: "birefnet_lite_fp16.onnx",
            approxMB: 109,
            inputSize: 1024, applySigmoid: true, usesCoreMLEP: true
        ),
        ModelSpec(
            id: "birefnet_portrait",
            name: "BiRefNet-portrait — best for people / hair",
            blurb: "Tuned for people — the finest hair and edge detail on portraits.",
            license: "MIT",
            engine: .ort,
            coremlBaseURL: nil, coremlFiles: [], coremlOutputName: nil,
            downloadURL: URL(string: "https://huggingface.co/onnx-community/BiRefNet-portrait-ONNX/resolve/main/onnx/model_fp16.onnx"),
            fileName: "birefnet_portrait_fp16.onnx",
            approxMB: 467,
            inputSize: 1024, applySigmoid: true, usesCoreMLEP: true
        ),
        ModelSpec(
            id: "birefnet_matting",
            name: "BiRefNet-matting — soft alpha (finest edges)",
            blurb: "True alpha matting: feathery hair, fur, and semi-transparency. The slowest to run.",
            license: "MIT",
            engine: .ort,
            coremlBaseURL: nil, coremlFiles: [], coremlOutputName: nil,
            downloadURL: URL(string: "https://huggingface.co/emrikol/birefnet-matting-onnx/resolve/main/birefnet-matting.onnx"),
            fileName: "birefnet-matting.onnx",
            approxMB: 897,
            inputSize: 1024, applySigmoid: true, usesCoreMLEP: false
        ),
    ]

    static func by(id: String) -> ModelSpec {
        all.first { $0.id == id } ?? all[0]
    }
}

/// Locates / downloads model files into Application Support, on demand.
enum ModelStore {
    static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("RemoveBackground/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Local path of an ORT model's `.onnx`, or nil for Core ML models.
    static func localURL(for spec: ModelSpec) -> URL? {
        guard let f = spec.fileName else { return nil }
        return dir.appendingPathComponent(f)
    }

    /// Where a Core ML model's compiled `.mlmodelc` is cached.
    static func compiledCoreMLURL(for spec: ModelSpec) -> URL {
        dir.appendingPathComponent("\(spec.id).mlmodelc")
    }

    static func isDownloaded(_ spec: ModelSpec) -> Bool {
        switch spec.engine {
        case .coreml:
            return FileManager.default.fileExists(atPath: compiledCoreMLURL(for: spec).path)
        case .ort:
            guard let u = localURL(for: spec) else { return false }
            return FileManager.default.fileExists(atPath: u.path)
        }
    }

    /// Ensures the ORT `.onnx` is present (downloading once), returns its path.
    static func ensure(_ spec: ModelSpec, progress: @escaping (Double) -> Void) async throws -> URL {
        guard let dest = localURL(for: spec), let url = spec.downloadURL else {
            throw NSError(domain: "ModelStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "no download for \(spec.id)"])
        }
        if FileManager.default.fileExists(atPath: dest.path) { return dest }
        let tmp = try await Downloader.shared.download(url, progress: progress)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        progress(1.0)
        return dest
    }

    /// Ensures the Core ML model is present: downloads the multi-file `.mlpackage`,
    /// compiles it to `.mlmodelc`, caches that, and returns it. The `.mlpackage` is
    /// removed after compiling (the `.mlmodelc` is self-contained).
    static func ensureCoreML(_ spec: ModelSpec, progress: @escaping (Double) -> Void) async throws -> URL {
        let compiled = compiledCoreMLURL(for: spec)
        if FileManager.default.fileExists(atPath: compiled.path) { return compiled }
        guard let base = spec.coremlBaseURL, !spec.coremlFiles.isEmpty else {
            throw NSError(domain: "ModelStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "no Core ML package for \(spec.id)"])
        }

        let pkg = dir.appendingPathComponent("\(spec.id).mlpackage", isDirectory: true)
        try? FileManager.default.removeItem(at: pkg)
        let n = spec.coremlFiles.count
        for (i, rel) in spec.coremlFiles.enumerated() {
            guard let fileURL = URL(string: base + "/" + rel) else {
                throw NSError(domain: "ModelStore", code: 3, userInfo: [NSLocalizedDescriptionKey: "bad URL for \(rel)"])
            }
            let dest = pkg.appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            let tmp = try await Downloader.shared.download(fileURL) { p in
                progress((Double(i) + p) / Double(n)) // weight.bin (last, biggest) dominates
            }
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
        }

        let tmpCompiled = try await MLModel.compileModel(at: pkg)
        try? FileManager.default.removeItem(at: compiled)
        try FileManager.default.moveItem(at: tmpCompiled, to: compiled)
        try? FileManager.default.removeItem(at: pkg) // keep only the compiled model
        progress(1.0)
        return compiled
    }
}

/// Downloads one file at a time with progress (handles multi-hundred-MB models).
/// The UI only ever fetches one model at a time, so a single in-flight download is
/// enough — no per-task bookkeeping. Thread-safety without a lock: the fields are set
/// before `resume()`, and URLSession delivers all callbacks serially on its own queue
/// (GCD provides the happens-before), so there's no concurrent access to guard.
final class Downloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = Downloader()
    private var progress: ((Double) -> Void)?
    private var continuation: CheckedContinuation<URL, Error>?
    private lazy var session: URLSession =
        .init(configuration: .default, delegate: self, delegateQueue: nil)

    func download(_ url: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            self.progress = progress
            self.continuation = cont
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_: URLSession, downloadTask _: URLSessionDownloadTask,
                    didWriteData _: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64)
    {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_: URLSession, downloadTask _: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Move out of the temp location synchronously (it's deleted when this returns).
        let staged = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tmp")
        let cont = continuation; continuation = nil; progress = nil
        do { try FileManager.default.moveItem(at: location, to: staged); cont?.resume(returning: staged) }
        catch { cont?.resume(throwing: error) }
    }

    func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let cont = continuation; continuation = nil; progress = nil
        cont?.resume(throwing: error)
    }
}
