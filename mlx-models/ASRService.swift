//
//  ASRService.swift
//  mlx-models
//
//  Created by Codex on 3/22/26.
//

import AVFoundation
import Foundation
import HuggingFace
import MLXAudioCore
import MLXAudioSTT

actor ASRService {
    struct TranscriptionResult {
        let text: String
        let language: String?
        let durationSeconds: Double?
        let elapsedSeconds: Double?
    }

    private let repository: String
    private let cache: HubCache
    private var model: Qwen3ASRModel?

    init() {
        repository = ModelLocator.modelRepository()
        let cacheURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "mlx-models", isDirectory: true)
            .appendingPathComponent("MLXAudioCache", isDirectory: true)
        cache = HubCache(cacheDirectory: cacheURL)
    }

    func prepareModel() async throws -> String {
        let bundledModelURL = try ModelLocator.bundledModelDirectory()
        try FileManager.default.createDirectory(at: cache.cacheDirectory, withIntermediateDirectories: true)
        try seedBundledModelIfNeeded(from: bundledModelURL)

        if model == nil {
            model = try await Qwen3ASRModel.fromPretrained(repository, cache: cache)
        }

        return bundledModelURL.path
    }

    func transcribeAudio(at url: URL) async throws -> TranscriptionResult {
        let preparedURL = try await AudioPreprocessor.prepareForTranscription(inputURL: url)
        defer {
            if preparedURL != url {
                try? FileManager.default.removeItem(at: preparedURL)
            }
        }

        let model = try await loadedModel()
        let startTime = Date()
        let (_, audio) = try loadAudioArray(from: preparedURL, sampleRate: 16_000)
        let output = model.generate(audio: audio)
        let elapsedSeconds = Date().timeIntervalSince(startTime)
        let trimmedText = output.text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedText.isEmpty else {
            throw ASRServiceError.emptyTranscript
        }

        return TranscriptionResult(
            text: trimmedText,
            language: output.language,
            durationSeconds: try? audioDuration(at: preparedURL),
            elapsedSeconds: elapsedSeconds
        )
    }

    private func loadedModel() async throws -> Qwen3ASRModel {
        if let model {
            return model
        }

        _ = try await prepareModel()

        guard let model else {
            throw ASRServiceError.modelLoadFailed("模型初始化后仍不可用。")
        }

        return model
    }

    private func seedBundledModelIfNeeded(from bundledModelURL: URL) throws {
        let targetURL = cache.cacheDirectory
            .appendingPathComponent("mlx-audio", isDirectory: true)
            .appendingPathComponent(repository.replacingOccurrences(of: "/", with: "_"), isDirectory: true)

        if isUsableModelDirectory(targetURL) {
            return
        }

        if FileManager.default.fileExists(atPath: targetURL.path) {
            try FileManager.default.removeItem(at: targetURL)
        }

        try FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: bundledModelURL, to: targetURL)
    }

    private func isUsableModelDirectory(_ url: URL) -> Bool {
        let configURL = url.appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return false
        }

        let files = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        return files.contains { $0.pathExtension == "safetensors" }
    }

    private func audioDuration(at url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        return Double(file.length) / file.processingFormat.sampleRate
    }
}

private enum AudioPreprocessor {
    static func prepareForTranscription(inputURL: URL) async throws -> URL {
        guard isVideoURL(inputURL) else {
            return inputURL
        }

        return try await exportAudioTrack(from: inputURL)
    }

    private static func isVideoURL(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "mov", "mp4", "m4v":
            return true
        default:
            return false
        }
    }

    private static func exportAudioTrack(from url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw ASRServiceError.audioPreparationFailed("无法从视频中导出音频轨道。")
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("extracted-\(UUID().uuidString)")
            .appendingPathExtension("m4a")

        do {
            try await exportSession.export(to: outputURL, as: .m4a)
            return outputURL
        } catch {
            throw ASRServiceError.audioPreparationFailed(error.localizedDescription)
        }
    }
}

enum ASRServiceError: LocalizedError {
    case modelLoadFailed(String)
    case emptyTranscript
    case audioPreparationFailed(String)

    var errorDescription: String? {
        switch self {
        case let .modelLoadFailed(message):
            return "模型加载失败：\(message)"
        case .emptyTranscript:
            return "ASR 失败：转写结果为空。"
        case let .audioPreparationFailed(message):
            return "音频预处理失败：\(message)"
        }
    }
}
