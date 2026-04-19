import AppKit
import Foundation

extension Notification.Name {
    /// Posted on the main thread after URLs are enqueued from `NSApplicationDelegate` open callbacks.
    static let zipperExternalURLsDidEnqueue = Notification.Name("ZipperExternalURLsDidEnqueue")
}

/// Bridges AppKit `application(_:open:)` callbacks into the main SwiftUI `Window` so Finder opens
/// do not spawn a second `NSWindow` alongside the SwiftUI scene.
enum ExternalOpenCoordinator {
    private static let lock = NSLock()
    private static var pendingURLs: [URL] = []

    /// Enqueue URLs from `NSApplicationDelegate` open-file callbacks (may arrive off the main actor).
    static func enqueue(urls: [URL]) {
        guard !urls.isEmpty else { return }
        lock.lock()
        pendingURLs.append(contentsOf: urls)
        lock.unlock()
    }

    /// Returns and clears all URLs waiting for the main window (call from the main window's `ContentView`).
    @MainActor
    static func dequeueAll() -> [URL] {
        lock.lock()
        let urls = pendingURLs
        pendingURLs.removeAll()
        lock.unlock()
        return urls
    }
}
