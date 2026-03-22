//
//  ModelLocator.swift
//  mlx-models
//
//  Created by Codex on 3/22/26.
//

import Foundation

enum ModelLocator {
    struct ModelInfo {
        let isAvailable: Bool
        let message: String
        let contents: [String]
    }

    nonisolated static func bundledModelDirectory() throws -> URL {
        guard let resourceURL = Bundle.main.resourceURL else {
            throw ModelError.missingResourcesDirectory
        }

        let modelURL = resourceURL.appendingPathComponent("Model", isDirectory: true)
        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(atPath: modelURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ModelError.missingBundledModel(modelURL.path)
        }

        return modelURL
    }

    nonisolated static func describeBundledModel() -> ModelInfo {
        do {
            let modelURL = try bundledModelDirectory()
            let contents = try FileManager.default.contentsOfDirectory(
                at: modelURL,
                includingPropertiesForKeys: nil
            )
            .map(\.lastPathComponent)
            .sorted()

            return ModelInfo(
                isAvailable: true,
                message: modelURL.path,
                contents: contents
            )
        } catch {
            return ModelInfo(
                isAvailable: false,
                message: error.localizedDescription,
                contents: []
            )
        }
    }

    nonisolated static func modelRepository() -> String {
        if let repository = Bundle.main.object(forInfoDictionaryKey: "ASRModelRepository") as? String,
           !repository.isEmpty {
            return repository
        }

        return "mlx-community/Qwen3-ASR-0.6B-4bit"
    }
}

private enum ModelError: LocalizedError {
    case missingResourcesDirectory
    case missingBundledModel(String)

    var errorDescription: String? {
        switch self {
        case .missingResourcesDirectory:
            return "Bundle resources directory is unavailable."
        case let .missingBundledModel(path):
            return "Bundled model directory not found at \(path)."
        }
    }
}
