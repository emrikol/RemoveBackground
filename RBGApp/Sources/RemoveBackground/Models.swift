// SPDX-FileCopyrightText: 2026 emrikol
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import CoreML
import CryptoKit
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

    /// Expected SHA-256 of the primary downloaded file — the `.onnx` for ORT models, or the
    /// Core ML package's `weight.bin`. Verified after download; nil skips the check. Paired
    /// with the pinned commit SHA in the URLs, so the model content is both immutable and verified.
    let sha256: String?

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
            // Pinned to an immutable commit SHA so a re-pointed `main` can't swap the model.
            coremlBaseURL: "https://huggingface.co/VincentGOURBIN/RMBG-2-CoreML/resolve/0da071b52c402b293c8b13af9148bac21b4a8456/RMBG-2-native.mlpackage",
            coremlFiles: [
                "Manifest.json",
                "Data/com.apple.CoreML/model.mlmodel",
                "Data/com.apple.CoreML/weights/weight.bin",
            ],
            coremlOutputName: "output_3",
            downloadURL: nil, fileName: nil,
            approxMB: 461,
            inputSize: 1024, applySigmoid: false, usesCoreMLEP: true,
            sha256: "2efd4c12d4a106d9e1b02703d7848cb1d6fd4c2ffb5cf2631065bf4e0271c823"
        ),
        ModelSpec(
            id: "birefnet",
            name: "BiRefNet (full) — maximum quality",
            blurb: "The original BiRefNet at full size — the sharpest edges and hair.",
            license: "MIT",
            engine: .ort,
            coremlBaseURL: nil, coremlFiles: [], coremlOutputName: nil,
            downloadURL: URL(string: "https://huggingface.co/onnx-community/BiRefNet-ONNX/resolve/534d3c82d3bb8b2f0867db6dfbc3a525b8e42f67/onnx/model_fp16.onnx"),
            fileName: "birefnet_fp16.onnx",
            approxMB: 467,
            inputSize: 1024, applySigmoid: true, usesCoreMLEP: true,
            sha256: "3654c741eb80bd926ada8fed1713b506ccf8d30eb1f6487e87eb9f234f33df09"
        ),
        ModelSpec(
            id: "birefnet_lite",
            name: "BiRefNet-lite — fast",
            blurb: "Lighter and quicker. Still very good for everyday cutouts.",
            license: "MIT",
            engine: .ort,
            coremlBaseURL: nil, coremlFiles: [], coremlOutputName: nil,
            downloadURL: URL(string: "https://huggingface.co/onnx-community/BiRefNet_lite-ONNX/resolve/de15b22ba131738a16dff04aab8bdf8dc32e3ac1/onnx/model_fp16.onnx"),
            fileName: "birefnet_lite_fp16.onnx",
            approxMB: 109,
            inputSize: 1024, applySigmoid: true, usesCoreMLEP: true,
            sha256: "d39b897ceb16ae654c1731f3dba0cf9b368d9cae74b5a57459b455cc8bfec402"
        ),
        ModelSpec(
            id: "birefnet_portrait",
            name: "BiRefNet-portrait — best for people / hair",
            blurb: "Tuned for people — the finest hair and edge detail on portraits.",
            license: "MIT",
            engine: .ort,
            coremlBaseURL: nil, coremlFiles: [], coremlOutputName: nil,
            downloadURL: URL(string: "https://huggingface.co/onnx-community/BiRefNet-portrait-ONNX/resolve/dd7167f6a8b54ff7efc29a4c988938d79866464f/onnx/model_fp16.onnx"),
            fileName: "birefnet_portrait_fp16.onnx",
            approxMB: 467,
            inputSize: 1024, applySigmoid: true, usesCoreMLEP: true,
            sha256: "4c05930c0b6f1418d02eb1de81c46fe37638ba54f5a93adeb5c674521db10110"
        ),
        ModelSpec(
            id: "birefnet_matting",
            name: "BiRefNet-matting — soft alpha (finest edges)",
            blurb: "True alpha matting: feathery hair, fur, and semi-transparency. The slowest to run.",
            license: "MIT",
            engine: .ort,
            coremlBaseURL: nil, coremlFiles: [], coremlOutputName: nil,
            downloadURL: URL(string: "https://huggingface.co/emrikol/birefnet-matting-onnx/resolve/0d58d809b3a360b44c556223d2f5812aeace9ba3/birefnet-matting.onnx"),
            fileName: "birefnet-matting.onnx",
            approxMB: 897,
            inputSize: 1024, applySigmoid: true, usesCoreMLEP: false,
            sha256: "f0843e38f6a4e88efc8c5fad4178ad7ed6c818346ce12f82e7b579324fe7e0c5"
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

    /// Verifies a freshly downloaded file against its pinned SHA-256, deleting it and throwing
    /// on mismatch. No-op when `expected` is nil. The file is memory-mapped so a multi-hundred-MB
    /// model is hashed without being loaded into RAM.
    static func verify(_ url: URL, expected: String?, name: String) throws {
        guard let expected else { return }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            throw NSError(domain: "ModelStore", code: 11,
                          userInfo: [NSLocalizedDescriptionKey: "Couldn’t read \(name) to verify it."])
        }
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == expected.lowercased() else {
            try? FileManager.default.removeItem(at: url)
            throw NSError(domain: "ModelStore", code: 12, userInfo: [NSLocalizedDescriptionKey:
                "Integrity check failed for \(name) — its checksum didn’t match the pinned value, so the download was discarded."])
        }
    }

    /// Ensures the ORT `.onnx` is present (downloading + verifying once), returns its path.
    static func ensure(_ spec: ModelSpec, progress: @escaping (Double) -> Void) async throws -> URL {
        guard let dest = localURL(for: spec), let url = spec.downloadURL else {
            throw NSError(domain: "ModelStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "no download for \(spec.id)"])
        }
        if FileManager.default.fileExists(atPath: dest.path) { return dest }
        let tmp = try await Downloader.shared.download(url, progress: progress)
        try verify(tmp, expected: spec.sha256, name: spec.fileName ?? spec.id)
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

        // Verify the package's bulk weights against the pinned hash before compiling it.
        try verify(pkg.appendingPathComponent("Data/com.apple.CoreML/weights/weight.bin"),
                   expected: spec.sha256, name: "\(spec.id) weights")
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
