import SwiftUI
import AppKit

final class ZipperAppDelegate: NSObject, NSApplicationDelegate {
    private func routeExternalOpen(urls: [URL], application: NSApplication) {
        ExternalOpenCoordinator.enqueue(urls: urls)
        Task { @MainActor in
            application.activate(ignoringOtherApps: true)
            NSApp.windows
                .filter { $0.isVisible && !$0.isMiniaturized }
                .forEach { $0.makeKeyAndOrderFront(nil) }
            NotificationCenter.default.post(name: .zipperExternalURLsDidEnqueue, object: nil)
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        routeExternalOpen(urls: [url], application: sender)
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        routeExternalOpen(urls: urls, application: sender)
        sender.reply(toOpenOrPrint: urls.isEmpty ? .failure : .success)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        routeExternalOpen(urls: urls, application: application)
    }
}

@main
struct ZipperApp: App {
    @NSApplicationDelegateAdaptor(ZipperAppDelegate.self) private var appDelegate
    @AppStorage(PreferenceKeys.openArchivesByDefault) private var openArchivesByDefault = false

    var body: some Scene {
        Window("Zipper", id: "main") {
            ContentView()
                .frame(minWidth: 380, minHeight: 520)
                .background(Theme.bg)
                .onAppear {
                    FileAssociationManager.registerCurrentAppIfNeeded()
                    FileAssociationManager.setArchiveAssociation(enabled: openArchivesByDefault)
                }
                .onChange(of: openArchivesByDefault) { enabled in
                    FileAssociationManager.setArchiveAssociation(enabled: enabled)
                }
        }
        .windowResizability(.automatic)
        .windowStyle(.hiddenTitleBar)

        Settings {
            PreferencesView()
        }
    }
}
