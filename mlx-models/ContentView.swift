//
//  ContentView.swift
//  mlx-models
//
//  Created by Qifan Zhang on 3/22/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = ASRSessionViewModel()

    var body: some View {
        VStack(spacing: 0) {
            StatusHeader(viewModel: viewModel)
            Divider()
            MessageList(messages: viewModel.messages)
            Divider()
            ControlBar(viewModel: viewModel)
        }
        .background(Color.white)
        .fileImporter(
            isPresented: $viewModel.isFileImporterPresented,
            allowedContentTypes: [.audio, .movie, .mpeg4Movie],
            allowsMultipleSelection: false,
            onCompletion: viewModel.handleFileImportResult
        )
        .preferredColorScheme(.light)
        .frame(minWidth: 860, minHeight: 620)
    }
}

private struct StatusHeader: View {
    @ObservedObject var viewModel: ASRSessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ASR Chat")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.black)

            HStack(spacing: 12) {
                StatusChip(label: "模型", value: viewModel.modelStatusLabel, tint: viewModel.modelStatusTint)
                StatusChip(label: "来源", value: viewModel.inputSourceLabel, tint: Color.gray.opacity(0.18))
                StatusChip(label: "状态", value: viewModel.sessionStateLabel, tint: viewModel.sessionStateTint)
            }

            if let lastError = viewModel.lastError, !lastError.isEmpty {
                Text(lastError)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.65, green: 0.17, blue: 0.17))
                    .lineLimit(2)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
    }
}

private struct StatusChip: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(Color.secondary)
            Text(value)
                .foregroundStyle(Color.black)
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(tint)
        )
    }
}

private struct MessageList: View {
    let messages: [ChatMessage]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    if messages.isEmpty {
                        EmptyState()
                    } else {
                        ForEach(messages) { message in
                            MessageRow(message: message)
                                .id(message.id)
                        }
                    }
                }
                .padding(24)
            }
            .background(Color(red: 0.97, green: 0.97, blue: 0.97))
            .onChange(of: messages.count) { _, _ in
                guard let lastMessage = messages.last else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
        }
    }
}

private struct EmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("等待语音输入")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.black)

            Text("选择音频文件，或者直接开始录音。识别结果会作为 ASR 消息出现在这里。")
                .font(.system(size: 15))
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct MessageRow: View {
    let message: ChatMessage

    private var alignment: HorizontalAlignment {
        message.role == .user ? .trailing : .leading
    }

    private var bubbleColor: Color {
        switch message.role {
        case .system:
            return Color(red: 0.95, green: 0.95, blue: 0.95)
        case .user:
            return Color(red: 0.92, green: 0.95, blue: 1.0)
        case .asr:
            return .white
        }
    }

    private var title: String {
        switch message.role {
        case .system:
            return "System"
        case .user:
            return "Input"
        case .asr:
            return "ASR"
        }
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.secondary)

            Text(message.text)
                .font(.system(size: 15))
                .foregroundStyle(Color.black)
                .textSelection(.enabled)
                .frame(maxWidth: 540, alignment: .leading)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(bubbleColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.black.opacity(message.role == .system ? 0.04 : 0.08), lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

private struct ControlBar: View {
    @ObservedObject var viewModel: ASRSessionViewModel

    var body: some View {
        HStack(spacing: 12) {
            Button("选择音频文件") {
                viewModel.presentFileImporter()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(viewModel.isBusy)

            Button(viewModel.isRecording ? "停止录音" : "开始录音") {
                viewModel.toggleRecording()
            }
            .buttonStyle(SecondaryButtonStyle(isActive: viewModel.isRecording))
            .disabled(viewModel.isTranscribing)

            Spacer(minLength: 12)

            Button("清空会话") {
                viewModel.clearMessages()
            }
            .buttonStyle(ClearButtonStyle())
            .disabled(viewModel.messages.isEmpty)
        }
        .padding(20)
        .background(Color.white)
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(configuration.isPressed ? 0.8 : 0.92))
            )
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isActive ? Color.white : Color.black)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isActive ? Color(red: 0.88, green: 0.22, blue: 0.22) : Color(red: 0.94, green: 0.94, blue: 0.94))
                    .opacity(configuration.isPressed ? 0.78 : 1)
            )
    }
}

private struct ClearButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(configuration.isPressed ? 0.7 : 1))
                    )
            )
    }
}

#Preview {
    ContentView()
}
