//
//  AppSettings.swift
//  ghostwriter
//

import Foundation
import Observation

@Observable
final class AppSettings {
    static let shared = AppSettings()
    
    @ObservationIgnored
    private let defaults = UserDefaults.standard
    
    @ObservationIgnored
    private var isSyncing: Bool = false
    
    var shortcut: String {
        didSet {
            defaults.set(shortcut, forKey: "shortcut")
            if !isSyncing {
                PreferencesManager.shared.updateKey(key: "shortcut", value: shortcut)
            }
            HotKeyManager.shared.updateShortcut(shortcut)
        }
    }
    
    var selectedProvider: AIProvider {
        didSet {
            defaults.set(selectedProvider.rawValue, forKey: "selectedProvider")
            if !isSyncing {
                PreferencesManager.shared.updateKey(key: "provider", value: selectedProvider.rawValue)
            }
        }
    }
    
    var sourceLanguage: Language {
        didSet {
            defaults.set(sourceLanguage.rawValue, forKey: "sourceLanguage")
            if !isSyncing {
                PreferencesManager.shared.updateKey(key: "source_language", value: sourceLanguage.rawValue)
            }
        }
    }
    
    var targetLanguage: Language {
        didSet {
            defaults.set(targetLanguage.rawValue, forKey: "targetLanguage")
            if !isSyncing {
                PreferencesManager.shared.updateKey(key: "target_language", value: targetLanguage.rawValue)
            }
        }
    }
    
    var selectedTone: LanguageTone {
        didSet {
            defaults.set(selectedTone.rawValue, forKey: "selectedTone")
            if !isSyncing {
                PreferencesManager.shared.updateKey(key: "tone", value: selectedTone.rawValue)
            }
        }
    }
    
    // Custom binary paths (leave empty to auto-detect from PATH)
    var agyPath: String {
        didSet {
            defaults.set(agyPath, forKey: "agyPath")
            if !isSyncing && !agyPath.isEmpty {
                PreferencesManager.shared.updateKey(key: "agy_path", value: agyPath)
            }
        }
    }
    
    var claudePath: String {
        didSet {
            defaults.set(claudePath, forKey: "claudePath")
            if !isSyncing && !claudePath.isEmpty {
                PreferencesManager.shared.updateKey(key: "claude_path", value: claudePath)
            }
        }
    }
    
    var opencodePath: String {
        didSet {
            defaults.set(opencodePath, forKey: "opencodePath")
            if !isSyncing && !opencodePath.isEmpty {
                PreferencesManager.shared.updateKey(key: "opencode_path", value: opencodePath)
            }
        }
    }
    
    // Custom CLI command
    var customBinaryPath: String {
        didSet {
            defaults.set(customBinaryPath, forKey: "customBinaryPath")
            if !isSyncing && !customBinaryPath.isEmpty {
                PreferencesManager.shared.updateKey(key: "custom_binary_path", value: customBinaryPath)
            }
        }
    }
    
    var customArguments: String {
        didSet {
            defaults.set(customArguments, forKey: "customArguments")
            if !isSyncing && !customArguments.isEmpty {
                PreferencesManager.shared.updateKey(key: "custom_arguments", value: customArguments)
            }
        }
    }
    
    // General
    var autoPaste: Bool {
        didSet {
            defaults.set(autoPaste, forKey: "autoPaste")
            if !isSyncing {
                PreferencesManager.shared.updateKey(key: "auto_paste", value: autoPaste ? "true" : "false", isString: false)
            }
        }
    }

    var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: "launchAtLogin")
            if !isSyncing {
                PreferencesManager.shared.updateKey(key: "launch_at_login", value: launchAtLogin ? "true" : "false", isString: false)
            }
            LaunchAtLoginManager.shared.setEnabled(launchAtLogin)
        }
    }

    /// User-overridden binary path for a provider, trimmed; empty means auto-detect.
    func configuredBinaryPath(for provider: AIProvider) -> String {
        switch provider {
        case .agy: return agyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        case .claude: return claudePath.trimmingCharacters(in: .whitespacesAndNewlines)
        case .opencode: return opencodePath.trimmingCharacters(in: .whitespacesAndNewlines)
        case .custom: return customBinaryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    
    init() {
        self.shortcut = defaults.string(forKey: "shortcut") ?? "ctrl+cmd+g"
        
        let providerRaw = defaults.string(forKey: "selectedProvider") ?? AIProvider.agy.rawValue
        self.selectedProvider = AIProvider(rawValue: providerRaw) ?? .agy
        
        let srcLangRaw = defaults.string(forKey: "sourceLanguage") ?? Language.pt_BR.rawValue
        self.sourceLanguage = Language(rawValue: srcLangRaw) ?? .pt_BR
        
        let targetLangRaw = defaults.string(forKey: "targetLanguage") ?? Language.en_US.rawValue
        self.targetLanguage = Language(rawValue: targetLangRaw) ?? .en_US
        
        let toneRaw = defaults.string(forKey: "selectedTone") ?? LanguageTone.formal.rawValue
        self.selectedTone = LanguageTone(rawValue: toneRaw) ?? .formal
        
        self.agyPath = defaults.string(forKey: "agyPath") ?? ""
        self.claudePath = defaults.string(forKey: "claudePath") ?? ""
        self.opencodePath = defaults.string(forKey: "opencodePath") ?? ""
        self.customBinaryPath = defaults.string(forKey: "customBinaryPath") ?? ""
        self.customArguments = defaults.string(forKey: "customArguments") ?? "{prompt}"
        
        if defaults.object(forKey: "autoPaste") != nil {
            self.autoPaste = defaults.bool(forKey: "autoPaste")
        } else {
            self.autoPaste = true
        }

        if defaults.object(forKey: "launchAtLogin") != nil {
            self.launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        } else {
            // No stored preference yet: adopt the OS login-item state so the
            // menu reflects reality (e.g. enabled manually via System Settings).
            self.launchAtLogin = LaunchAtLoginManager.shared.isEnabled
        }
        
        // Sync initial state from prefs.toml
        reloadFromDisk()
    }
    
    /// Applies prefs.toml as the source of truth. Keys absent from the file
    /// revert to their defaults, so deleting a line in the TOML takes effect.
    /// If the file cannot be read at all, current UserDefaults-backed values
    /// are kept as a fallback.
    func reloadFromDisk() {
        let prefs = PreferencesManager.shared.readPreferences()
        guard !prefs.isEmpty else { return }

        isSyncing = true
        defer { isSyncing = false }

        if let sc = prefs["shortcut"], !sc.isEmpty {
            sync(sc, to: \.shortcut)
        } else {
            sync("ctrl+cmd+g", to: \.shortcut)
        }
        sync(prefs["provider"].flatMap(AIProvider.init(rawValue:)) ?? .agy, to: \.selectedProvider)
        sync(prefs["source_language"].flatMap(Language.init(rawValue:)) ?? .pt_BR, to: \.sourceLanguage)
        sync(prefs["target_language"].flatMap(Language.init(rawValue:)) ?? .en_US, to: \.targetLanguage)
        sync(prefs["tone"].flatMap(LanguageTone.init(rawValue:)) ?? .formal, to: \.selectedTone)
        sync(prefs["auto_paste"].map { $0.lowercased() == "true" } ?? true, to: \.autoPaste)
        // Unlike other keys, an absent launch_at_login keeps the current value
        // (adopted from the OS registration state): deleting the line must not
        // silently unregister a login item the user enabled in System Settings.
        if let raw = prefs["launch_at_login"] {
            sync(raw.lowercased() == "true", to: \.launchAtLogin)
        }
        sync(prefs["agy_path"] ?? "", to: \.agyPath)
        sync(prefs["claude_path"] ?? "", to: \.claudePath)
        sync(prefs["opencode_path"] ?? "", to: \.opencodePath)
        sync(prefs["custom_binary_path"] ?? "", to: \.customBinaryPath)
        sync(prefs["custom_arguments"] ?? "{prompt}", to: \.customArguments)
    }

    /// Assigns only on change so didSet side effects (persistence, hotkey
    /// re-registration) are not triggered on every file reload.
    private func sync<T: Equatable>(_ newValue: T, to path: ReferenceWritableKeyPath<AppSettings, T>) {
        if self[keyPath: path] != newValue {
            self[keyPath: path] = newValue
        }
    }
}
