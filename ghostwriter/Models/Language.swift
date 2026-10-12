//
//  Language.swift
//  ghostwriter
//

import Foundation

enum Language: String, CaseIterable, Identifiable, Codable {
    case auto = "auto"
    case pt_BR = "pt-BR"
    case pt_PT = "pt-PT"
    case en_US = "en-US"
    case en_GB = "en-GB"
    case es_ES = "es-ES"
    case es_LA = "es-419"
    case fr_FR = "fr-FR"
    case fr_CA = "fr-CA"
    case de_DE = "de-DE"
    case it_IT = "it-IT"
    case ja_JP = "ja-JP"
    case zh_CN = "zh-CN"
    case zh_TW = "zh-TW"
    case ru_RU = "ru-RU"
    case ko_KR = "ko-KR"
    case nl_NL = "nl-NL"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .auto: return AppStrings.localized("lang_auto")
        case .pt_BR: return AppStrings.localized("lang_pt_br")
        case .pt_PT: return AppStrings.localized("lang_pt_pt")
        case .en_US: return AppStrings.localized("lang_en_us")
        case .en_GB: return AppStrings.localized("lang_en_gb")
        case .es_ES: return AppStrings.localized("lang_es_es")
        case .es_LA: return AppStrings.localized("lang_es_la")
        case .fr_FR: return AppStrings.localized("lang_fr_fr")
        case .fr_CA: return AppStrings.localized("lang_fr_ca")
        case .de_DE: return AppStrings.localized("lang_de_de")
        case .it_IT: return AppStrings.localized("lang_it_it")
        case .ja_JP: return AppStrings.localized("lang_ja_jp")
        case .zh_CN: return AppStrings.localized("lang_zh_cn")
        case .zh_TW: return AppStrings.localized("lang_zh_tw")
        case .ru_RU: return AppStrings.localized("lang_ru_ru")
        case .ko_KR: return AppStrings.localized("lang_ko_ko")
        case .nl_NL: return AppStrings.localized("lang_nl_nl")
        }
    }
    
    var regionPromptInstruction: String {
        switch self {
        case .auto:
            return "Automatically detect the input language."
        case .pt_BR:
            return "Brazilian Portuguese (pt-BR). Use Brazilian grammar, spelling, natural idioms, and vocabulary."
        case .pt_PT:
            return "European Portuguese (pt-PT). Use Portugal grammar, spelling, enclitic pronouns, and European vocabulary (e.g., 'comboio', 'ecrã', 'utilizador')."
        case .en_US:
            return "American English (en-US). Use American spelling (e.g., 'color', 'organize') and idioms."
        case .en_GB:
            return "British English (en-GB). Use British spelling (e.g., 'colour', 'organise') and idioms."
        case .es_ES:
            return "European Spanish (es-ES). Use Iberian vocabulary and grammatical conventions."
        case .es_LA:
            return "Latin American Spanish (es-419). Use natural Latin American phrasing and 'ustedes'."
        case .fr_FR:
            return "Metropolitan French (fr-FR). Use European French spelling and conventions."
        case .fr_CA:
            return "Canadian French (fr-CA). Use Québécois conventions and natural expressions."
        case .de_DE:
            return "Standard German (de-DE)."
        case .it_IT:
            return "Standard Italian (it-IT)."
        case .ja_JP:
            return "Natural Japanese (ja-JP)."
        case .zh_CN:
            return "Simplified Chinese (zh-CN)."
        case .zh_TW:
            return "Traditional Chinese (zh-TW)."
        case .ru_RU:
            return "Standard Russian (ru-RU)."
        case .ko_KR:
            return "Standard Korean (ko-KR)."
        case .nl_NL:
            return "Standard Dutch (nl-NL)."
        }
    }
    
    static var targetLanguages: [Language] {
        allCases.filter { $0 != .auto }
    }
    
    static var sourceLanguages: [Language] {
        allCases
    }
}
