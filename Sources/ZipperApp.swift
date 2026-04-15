import SwiftUI

@main
struct ZipperApp: App {
    @AppStorage(PreferenceKeys.openArchivesByDefault) private var openArchivesByDefault = true

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(initialURL: nil)
                .frame(minWidth: 380, minHeight: 520)
                .background(Theme.bg)
                .onOpenURL { url in
                    NotificationCenter.default.post(name: .openArchiveInCurrentWindow, object: url)
                }
                .onAppear {
                    if openArchivesByDefault {
                        FileAssociationManager.registerAsDefaultArchiveHandler()
                    }
                }
                .onChange(of: openArchivesByDefault) { enabled in
                    if enabled {
                        FileAssociationManager.registerAsDefaultArchiveHandler()
                    }
                }
        }
        .windowResizability(.automatic)
        .windowStyle(.hiddenTitleBar)

        Settings {
            PreferencesView()
        }

        WindowGroup(for: URL.self) { $openedURL in
            ContentView(initialURL: openedURL)
                .frame(minWidth: 380, minHeight: 520)
                .background(Theme.bg)
        }
        .windowResizability(.automatic)
        .windowStyle(.hiddenTitleBar)
    }
}
