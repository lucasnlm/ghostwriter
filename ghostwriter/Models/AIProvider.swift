//
//  AIProvider.swift
//  ghostwriter
//

import Foundation

enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case agy = "agy"
    case claude = "claude"
    case opencode = "opencode"
    case custom = "custom"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .agy: return AppStrings.localized("provider_agy")
        case .claude: return AppStrings.localized("provider_claude")
        case .opencode: return AppStrings.localized("provider_opencode")
        case .custom: return AppStrings.localized("provider_custom")
        }
    }
    
    var defaultBinaryName: String {
        switch self {
        case .agy: return "agy"
        case .claude: return "claude"
        case .opencode: return "opencode"
        case .custom: return ""
        }
    }
    
    var defaultArguments: [String] {
        switch self {
        case .agy:
            return ["-p", "{prompt}"]
        case .claude:
            return ["-p", "{prompt}"]
        case .opencode:
            return ["run", "{prompt}"]
        case .custom:
            return ["{prompt}"]
        }
    }
}
