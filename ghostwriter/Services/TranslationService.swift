//
//  TranslationService.swift
//  ghostwriter
//

import Foundation

enum TranslationError: LocalizedError {
    case cliNotFound(String)
    case executionFailed(String)
    case emptyResponse
    case timedOut

    var errorDescription: String? {
        switch self {
        case .cliNotFound(let name):
            return AppStrings.Errors.cliNotFound(name: name)
        case .executionFailed(let reason):
            return AppStrings.Errors.cliExecutionFailed(reason: reason)
        case .emptyResponse:
            return AppStrings.Errors.emptyResponse
        case .timedOut:
            return AppStrings.Errors.timedOut
        }
    }
}

protocol TranslationService {
    func translate(
        text: String,
        sourceLanguage: Language,
        targetLanguage: Language,
        tone: LanguageTone,
        context: String?,
        promptMode: Bool,
        timeout: TimeInterval
    ) async throws -> String
}
