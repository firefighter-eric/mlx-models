//
//  AudioRecorder.swift
//  mlx-models
//
//  Created by Codex on 3/22/26.
//

import AVFoundation
import Foundation

final class AudioRecorder: NSObject {
    private var recorder: AVAudioRecorder?
    private var outputURL: URL?

    func startRecording() async throws -> URL {
        try await requestMicrophoneAccessIfNeeded()

        let targetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]

        let recorder = try AVAudioRecorder(url: targetURL, settings: settings)
        recorder.prepareToRecord()

        guard recorder.record() else {
            throw AudioRecorderError.couldNotStart
        }

        self.recorder = recorder
        outputURL = targetURL
        return targetURL
    }

    func stopRecording() throws -> URL {
        recorder?.stop()
        recorder = nil

        guard let outputURL else {
            throw AudioRecorderError.noRecordingInProgress
        }

        self.outputURL = nil
        return outputURL
    }

    private func requestMicrophoneAccessIfNeeded() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                throw AudioRecorderError.permissionDenied
            }
        case .denied, .restricted:
            throw AudioRecorderError.permissionDenied
        @unknown default:
            throw AudioRecorderError.permissionDenied
        }
    }
}

enum AudioRecorderError: LocalizedError {
    case permissionDenied
    case couldNotStart
    case noRecordingInProgress

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "没有麦克风权限。"
        case .couldNotStart:
            return "录音器未能启动。"
        case .noRecordingInProgress:
            return "当前没有正在进行的录音。"
        }
    }
}
