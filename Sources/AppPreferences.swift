import SwiftUI

enum PreferenceKeys {
    static let defaultSaveLocationBookmark = "preferences.defaultSaveLocationBookmark"
    static let preferredFormat = "preferences.preferredFormat"
    static let openArchivesByDefault = "preferences.openArchivesByDefault"

    static let nextShortcutKey = "preferences.shortcuts.next.key"
    static let nextShortcutModifiers = "preferences.shortcuts.next.modifiers"
    static let saveShortcutKey = "preferences.shortcuts.save.key"
    static let saveShortcutModifiers = "preferences.shortcuts.save.modifiers"
    static let shareShortcutKey = "preferences.shortcuts.share.key"
    static let shareShortcutModifiers = "preferences.shortcuts.share.modifiers"

    static let enableMouseForwardForNext = "preferences.enableMouseForwardForNext"
    static let respectGitignoreByDefault = "preferences.respectGitignoreByDefault"

    static let checkForUpdatesOnLaunch = "preferences.updates.checkOnLaunch"
    static let automaticallyDownloadUpdates = "preferences.updates.automaticallyDownload"
    static let lastUpdateCheckTimestamp = "preferences.updates.lastCheckTimestamp"
}

enum ShortcutModifierMask {
    static let command = 1
    static let shift = 1 << 1
    static let option = 1 << 2
    static let control = 1 << 3
}

struct ShortcutBinding {
    let key: String
    let modifiersMask: Int
    let fallbackKey: String
    let fallbackMask: Int

    var keyEquivalent: KeyEquivalent {
        let normalized = Self.normalizeKey(key)
        if let character = normalized.first {
            return KeyEquivalent(character)
        }
        return KeyEquivalent(Character(fallbackKey))
    }

    var eventModifiers: EventModifiers {
        let resolvedMask = modifiersMask == 0 ? fallbackMask : modifiersMask
        return Self.modifiers(from: resolvedMask)
    }

    static func normalizeKey(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .prefix(1)
            .description
    }

    static func modifiers(from mask: Int) -> EventModifiers {
        var modifiers: EventModifiers = []
        if mask & ShortcutModifierMask.command != 0 { modifiers.insert(.command) }
        if mask & ShortcutModifierMask.shift != 0 { modifiers.insert(.shift) }
        if mask & ShortcutModifierMask.option != 0 { modifiers.insert(.option) }
        if mask & ShortcutModifierMask.control != 0 { modifiers.insert(.control) }
        return modifiers
    }

    static func mask(command: Bool, shift: Bool, option: Bool, control: Bool) -> Int {
        var value = 0
        if command { value |= ShortcutModifierMask.command }
        if shift { value |= ShortcutModifierMask.shift }
        if option { value |= ShortcutModifierMask.option }
        if control { value |= ShortcutModifierMask.control }
        return value
    }
}

enum SaveLocationBookmark {
    static func create(for directoryURL: URL) -> Data? {
        try? directoryURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    static func resolve(_ data: Data) -> URL? {
        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }
}
