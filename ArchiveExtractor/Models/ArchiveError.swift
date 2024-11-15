//
//  ArchiveError.swift
//  ArchiveExtractor
//
//  Created by Ivan Apostolovski on 14.11.24.
//

import Foundation

enum ArchiveErroraaaa: LocalizedError {
    case toolNotFound(String)
    case extractionFailed(String)
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case .toolNotFound(let tool):
            return "Required tool not found: \(tool)"
        case .extractionFailed(let message):
            return "Extraction failed: \(message)"
        case .unsupportedFormat(let format):
            return "Unsupported archive format: \(format)"
        }
    }
}
