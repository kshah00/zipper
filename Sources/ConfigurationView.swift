import SwiftUI
import UniformTypeIdentifiers

// MARK: - Supporting Views (extracted to avoid recursive type inference issues)

private struct TreeRowView: View {
    let node: ConfigurationView.FileNode
    let level: Int
    let isOnBinding: Binding<Bool>
    let isExpandedBinding: Binding<Bool>
    let onToggleInclude: () -> Void
    let onToggleExpand: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Indent
                Color.clear.frame(width: CGFloat(level) * 18 + 12, height: 1)

                // Expand/collapse chevron
                if node.isDirectory && !node.children.isEmpty {
                    Button(action: onToggleExpand) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.textMuted)
                            .rotationEffect(.degrees(isExpandedBinding.wrappedValue ? 90 : 0))
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 16)
                }

                Color.clear.frame(width: 4)

                Button(action: onToggleInclude) {
                    HStack(spacing: 0) {
                        // Checkbox
                        ZStack {
                            Circle()
                                .fill(isOnBinding.wrappedValue ? Theme.accent : Color.clear)
                                .frame(width: 16, height: 16)
                                .overlay(
                                    Circle().stroke(
                                        isOnBinding.wrappedValue ? Theme.accent : Theme.textMuted,
                                        lineWidth: 1.2
                                    )
                                )
                            if isOnBinding.wrappedValue {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.black)
                            }
                        }

                        Color.clear.frame(width: 8)

                        // File icon
                        Image(systemName: node.isDirectory ? "folder.fill" : fileIcon(for: node.name))
                            .font(.system(size: 12))
                            .foregroundStyle(node.isDirectory ? Theme.accent.opacity(0.75) : Theme.textMuted)
                            .frame(width: 16)

                        Color.clear.frame(width: 6)

                        // Name
                        Text(node.name)
                            .font(.system(size: 12))
                            .foregroundStyle(isOnBinding.wrappedValue ? Theme.textPrimary : Theme.textSecondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Child count badge
                        if node.isDirectory && !node.children.isEmpty {
                            Text("\(node.children.count)")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.textMuted)
                                .padding(.trailing, 12)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(height: 32)
        }
    }

    private func fileIcon(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift", "py", "js", "ts", "go", "rs", "cpp", "c", "h": return "doc.text.fill"
        case "jpg", "jpeg", "png", "gif", "webp", "heic":             return "photo.fill"
        case "mp4", "mov", "avi", "mkv":                              return "film.fill"
        case "mp3", "wav", "aac", "flac":                             return "waveform"
        case "pdf":                                                    return "doc.richtext.fill"
        case "zip", "7z", "tar", "gz", "rar":                        return "archivebox.fill"
        default:                                                       return "doc.fill"
        }
    }
}

private struct CompletionView: View {
    let outputURL: URL
    let format: String
    let encrypt: Bool
    let saveShortcut: ShortcutBinding
    let shareShortcut: ShortcutBinding
    let onSave: (URL) -> Void
    let onShare: (URL) -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                Spacer()

                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Theme.surface)
                        .frame(width: 90, height: 90)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Theme.accent.opacity(0.3), lineWidth: 1)
                        )
                    Image(systemName: format == "zip" ? "doc.zipper" : "archivebox.fill")
                        .font(.system(size: 40, weight: .ultraLight))
                        .foregroundStyle(Theme.accent)
                        .onDrag {
                            NSItemProvider(object: outputURL as NSURL)
                        } preview: {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: outputURL.path))
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 56, height: 56)
                        }
                }

                VStack(spacing: 4) {
                    Text(outputURL.lastPathComponent)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(sizeSubtext)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }

                if encrypt {
                    detailBadge(icon: "lock.fill", text: "Encrypted")
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle().fill(Theme.border).frame(height: 1)

            VStack(spacing: 10) {
                Button { onSave(outputURL) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill").font(.system(size: 14))
                        Text("Save As…").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(saveShortcut.keyEquivalent, modifiers: saveShortcut.eventModifiers)

                Button { onShare(outputURL) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 12))
                        Text("Share").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(shareShortcut.keyEquivalent, modifiers: shareShortcut.eventModifiers)
            }
            .padding(16)
        }
    }

    private var sizeSubtext: String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
              let outSize = attrs[.size] as? Int64 else { return "" }
        return ByteCountFormatter.string(fromByteCount: outSize, countStyle: .file)
    }

    private func detailBadge(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(Theme.accent)
            Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Theme.surface, in: Capsule())
    }
}

// MARK: - ConfigurationView

struct ConfigurationView: View {

    struct FileNode: Identifiable, Hashable {
        let id = UUID()
        let relativePath: String
        let name: String
        let isDirectory: Bool
        var isIncluded: Bool
        var isExpanded: Bool = true
        var children: [FileNode] = []
    }

    enum Step: Int, CaseIterable {
        case files, format, encryption
        var title: String {
            switch self {
            case .files:      return "Files"
            case .format:     return "Format"
            case .encryption: return "Encryption"
            }
        }
    }

    enum CompletionState {
        case idle, archiving, done(URL), failed(String)
    }

    // MARK: Props
    let url: URL
    let onCancel: () -> Void

    // MARK: State
    @State private var currentStep: Step = .files
    @State private var password = ""
    @State private var encrypt = false
    @State private var removeMacFiles = true
    @State private var format = "zip"
    @State private var progress: Double = 0
    @State private var nodes: [FileNode] = []
    @State private var loadError: String?
    @State private var searchText = ""
    @State private var completionState: CompletionState = .idle
    @State private var keyMonitor: Any?
    @State private var activeArchiveTask: ArchiveTask?

    @AppStorage(PreferenceKeys.defaultSaveLocationBookmark) private var defaultSaveLocationBookmark = Data()
    @AppStorage(PreferenceKeys.preferredFormat) private var preferredFormat = "zip"
    @AppStorage(PreferenceKeys.saveShortcutKey) private var saveShortcutKey = "s"
    @AppStorage(PreferenceKeys.saveShortcutModifiers) private var saveShortcutModifiers = ShortcutModifierMask.command
    @AppStorage(PreferenceKeys.shareShortcutKey) private var shareShortcutKey = "e"
    @AppStorage(PreferenceKeys.shareShortcutModifiers) private var shareShortcutModifiers = ShortcutModifierMask.command
    @FocusState private var isSearchFocused: Bool

    private let formats = ["zip", "7z"]

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            topBar

            Group {
                switch completionState {
                case .idle:
                    VStack(spacing: 0) {
                        stepContent
                        separator
                        bottomBar
                    }

                case .archiving:
                    progressView

                case .done(let outURL):
                    CompletionView(
                        outputURL: outURL,
                        format: format,
                        encrypt: encrypt,
                        saveShortcut: saveShortcut,
                        shareShortcut: shareShortcut,
                        onSave: saveArchive,
                        onShare: shareArchive
                    )

                case .failed(let msg):
                    errorView(message: msg)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.3), value: stateKey)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            format = formats.contains(preferredFormat) ? preferredFormat : "zip"
            loadTree()
            setupKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    private var stateKey: String {
        switch completionState {
        case .idle: return "idle_\(currentStep.rawValue)"
        case .archiving: return "archiving"
        case .done: return "done"
        case .failed: return "failed"
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        ZStack {
            Text("Z I P P E R")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            HStack {
                Button(backLabel, action: handleBack).buttonStyle(SubtleButtonStyle())
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 10)
    }

    private var backLabel: String {
        switch completionState {
        case .archiving:      return "Cancel"
        case .done, .failed:  return "Discard"
        case .idle where currentStep == .files: return "Back"
        default: return "Back"
        }
    }

    private func handleBack() {
        switch completionState {
        case .archiving:
            activeArchiveTask?.cancel()
        case .done, .failed:
            completionState = .idle
            currentStep = .files
            onCancel()
        case .idle where currentStep == .files:
            onCancel()
        case .idle:
            withAnimation(.easeInOut(duration: 0.22)) {
                currentStep = Step(rawValue: currentStep.rawValue - 1) ?? .files
            }
        }
    }

    // MARK: - Step Content

    private var stepContent: some View {
        VStack(spacing: 0) {
            stepIndicator.padding(.vertical, 10)
            separator
            Group {
                switch currentStep {
                case .files:      filesStep
                case .format:     formatStep
                case .encryption: encryptionStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.22), value: currentStep)
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.rawValue) { step in
                Capsule()
                    .fill(step == currentStep ? Theme.accent : (step.rawValue < currentStep.rawValue ? Theme.accent.opacity(0.4) : Theme.border))
                    .frame(width: step == currentStep ? 18 : 6, height: 6)
                    .animation(.easeInOut(duration: 0.25), value: currentStep)
            }
        }
    }

    // MARK: - Step 1: Files

    private var filesStep: some View {
        VStack(spacing: 0) {
            // File badge
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable().frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(url.lastPathComponent)
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        .lineLimit(1).truncationMode(.middle)
                    Text(fileSizeText)
                        .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text("\(includedCount) selected")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.surface, in: Capsule())
            }
            .padding(.horizontal, 16).padding(.vertical, 10)

            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                TextField("Search files…", text: $searchText).textFieldStyle(.plain).font(.system(size: 12))
                    .focused($isSearchFocused)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Theme.surface)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 0.5) }

            separator

            // Tree
            if let loadError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 28)).foregroundStyle(Theme.textMuted)
                    Text(loadError).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleRows, id: \.node.id) { item in
                            TreeRowView(
                                node: item.node,
                                level: item.level,
                                isOnBinding: binding(forPath: item.node.relativePath),
                                isExpandedBinding: expandedBinding(forPath: item.node.relativePath),
                                onToggleInclude: {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        nodes = setNodeIncluded(path: item.node.relativePath, included: !isNodeIncluded(path: item.node.relativePath, in: nodes), in: nodes)
                                    }
                                },
                                onToggleExpand: {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        nodes = setNodeExpanded(path: item.node.relativePath, expanded: !isNodeExpanded(path: item.node.relativePath, in: nodes), in: nodes)
                                    }
                                }
                            )
                            Rectangle().fill(Theme.border.opacity(0.4)).frame(height: 0.5).padding(.leading, 46)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: .infinity)
            }

            separator

            // Strip metadata
            Toggle("Strip Mac metadata", isOn: $removeMacFiles)
                .toggleStyle(.switch).tint(Theme.accent)
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 18).padding(.vertical, 12)
        }
    }

    // MARK: - Step 2: Format

    private var formatStep: some View {
        VStack(spacing: 24) {
            Spacer()

            HStack(spacing: 14) {
                formatCard(fmt: "zip", icon: "doc.zipper",     title: "ZIP", subtitle: "Universal compatibility\nWorks everywhere")
                formatCard(fmt: "7z",  icon: "archivebox.fill", title: "7Z",  subtitle: "Better compression\nSmaller file size")
            }
            .padding(.horizontal, 24)
            Spacer()
        }
    }

    private func formatCard(fmt: String, icon: String, title: String, subtitle: String) -> some View {
        let selected = format == fmt
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { format = fmt }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 34, weight: .ultraLight))
                    .foregroundStyle(selected ? Theme.accent : Theme.textSecondary)
                Text(title).font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 28)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(selected ? Theme.surfaceActive : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(selected ? Theme.accent : Theme.border, lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 3: Encryption

    private var encryptionStep: some View {
        VStack(spacing: 24) {
            Spacer()

            HStack(spacing: 14) {
                encryptCard(value: false, icon: "lock.open.fill", title: "None",    subtitle: "No password\nOpen access")
                encryptCard(value: true,  icon: "lock.fill",      title: "Encrypt", subtitle: "Password protected\nAES-256")
            }
            .padding(.horizontal, 24)

            if encrypt {
                HStack(spacing: 8) {
                    Image(systemName: "key.fill").font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                    SecureField("Enter password", text: $password).textFieldStyle(.plain).font(.system(size: 13))
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(password.isEmpty ? Theme.border : Theme.accent.opacity(0.6), lineWidth: 1))
                .padding(.horizontal, 24)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer()
        }
        .animation(.easeInOut(duration: 0.25), value: encrypt)
    }

    private func encryptCard(value: Bool, icon: String, title: String, subtitle: String) -> some View {
        let selected = encrypt == value
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { encrypt = value; if !value { password = "" } }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 34, weight: .ultraLight))
                    .foregroundStyle(selected ? Theme.accent : Theme.textSecondary)
                Text(title).font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 28)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(selected ? Theme.surfaceActive : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(selected ? Theme.accent : Theme.border, lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Progress

    private var progressView: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle().stroke(Theme.surface, lineWidth: 5).frame(width: 88, height: 88)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 88, height: 88)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.25), value: progress)
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 18, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
            }
            VStack(spacing: 4) {
                Text("Compressing…").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.textPrimary)
                Text(url.lastPathComponent).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 40)).foregroundStyle(.red.opacity(0.8))
            Text("Compression Failed").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Text(message).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            Button("Try Again") { completionState = .idle; currentStep = .files }
                .buttonStyle(GoldButtonStyle())
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Bottom Bar

    private var separator: some View {
        Rectangle().fill(Theme.border).frame(height: 1)
    }

    private var bottomBar: some View {
        HStack {
            Button("Back") {
                if currentStep == .files { onCancel() }
                else { withAnimation(.easeInOut(duration: 0.22)) { currentStep = Step(rawValue: currentStep.rawValue - 1) ?? .files } }
            }
            .buttonStyle(SecondaryButtonStyle())
            Spacer()
            if currentStep == .encryption {
                Button("Compress", action: startArchiving)
                    .buttonStyle(GoldButtonStyle())
                    .disabled(!canCompress).opacity(canCompress ? 1 : 0.35)
            } else {
                Button("Next", action: goToNextStep)
                .buttonStyle(GoldButtonStyle())
                .disabled(!canProceed).opacity(canProceed ? 1 : 0.35)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    private var canProceed: Bool { currentStep == .files ? includedCount > 0 : true }
    private var canCompress: Bool { includedCount > 0 && !(encrypt && password.isEmpty) }

    private var saveShortcut: ShortcutBinding {
        ShortcutBinding(
            key: saveShortcutKey,
            modifiersMask: saveShortcutModifiers,
            fallbackKey: "s",
            fallbackMask: ShortcutModifierMask.command
        )
    }

    private var shareShortcut: ShortcutBinding {
        ShortcutBinding(
            key: shareShortcutKey,
            modifiersMask: shareShortcutModifiers,
            fallbackKey: "e",
            fallbackMask: ShortcutModifierMask.command
        )
    }

    // MARK: - File Actions

    private func saveArchive(tempURL: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = tempURL.lastPathComponent
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        if let defaultDirectory = SaveLocationBookmark.resolve(defaultSaveLocationBookmark) {
            _ = defaultDirectory.startAccessingSecurityScopedResource()
            panel.directoryURL = defaultDirectory
            defaultDirectory.stopAccessingSecurityScopedResource()
        }

        guard panel.runModal() == .OK, let dest = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
            try FileManager.default.copyItem(at: tempURL, to: dest)
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        } catch {
            completionState = .failed(error.localizedDescription)
        }
    }

    private func shareArchive(url: URL) {
        let picker = NSSharingServicePicker(items: [url])
        if let contentView = NSApp.keyWindow?.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
    }

    private func goToNextStep() {
        guard case .idle = completionState else { return }
        guard currentStep != .encryption else { return }
        guard !isSearchFocused else { return }
        guard canProceed else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            currentStep = Step(rawValue: currentStep.rawValue + 1) ?? .encryption
        }
    }

    private func setupKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Return (36) or Keypad Enter (76)
            if event.keyCode == 36 || event.keyCode == 76 {
                if currentStep == .encryption {
                    if canCompress { startArchiving() }
                } else {
                    if canProceed { goToNextStep() }
                }
                return nil
            }
            
            let isTextFieldFocused = (NSApp.keyWindow?.firstResponder is NSTextView)
            
            if !isTextFieldFocused {
                if event.keyCode == 124 { // Right arrow
                    if currentStep != .encryption && canProceed {
                        goToNextStep()
                    }
                    return nil
                } else if event.keyCode == 123 { // Left arrow
                    handleBack()
                    return nil
                }
            }
            
            return event
        }
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }

    // MARK: - Archive

    private func startArchiving() {
        guard canCompress else { return }
        withAnimation(.easeInOut(duration: 0.3)) { completionState = .archiving; progress = 0 }

        activeArchiveTask = ArchiveEngine.shared.compress(
            url: url, format: format, password: encrypt ? password : "",
            removeMacFiles: removeMacFiles, excludedPaths: excludedPaths()
        ) { value in
            progress = value
        } completion: { result in
            withAnimation(.easeInOut(duration: 0.4)) {
                switch result {
                case .success(let outURL):
                    completionState = .done(outURL)
                case .failure(let err):
                    let nsError = err as NSError
                    if nsError.code == -999 {
                        completionState = .idle
                    } else {
                        completionState = .failed(err.localizedDescription)
                    }
                }
                activeArchiveTask = nil
            }
        }
    }

    // MARK: - Helpers

    private var fileSizeText: String {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return "" }
        if isDir.boolValue {
            let count = (try? fm.contentsOfDirectory(atPath: url.path))?.count ?? 0
            return "\(count) item\(count == 1 ? "" : "s")"
        }
        guard let attrs = try? fm.attributesOfItem(atPath: url.path), let size = attrs[.size] as? Int64 else { return "" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private var includedCount: Int { flatten(nodes).filter(\.isIncluded).count }

    struct NodeRow { let node: FileNode; let level: Int }

    private var visibleRows: [NodeRow] {
        let source = searchText.isEmpty ? nodes : filterNodes(nodes, query: searchText.lowercased())
        return flattenVisible(source, level: 0)
    }

    private func flattenVisible(_ input: [FileNode], level: Int) -> [NodeRow] {
        input.flatMap { node -> [NodeRow] in
            var rows: [NodeRow] = [NodeRow(node: node, level: level)]
            if node.isDirectory && node.isExpanded && searchText.isEmpty {
                rows += flattenVisible(node.children, level: level + 1)
            } else if node.isDirectory && !searchText.isEmpty {
                rows += flattenVisible(node.children, level: level + 1)
            }
            return rows
        }
    }

    private func filterNodes(_ nodes: [FileNode], query: String) -> [FileNode] {
        var result: [FileNode] = []
        for node in nodes {
            if node.name.lowercased().contains(query) {
                result.append(node)
            } else if !node.children.isEmpty {
                let filtered = filterNodes(node.children, query: query)
                if !filtered.isEmpty {
                    var copy = node; copy.children = filtered; result.append(copy)
                }
            }
        }
        return result
    }

    // MARK: - Tree Logic

    private func loadTree() {
        loadError = nil
        do {
            nodes = try buildNodes(for: url, baseURL: url)
            if nodes.isEmpty {
                nodes = [FileNode(relativePath: "", name: url.lastPathComponent, isDirectory: false, isIncluded: true)]
            }
        } catch {
            loadError = "Unable to inspect folder contents."
            nodes = [FileNode(relativePath: "", name: url.lastPathComponent, isDirectory: false, isIncluded: true)]
        }
    }

    private func buildNodes(for targetURL: URL, baseURL: URL) throws -> [FileNode] {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDirectory)
        if !isDirectory.boolValue {
            return [FileNode(relativePath: "", name: targetURL.lastPathComponent, isDirectory: false, isIncluded: true)]
        }
        let items = try FileManager.default.contentsOfDirectory(
            at: targetURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        return try items.map { itemURL in
            let values = try itemURL.resourceValues(forKeys: [.isDirectoryKey])
            let itemIsDirectory = values.isDirectory ?? false
            let relativePath = itemURL.path.replacingOccurrences(of: baseURL.path + "/", with: "")
            var node = FileNode(relativePath: relativePath, name: itemURL.lastPathComponent,
                                isDirectory: itemIsDirectory, isIncluded: true, isExpanded: true)
            if itemIsDirectory { node.children = try buildNodes(for: itemURL, baseURL: baseURL) }
            return node
        }
    }

    private func flatten(_ input: [FileNode]) -> [FileNode] {
        input.flatMap { [$0] + flatten($0.children) }
    }

    private func binding(forPath path: String) -> Binding<Bool> {
        Binding(
            get: { isNodeIncluded(path: path, in: nodes) },
            set: { newValue in
                withAnimation(.easeInOut(duration: 0.15)) {
                    nodes = setNodeIncluded(path: path, included: newValue, in: nodes)
                }
            }
        )
    }

    private func expandedBinding(forPath path: String) -> Binding<Bool> {
        Binding(
            get: { isNodeExpanded(path: path, in: nodes) },
            set: { newValue in nodes = setNodeExpanded(path: path, expanded: newValue, in: nodes) }
        )
    }

    private func isNodeExpanded(path: String, in nodes: [FileNode]) -> Bool {
        for node in nodes {
            if node.relativePath == path { return node.isExpanded }
            if let r = findExpanded(path: path, in: node.children) { return r }
        }
        return true
    }

    private func findExpanded(path: String, in nodes: [FileNode]) -> Bool? {
        for node in nodes {
            if node.relativePath == path { return node.isExpanded }
            if let r = findExpanded(path: path, in: node.children) { return r }
        }
        return nil
    }

    private func setNodeExpanded(path: String, expanded: Bool, in nodes: [FileNode]) -> [FileNode] {
        nodes.map { node in
            var u = node
            if node.relativePath == path { u.isExpanded = expanded; return u }
            if !node.children.isEmpty { u.children = setNodeExpanded(path: path, expanded: expanded, in: node.children) }
            return u
        }
    }

    private func isNodeIncluded(path: String, in nodes: [FileNode]) -> Bool {
        for node in nodes {
            if node.relativePath == path { return node.isIncluded }
            if !node.children.isEmpty {
                let r = isNodeIncluded(path: path, in: node.children)
                if r || containsPath(path: path, in: node.children) { return r }
            }
        }
        return false
    }

    private func containsPath(path: String, in nodes: [FileNode]) -> Bool {
        for node in nodes {
            if node.relativePath == path { return true }
            if containsPath(path: path, in: node.children) { return true }
        }
        return false
    }

    private func setNodeIncluded(path: String, included: Bool, in nodes: [FileNode]) -> [FileNode] {
        nodes.map { node in
            var u = node
            if node.relativePath == path {
                u.isIncluded = included
                if !u.children.isEmpty { u.children = setAllIncluded(u.children, included: included) }
                return u
            }
            if !node.children.isEmpty {
                u.children = setNodeIncluded(path: path, included: included, in: node.children)
                if node.isDirectory { u.isIncluded = u.children.contains(where: \.isIncluded) }
            }
            return u
        }
    }

    private func setAllIncluded(_ nodes: [FileNode], included: Bool) -> [FileNode] {
        nodes.map { node in
            var u = node; u.isIncluded = included
            if !u.children.isEmpty { u.children = setAllIncluded(u.children, included: included) }
            return u
        }
    }

    private func excludedPaths() -> [ArchiveEngine.ExcludedPath] {
        flatten(nodes).filter { !$0.isIncluded }
            .map { ArchiveEngine.ExcludedPath(relativePath: $0.relativePath, isDirectory: $0.isDirectory) }
    }
}
