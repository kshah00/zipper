import SwiftUI
import AppKit

struct PreferencesView: View {
    @AppStorage(PreferenceKeys.defaultSaveLocationBookmark) private var defaultSaveLocationBookmark = Data()
    @AppStorage(PreferenceKeys.preferredFormat) private var preferredFormat = "zip"
    @AppStorage(PreferenceKeys.openArchivesByDefault) private var openArchivesByDefault = true

    @AppStorage(PreferenceKeys.saveShortcutKey) private var saveShortcutKey = "s"
    @AppStorage(PreferenceKeys.saveShortcutModifiers) private var saveShortcutModifiers = ShortcutModifierMask.command
    @AppStorage(PreferenceKeys.shareShortcutKey) private var shareShortcutKey = "e"
    @AppStorage(PreferenceKeys.shareShortcutModifiers) private var shareShortcutModifiers = ShortcutModifierMask.command

    @State private var savePathLabel = "Not set"

    var body: some View {
        Form {
            Section("Archiving") {
                Picker("Preferred mode", selection: $preferredFormat) {
                    Text("ZIP").tag("zip")
                    Text("7Z").tag("7z")
                }
                .pickerStyle(.segmented)

                Toggle("Open zip / rar / 7z files in Zipper by default", isOn: $openArchivesByDefault)
            }

            Section("Default Save Location") {
                HStack {
                    Text(savePathLabel)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose…", action: chooseDefaultSaveLocation)
                    Button("Clear", action: clearDefaultSaveLocation)
                        .disabled(defaultSaveLocationBookmark.isEmpty)
                }
            }

            Section("Shortcuts") {
                ShortcutRecorderRow(
                    title: "Save As…",
                    key: $saveShortcutKey,
                    modifiersMask: $saveShortcutModifiers,
                    fallbackKey: "s"
                )
                ShortcutRecorderRow(
                    title: "Share",
                    key: $shareShortcutKey,
                    modifiersMask: $shareShortcutModifiers,
                    fallbackKey: "e"
                )
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 460)
        .navigationTitle("Zipper Preferences")
        .padding(16)
        .background(Theme.bg)
        .onAppear(perform: refreshSavePathLabel)
        .onChange(of: defaultSaveLocationBookmark) { _ in refreshSavePathLabel() }
    }

    private func chooseDefaultSaveLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        guard let bookmark = SaveLocationBookmark.create(for: selectedURL) else { return }
        defaultSaveLocationBookmark = bookmark
        refreshSavePathLabel()
    }

    private func clearDefaultSaveLocation() {
        defaultSaveLocationBookmark = Data()
        refreshSavePathLabel()
    }

    private func refreshSavePathLabel() {
        guard let url = SaveLocationBookmark.resolve(defaultSaveLocationBookmark) else {
            savePathLabel = "Not set"
            return
        }
        savePathLabel = url.path
    }
}

private struct ShortcutRecorderRow: View {
    let title: String
    @Binding var key: String
    @Binding var modifiersMask: Int
    let fallbackKey: String

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(width: 70, alignment: .leading)

            Button(action: {
                isRecording.toggle()
                if isRecording {
                    installRecorderMonitor()
                } else {
                    removeRecorderMonitor()
                }
            }) {
                HStack(spacing: 4) {
                    if isRecording {
                        Text("Listening…")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    } else {
                        ForEach(displayShortcutParts, id: \.self) { part in
                            Text(part)
                                .font(.system(size: 12, weight: .medium, design: .default))
                                .foregroundStyle(Theme.textPrimary)
                                .padding(.horizontal, 4)
                                .frame(minWidth: 22, minHeight: 22)
                                .background(Theme.surfaceActive, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .stroke(Theme.border, lineWidth: 1)
                                )
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isRecording ? Theme.accent : Theme.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if isRecording {
                Button("Cancel") {
                    isRecording = false
                    removeRecorderMonitor()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
                .font(.system(size: 12))
            }

            Spacer()
        }
        .onDisappear(perform: removeRecorderMonitor)
    }

    private var displayShortcutParts: [String] {
        let binding = ShortcutBinding(
            key: key,
            modifiersMask: modifiersMask,
            fallbackKey: fallbackKey,
            fallbackMask: ShortcutModifierMask.command
        )
        let resolvedMask = modifiersMask == 0 ? ShortcutModifierMask.command : modifiersMask

        var parts: [String] = []
        if resolvedMask & ShortcutModifierMask.control != 0 { parts.append("⌃") }
        if resolvedMask & ShortcutModifierMask.option != 0 { parts.append("⌥") }
        if resolvedMask & ShortcutModifierMask.shift != 0 { parts.append("⇧") }
        if resolvedMask & ShortcutModifierMask.command != 0 { parts.append("⌘") }
        
        let char = String(binding.keyEquivalent.character).uppercased()
        // Handle special keys if needed, e.g. enter, space, arrows
        switch char {
        case " ": parts.append("Space")
        case "\r", "\n": parts.append("↩")
        case "\u{1B}": parts.append("⎋") // Esc
        default: parts.append(char)
        }
        
        return parts
    }

    private func installRecorderMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isRecording else { return event }

            if event.keyCode == 53 {
                isRecording = false
                removeRecorderMonitor()
                return nil
            }

            let normalized = ShortcutBinding.normalizeKey(event.charactersIgnoringModifiers ?? "")
            guard !normalized.isEmpty else { return nil }

            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let mask = ShortcutBinding.mask(
                command: flags.contains(.command),
                shift: flags.contains(.shift),
                option: flags.contains(.option),
                control: flags.contains(.control)
            )

            key = normalized
            modifiersMask = mask

            isRecording = false
            removeRecorderMonitor()
            return nil
        }
    }

    private func removeRecorderMonitor() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }
}
