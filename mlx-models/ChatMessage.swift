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
    let createdAt = Date()
}
