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
        let candidates = recordingCandidates()

        for candidate in candidates {
            do {
                let recorder = try AVAudioRecorder(url: candidate.url, settings: candidate.settings)
                recorder.isMeteringEnabled = true
                recorder.prepareToRecord()

                guard recorder.record() else {
                    continue
                }

                self.recorder = recorder
                outputURL = candidate.url
                return candidate.url
            } catch {
                continue
            }
        }

        throw AudioRecorderError.couldNotStart
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

    func normalizedPowerLevel() -> Double {
        guard let recorder else { return 0 }

        recorder.updateMeters()
        let averagePower = recorder.averagePower(forChannel: 0)
        let minDb: Float = -50

        if averagePower <= minDb {
            return 0
        }

        if averagePower >= 0 {
            return 1
        }

        return Double((averagePower - minDb) / abs(minDb))
    }

    func averagePowerLevel() -> Float {
        guard let recorder else { return -160 }
        recorder.updateMeters()
        return recorder.averagePower(forChannel: 0)
    }

    func peakPowerLevel() -> Float {
        guard let recorder else { return -160 }
        recorder.updateMeters()
        return recorder.peakPower(forChannel: 0)
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

    private func recordingCandidates() -> [(url: URL, settings: [String: Any])] {
        let temp = FileManager.default.temporaryDirectory
        let id = UUID().uuidString

        return [
            (
                url: temp
                    .appendingPathComponent("recording-\(id)")
                    .appendingPathExtension("m4a"),
                settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 44_100,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                    AVEncoderBitRateKey: 96_000
                ]
            ),
            (
                url: temp
                    .appendingPathComponent("recording-\(id)")
                    .appendingPathExtension("caf"),
                settings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 44_100,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsFloatKey: false
                ]
            )
        ]
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
