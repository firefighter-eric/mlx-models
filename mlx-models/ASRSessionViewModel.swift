//
//  ASRSessionViewModel.swift
//  mlx-models
//
//  Created by Codex on 3/22/26.
//

import Combine
import AppKit
import AVFoundation
import Foundation
import SwiftUI

@MainActor
final class ASRSessionViewModel: NSObject, ObservableObject, NSSoundDelegate {
    @Published var messages: [ChatMessage] = []
    @Published var isFileImporterPresented = false
    @Published private(set) var sessionState: ASRSessionState = .loadingModel
    @Published private(set) var modelReady = false
    @Published private(set) var inputSource: ASRInputSource = .idle
    @Published private(set) var lastError: String?
    @Published private(set) var playingMessageID: UUID?
    @Published private(set) var recordingLevel: Double = 0
    @Published private(set) var recordingAveragePower: Float = -160
    @Published private(set) var recordingPeakPower: Float = -160
    @Published private(set) var recordingPeakHoldPower: Float = -160

    private let service: ASRService
    private let audioRecorder: AudioRecorder
    private var audioPlayer: NSSound?
    private var recordingMeterTask: Task<Void, Never>?

    init(
        service: ASRService = ASRService(),
        audioRecorder: AudioRecorder? = nil
    ) {
        self.service = service
        self.audioRecorder = audioRecorder ?? AudioRecorder()
        super.init()

        Task {
            await prepareModel()
        }
    }

    var isBusy: Bool {
        sessionState == .recording || sessionState == .transcribing || sessionState == .loadingModel
    }

    var isRecording: Bool {
        sessionState == .recording
    }

    var isTranscribing: Bool {
        sessionState == .transcribing
    }

    var modelStatusLabel: String {
        modelReady ? "已加载" : "未就绪"
    }

    var modelStatusTint: Color {
        modelReady ? Color(red: 0.90, green: 0.97, blue: 0.91) : Color.gray.opacity(0.18)
    }

    var inputSourceLabel: String {
        inputSource.label
    }

    var sessionStateLabel: String {
        switch sessionState {
        case .idle:
            return "空闲"
        case .loadingModel:
            return "加载模型"
        case .recording:
            return "录音中"
        case .transcribing:
            return "转写中"
        case .failed:
            return "失败"
        }
    }

    var sessionStateTint: Color {
        switch sessionState {
        case .idle:
            return Color.gray.opacity(0.18)
        case .loadingModel, .recording, .transcribing:
            return Color(red: 0.92, green: 0.95, blue: 1.0)
        case .failed:
            return Color(red: 1.0, green: 0.92, blue: 0.92)
        }
    }

    func presentFileImporter() {
        isFileImporterPresented = true
    }

    func clearMessages() {
        stopPlayback()
        messages.removeAll()
        lastError = nil
    }

    func toggleRecording() {
        Task {
            if isRecording {
                await stopRecordingAndTranscribe()
            } else {
                await startRecording()
            }
        }
    }

    func handleFileImportResult(_ result: Result<[URL], Error>) {
        Task {
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                await transcribeImportedFile(url)
            case let .failure(error):
                handleFailure("文件选择失败：\(error.localizedDescription)")
            }
        }
    }

    func togglePlayback(for message: ChatMessage) {
        guard message.allowsPlayback, let audioURL = message.audioURL else { return }

        if playingMessageID == message.id {
            stopPlayback()
            return
        }

        Task {
            await startPlayback(for: message, audioURL: audioURL)
        }
    }

    func isPlaying(_ message: ChatMessage) -> Bool {
        playingMessageID == message.id
    }

    private func startPlayback(for message: ChatMessage, audioURL: URL) async {
        do {
            stopPlayback()

            let attributes = try FileManager.default.attributesOfItem(atPath: audioURL.path)
            guard let fileSize = attributes[.size] as? NSNumber, fileSize.int64Value > 0 else {
                throw PlaybackError.emptyFile
            }

            let asset = AVURLAsset(url: audioURL)
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)

            guard let player = NSSound(contentsOf: audioURL, byReference: false) else {
                throw PlaybackError.unreadableFile
            }

            player.delegate = self
            player.volume = 1.0

            guard player.play() else {
                throw PlaybackError.couldNotStart
            }

            audioPlayer = player
            playingMessageID = message.id
            appendSystemMessage(
                String(
                    format: "开始播放：%@（%.2f 秒）",
                    audioURL.lastPathComponent,
                    durationSeconds.isFinite ? durationSeconds : 0
                )
            )
        } catch {
            stopPlayback()
            handleFailure("播放音频失败：\(error.localizedDescription)")
        }
    }

    private func prepareModel() async {
        sessionState = .loadingModel

        do {
            let modelPath = try await service.prepareModel()
            modelReady = true
            sessionState = .idle
            appendSystemMessage("模型已就绪：\(modelPath)")
        } catch {
            modelReady = false
            handleFailure(error.localizedDescription)
        }
    }

    private func startRecording() async {
        guard modelReady else {
            handleFailure("模型未就绪，无法开始录音。")
            return
        }

        do {
            sessionState = .recording
            inputSource = .microphone
            let recordingURL = try await audioRecorder.startRecording()
            startRecordingMeterUpdates()
            appendUserMessage("开始录音：\(recordingURL.lastPathComponent)")
        } catch {
            handleFailure("启动录音失败：\(error.localizedDescription)")
        }
    }

    private func stopRecordingAndTranscribe() async {
        do {
            stopRecordingMeterUpdates()
            let recordedURL = try audioRecorder.stopRecording()
            let localAudioURL = try createLocalPlaybackCopy(from: recordedURL)

            appendUserMessage(
                "录音输入：\(localAudioURL.lastPathComponent)",
                audioURL: localAudioURL,
                allowsPlayback: true
            )
            appendUserMessage("停止录音，准备转写。")
            await transcribeAudio(at: localAudioURL, source: .microphone)
        } catch {
            stopRecordingMeterUpdates()
            handleFailure("停止录音失败：\(error.localizedDescription)")
        }
    }

    private func transcribeImportedFile(_ url: URL) async {
        guard modelReady else {
            handleFailure("模型未就绪，无法转写文件。")
            return
        }

        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let localAudioURL: URL

        do {
            localAudioURL = try createLocalPlaybackCopy(from: url)
        } catch {
            handleFailure("导入音频失败：\(error.localizedDescription)")
            return
        }

        appendUserMessage(
            "文件输入：\(url.lastPathComponent)",
            audioURL: localAudioURL,
            allowsPlayback: true
        )
        await transcribeAudio(at: localAudioURL, source: .file)
    }

    private func transcribeAudio(at url: URL, source: ASRInputSource) async {
        sessionState = .transcribing
        inputSource = source
        lastError = nil

        do {
            let result = try await service.transcribeAudio(at: url)
            appendASRMessage(result.text)

            if let language = result.language, !language.isEmpty {
                appendSystemMessage("识别语言：\(language)")
            }

            if let elapsed = result.elapsedSeconds {
                appendSystemMessage(String(format: "转写完成，用时 %.2f 秒。", elapsed))
            }

            sessionState = .idle
            inputSource = .idle
        } catch {
            handleFailure(error.localizedDescription)
        }
    }

    private func appendSystemMessage(_ text: String) {
        messages.append(ChatMessage(role: .system, text: text))
    }

    private func appendUserMessage(
        _ text: String,
        audioURL: URL? = nil,
        allowsPlayback: Bool = false
    ) {
        messages.append(
            ChatMessage(
                role: .user,
                text: text,
                audioURL: audioURL,
                allowsPlayback: allowsPlayback
            )
        )
    }

    private func appendASRMessage(_ text: String) {
        messages.append(ChatMessage(role: .asr, text: text))
    }

    private func createLocalPlaybackCopy(from sourceURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let destinationURL = fileManager.temporaryDirectory
            .appendingPathComponent("imported-\(UUID().uuidString)")
            .appendingPathExtension(sourceURL.pathExtension)

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        playingMessageID = nil
    }

    private func startRecordingMeterUpdates() {
        stopRecordingMeterUpdates()

        recordingMeterTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                self.recordingLevel = self.audioRecorder.normalizedPowerLevel()
                self.recordingAveragePower = self.audioRecorder.averagePowerLevel()
                self.recordingPeakPower = self.audioRecorder.peakPowerLevel()
                self.recordingPeakHoldPower = max(self.recordingPeakHoldPower, self.recordingPeakPower)
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }

    private func stopRecordingMeterUpdates() {
        recordingMeterTask?.cancel()
        recordingMeterTask = nil
        recordingLevel = 0
        recordingAveragePower = -160
        recordingPeakPower = -160
        recordingPeakHoldPower = -160
    }

    private func handleFailure(_ message: String) {
        stopRecordingMeterUpdates()
        lastError = message
        sessionState = .failed(message)
        inputSource = .idle
        appendSystemMessage(message)
    }

    func sound(_ sound: NSSound, didFinishPlaying successfully: Bool) {
        stopPlayback()

        if !successfully {
            handleFailure("播放音频失败：播放过程中断。")
        }
    }
}

private enum PlaybackError: LocalizedError {
    case couldNotStart
    case emptyFile
    case unreadableFile

    var errorDescription: String? {
        switch self {
        case .couldNotStart:
            return "播放器未能启动。"
        case .emptyFile:
            return "音频文件为空。"
        case .unreadableFile:
            return "音频文件无法读取。"
        }
    }
}

enum ASRSessionState: Equatable {
    case idle
    case loadingModel
    case recording
    case transcribing
    case failed(String)
}

enum ASRInputSource {
    case idle
    case file
    case microphone

    var label: String {
        switch self {
        case .idle:
            return "未选择"
        case .file:
            return "音频文件"
        case .microphone:
            return "麦克风"
        }
    }
}
