//
//  AppError.swift
//  Me2Tune
//
//  统一错误类型定义
//

import Foundation

enum AppError: LocalizedError {
    case audioLoadFailed(URL)
    case audioPlayFailed(String)
    case metadataExtractionFailed(URL)
    case persistenceFailed(String)
    case invalidFileFormat(URL)
    case folderAccessDenied(URL)
    case swiftDataFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .audioLoadFailed(let url):
            return "Failed to load audio file: \(url.lastPathComponent)"
        case .audioPlayFailed(let reason):
            return "Playback failed: \(reason)"
        case .metadataExtractionFailed(let url):
            return "Failed to read metadata from: \(url.lastPathComponent)"
        case .persistenceFailed(let operation):
            return "Failed to \(operation) data"
        case .invalidFileFormat(let url):
            return "Unsupported file format: \(url.pathExtension)"
        case .folderAccessDenied(let url):
            return "Cannot access folder: \(url.lastPathComponent)"
        case .swiftDataFailed(let error):
            return "Data operation failed: \(error.localizedDescription)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .audioLoadFailed, .metadataExtractionFailed:
            return "Check if the file exists and is not corrupted"
        case .audioPlayFailed:
            return "Try playing a different file"
        case .persistenceFailed:
            return "Check disk space and permissions"
        case .invalidFileFormat:
            return "Use supported audio formats (MP3, AAC, FLAC, etc.)"
        case .folderAccessDenied:
            return "Grant file access permission in System Settings"
        case .swiftDataFailed:
            return "Check disk space and permissions"
        }
    }
}
