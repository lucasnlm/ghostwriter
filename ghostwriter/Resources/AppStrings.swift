//
//  AppStrings.swift
//  ghostwriter
//

import Foundation

enum AppStrings {
    static func localized(_ key: String, comment: String = "") -> String {
        NSLocalizedString(key, comment: comment)
    }

    static func localizedFormat(_ key: String, _ args: CVarArg...) -> String {
        let format = NSLocalizedString(key, comment: "")
        return String(format: format, arguments: args)
    }

    enum General {
        static var appName: String { localized("app_name") }
    }

    enum Keys {
        static var commandReturn: String { localized("key_command_return") }
        static var escape: String { localized("key_escape") }
    }

    enum Actions {
        static var close: String { localized("action_close") }
        static var settings: String { localized("action_settings") }
        static var launchAtLogin: String { localized("action_launch_at_login") }
        static var swapLanguages: String { localized("action_swap_languages") }
        static var swapUnavailable: String { localized("action_swap_unavailable") }
        static var quit: String { localized("action_quit") }
        static func showWindow(hotkey: String) -> String {
            localizedFormat("action_show_window", hotkey)
        }
        static func showWindowUnavailable(hotkey: String) -> String {
            localizedFormat("action_show_window_unavailable", hotkey)
        }

        static var translateAndInsert: String { localized("action_translate_and_insert") }
        static var improveAndInsert: String { localized("action_improve_and_insert") }
        static var writeAndInsert: String { localized("action_write_and_insert") }
        static var promptMode: String { localized("action_prompt_mode") }
        static var promptModeHelp: String { localized("action_prompt_mode_help") }
    }

    enum Placeholders {
        static func translate(sourceName: String) -> String {
            localizedFormat("placeholder_translate", sourceName)
        }
        static func improve(targetName: String) -> String {
            localizedFormat("placeholder_improve", targetName)
        }
        static var promptMode: String { localized("placeholder_prompt") }
        static var shortcutHint: String { localized("placeholder_shortcut_hint") }
    }

    enum Status {
        static func translating(targetName: String) -> String {
            localizedFormat("status_translating", targetName)
        }
        static func improving(targetName: String) -> String {
            localizedFormat("status_improving", targetName)
        }
        static func generating(targetName: String) -> String {
            localizedFormat("status_generating", targetName)
        }
    }

    enum Errors {
        static func cliNotFound(name: String) -> String {
            localizedFormat("error_cli_not_found", name)
        }
        static func cliExecutionFailed(reason: String) -> String {
            localizedFormat("error_cli_execution_failed", reason)
        }
        static var emptyResponse: String { localized("error_empty_response") }
        static var timedOut: String { localized("error_timeout") }
    }
}
