//
//  ASRSessionViewModel.swift
//  mlx-models
//
//  Created by Codex on 3/22/26.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class ASRSessionViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isFileImporterPresented = false
    @Published private(set) var sessionState: ASRSessionState = .loadingModel
    @Published private(set) var modelReady = false
    @Published private(set) var inputSource: ASRInputSource = .idle
    @Published private(set) var lastError: String?

    private let service: ASRService
    private let audioRecorder: AudioRecorder

    init(
        service: ASRService = ASRService(),
        audioRecorder: AudioRecorder? = nil
    ) {
        self.service = service
        self.audioRecorder = audioRecorder ?? AudioRecorder()

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
            appendUserMessage("开始录音：\(recordingURL.lastPathComponent)")
        } catch {
            handleFailure("启动录音失败：\(error.localizedDescription)")
        }
    }

    private func stopRecordingAndTranscribe() async {
        do {
            let recordedURL = try audioRecorder.stopRecording()
            appendUserMessage("停止录音，准备转写。")
            await transcribeAudio(at: recordedURL, source: .microphone)
        } catch {
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

        appendUserMessage("文件输入：\(url.lastPathComponent)")
        await transcribeAudio(at: url, source: .file)
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

    private func appendUserMessage(_ text: String) {
        messages.append(ChatMessage(role: .user, text: text))
    }

    private func appendASRMessage(_ text: String) {
        messages.append(ChatMessage(role: .asr, text: text))
    }

    private func handleFailure(_ message: String) {
        lastError = message
        sessionState = .failed(message)
        inputSource = .idle
        appendSystemMessage(message)
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
