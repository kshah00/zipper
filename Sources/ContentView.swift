import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct FileDropReceiver: NSViewRepresentable {
    @Binding var isTargeted: Bool
    let onFileDrop: (URL) -> Void

    func makeNSView(context: Context) -> DropView {
        let view = DropView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: DropView, context: Context) {
        nsView.coordinator = context.coordinator
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isTargeted: $isTargeted, onFileDrop: onFileDrop)
    }

    final class Coordinator: NSObject {
        @Binding var isTargeted: Bool
        let onFileDrop: (URL) -> Void

        init(isTargeted: Binding<Bool>, onFileDrop: @escaping (URL) -> Void) {
            _isTargeted = isTargeted
            self.onFileDrop = onFileDrop
        }
    }

    final class DropView: NSView {
        weak var coordinator: Coordinator?
        private var pendingURL: URL?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            registerForDraggedTypes([.fileURL])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            guard let coordinator, draggedFileURL(from: sender) != nil else {
                return []
            }

            coordinator.isTargeted = true
            return .copy
        }

        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            draggedFileURL(from: sender) == nil ? [] : .copy
        }

        override func draggingExited(_ sender: NSDraggingInfo?) {
            coordinator?.isTargeted = false
            pendingURL = nil
        }

        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
            draggedFileURL(from: sender) != nil
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            pendingURL = draggedFileURL(from: sender)
            return pendingURL != nil
        }

        override func concludeDragOperation(_ sender: NSDraggingInfo?) {
            guard let coordinator else { return }

            coordinator.isTargeted = false

            guard let pendingURL else { return }
            self.pendingURL = nil

            coordinator.onFileDrop(pendingURL)
        }

        private func draggedFileURL(from sender: NSDraggingInfo) -> URL? {
            let classes: [AnyClass] = [NSURL.self]
            let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
            let urls = sender.draggingPasteboard.readObjects(forClasses: classes, options: options) as? [URL]
            return urls?.first
        }
    }
}

struct ContentView: View {
    let initialURL: URL?

    @State private var selectedURL: URL?
    @State private var extractionDirectoryURL: URL?
    @State private var hasHandledInitialURL = false
    @State private var isDropTargeted = false
    @State private var iconBreathing = false
    @State private var isHoveringDropZone = false
    @AppStorage(PreferenceKeys.defaultSaveLocationBookmark) private var defaultSaveLocationBookmark = Data()

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            if let url = selectedURL {
                ConfigurationView(url: url, extractionDirectoryURL: extractionDirectoryURL) {
                    clearSelection()
                }
                .transition(.opacity)
            } else {
                dropZone
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if selectedURL == nil {
                selectItem()
            }
        }
        .overlay(alignment: .topLeading) {
            if selectedURL == nil {
                Button("", action: selectItem)
                    .keyboardShortcut("o", modifiers: .command)
                    .frame(width: 0, height: 0)
                    .opacity(0.001)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                Button("", action: selectArchiveForExtraction)
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                    .frame(width: 0, height: 0)
                    .opacity(0.001)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .background(
            FileDropReceiver(isTargeted: $isDropTargeted, onFileDrop: handleDroppedURL)
        )
        .onAppear {
            if !hasHandledInitialURL, selectedURL == nil, let initialURL {
                hasHandledInitialURL = true

                // External item windows need one turn of the run loop before presenting
                // archive extraction panels; otherwise the destination picker can fail
                // to appear while the new window is still becoming key.
                DispatchQueue.main.async {
                    handlePickedItem(initialURL)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: selectedURL != nil)
    }

    // MARK: - Drop Zone

    private var dropZone: some View {
        VStack(spacing: 0) {
            Text("Z I P P E R")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 32)

            Spacer()

                VStack(spacing: 22) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(isHoveringDropZone ? Theme.surfaceActive : Theme.surface)
                        .frame(width: 120, height: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(
                                    (isDropTargeted || isHoveringDropZone) ? Theme.accent.opacity(0.7) : Theme.border,
                                    lineWidth: (isDropTargeted || isHoveringDropZone) ? 2 : 1
                                )
                        )

                    Image(systemName: "doc.zipper")
                        .font(.system(size: 46, weight: .ultraLight))
                        .foregroundStyle((isDropTargeted || isHoveringDropZone) ? Theme.accent : Theme.textSecondary)
                        .opacity(iconBreathing ? 1.0 : 0.65)
                        .scaleEffect((isDropTargeted || isHoveringDropZone) ? 1.06 : 1.0)
                }
                .animation(.easeInOut(duration: 0.2), value: isDropTargeted)

                VStack(spacing: 6) {
                    Text("Drop file or folder")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
            }

            Spacer()

            VStack(spacing: 10) {
                Button("Choose Item", action: selectItem)
                    .buttonStyle(GoldButtonStyle())

                Button("Extract Archive…", action: selectArchiveForExtraction)
                    .buttonStyle(SubtleButtonStyle())
            }
                .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: selectItem)
        .onHover { hovering in
            isHoveringDropZone = hovering
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) {
                iconBreathing = true
            }
        }
    }

    // MARK: - Actions

    private func selectItem() {
        let panel = NSOpenPanel()
        panel.title = "Open file or folder"
        panel.prompt = "Open"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            handlePickedItem(url)
        }
    }

    private func selectArchiveForExtraction() {
        let panel = NSOpenPanel()
        panel.title = "Choose archive to extract"
        panel.message = "Pick an archive, then choose where the extracted folder should be created."
        panel.prompt = "Choose Archive"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ArchiveFileClassifier.selectableArchiveExtensions

        if panel.runModal() == .OK, let url = panel.url {
            handlePickedItem(url, forceExtractionFlow: true)
        }
    }

    private func handlePickedItem(_ url: URL, forceExtractionFlow: Bool = false) {
        let shouldExtract = forceExtractionFlow || ArchiveFileClassifier.isArchive(url)

        if shouldExtract {
            guard let destinationDirectory = promptForExtractionDirectory(for: url) else { return }
            presentSelection(url, extractionDirectoryURL: destinationDirectory)
            return
        }

        presentSelection(url, extractionDirectoryURL: nil)
    }

    private func promptForExtractionDirectory(for archiveURL: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose where to save extracted files"
        panel.message = "Zipper will create a new folder for “\(ArchiveFileClassifier.extractionFolderName(for: archiveURL))”."
        panel.prompt = "Extract Here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        if let defaultDirectory = SaveLocationBookmark.resolve(defaultSaveLocationBookmark) {
            let isAccessing = defaultDirectory.startAccessingSecurityScopedResource()
            panel.directoryURL = defaultDirectory
            if isAccessing {
                defaultDirectory.stopAccessingSecurityScopedResource()
            }
        } else {
            panel.directoryURL = archiveURL.deletingLastPathComponent()
        }

        guard panel.runModal() == .OK, let directoryURL = panel.url else { return nil }
        return directoryURL
    }

    private func presentSelection(_ url: URL, extractionDirectoryURL: URL?) {
        withAnimation(.easeInOut(duration: 0.25)) {
            self.extractionDirectoryURL = extractionDirectoryURL
            selectedURL = url
        }
    }

    private func clearSelection() {
        withAnimation(.easeInOut(duration: 0.25)) {
            extractionDirectoryURL = nil
            selectedURL = nil
        }
    }

    private func handleDroppedURL(_ url: URL) {
        isDropTargeted = false
        NSApp.activate(ignoringOtherApps: true)
        handlePickedItem(url)
    }
}
