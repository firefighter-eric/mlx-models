//
//  ChatMessage.swift
//  mlx-models
//
//  Created by Codex on 3/22/26.
//

import Foundation

enum ChatMessageRole {
    case system
    case user
    case asr
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ChatMessageRole
    let text: String
    let audioURL: URL?
    let allowsPlayback: Bool
    let createdAt = Date()

    init(
        role: ChatMessageRole,
        text: String,
        audioURL: URL? = nil,
        allowsPlayback: Bool = false
    ) {
        self.role = role
        self.text = text
        self.audioURL = audioURL
        self.allowsPlayback = allowsPlayback
    }
}
