//
//  LanguageTone.swift
//  ghostwriter
//

import Foundation

enum LanguageTone: String, CaseIterable, Identifiable, Codable {
    case formal = "formal"
    case informal = "informal"
    case concise = "concise"
    case friendly = "friendly"
    case academic = "academic"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .formal: return AppStrings.localized("tone_formal")
        case .informal: return AppStrings.localized("tone_informal")
        case .concise: return AppStrings.localized("tone_concise")
        case .friendly: return AppStrings.localized("tone_friendly")
        case .academic: return AppStrings.localized("tone_academic")
        }
    }
    
    var promptDescription: String {
        switch self {
        case .formal:
            return "Professional, polite, grammatically precise, and suitable for business, work communication, or official settings."
        case .informal:
            return "Casual, colloquial, conversational, natural, and suitable for chatting with friends or casual messaging."
        case .concise:
            return "Extremely concise, clear, direct, and to the point. Eliminate any fluff, filler words, or unnecessary elaboration."
        case .friendly:
            return "Warm, enthusiastic, approachable, polite, and encouraging."
        case .academic:
            return "Academic, rigorous, analytical, and utilizing precise domain-specific vocabulary."
        }
    }
}
