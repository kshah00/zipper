import AppKit
import Foundation

/// Checks GitHub Releases for newer Zipper builds and optionally downloads the release disk image.
final class AppUpdateController {
    static let shared = AppUpdateController()

    private let minimumIntervalBetweenChecks: TimeInterval = 60 * 60 * 24
    private let releasesLatestAPIURL = URL(string: "https://api.github.com/repos/kshah00/zipper/releases/latest")!
    private let releasesLatestPageURL = URL(string: "https://github.com/kshah00/zipper/releases/latest")!

    private var activeCheck: Task<Void, Never>?

    private init() {}

    func applicationDidFinishLaunching() {
        scheduleBackgroundCheckIfNeeded()
    }

    func checkForUpdatesFromUser() {
        activeCheck?.cancel()
        activeCheck = Task { [releasesLatestAPIURL] in
            await self.runCheck(apiURL: releasesLatestAPIURL, respectThrottle: false, userInitiated: true)
        }
    }

    func scheduleBackgroundCheckIfNeeded() {
        guard UserDefaults.standard.object(forKey: PreferenceKeys.checkForUpdatesOnLaunch) as? Bool ?? true else {
            return
        }

        activeCheck?.cancel()
        activeCheck = Task { [releasesLatestAPIURL] in
            await self.runCheck(apiURL: releasesLatestAPIURL, respectThrottle: true, userInitiated: false)
        }
    }

    @MainActor
    private func currentMarketingVersion() -> String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "0"
    }

    private func runCheck(apiURL: URL, respectThrottle: Bool, userInitiated: Bool) async {
        if respectThrottle, shouldSkipDueToThrottle() {
            return
        }

        do {
            let release = try await fetchLatestRelease(from: apiURL)
            let remoteVersion = Self.versionString(fromReleaseTag: release.tagName)
            let localVersion = await MainActor.run { currentMarketingVersion() }

            recordSuccessfulCheck()

            guard Self.compareVersions(remoteVersion, isNewerThan: localVersion) else {
                if userInitiated {
                    await MainActor.run { presentUpToDateAlert() }
                }
                return
            }

            let asset = preferredDownloadAsset(in: release.assets)
            let autoDownload = UserDefaults.standard.object(forKey: PreferenceKeys.automaticallyDownloadUpdates) as? Bool ?? false

            if autoDownload {
                if let asset {
                    try await downloadAndRevealUpdate(asset: asset, remoteVersion: remoteVersion)
                } else {
                    await MainActor.run {
                        presentUpdateAvailableAlert(
                            localVersion: localVersion,
                            remoteVersion: remoteVersion,
                            downloadPageURL: releasesLatestPageURL
                        )
                    }
                }
            } else {
                await MainActor.run {
                    let downloadURL = asset.flatMap { URL(string: $0.browserDownloadURL) } ?? releasesLatestPageURL
                    presentUpdateAvailableAlert(
                        localVersion: localVersion,
                        remoteVersion: remoteVersion,
                        downloadPageURL: downloadURL
                    )
                }
            }
        } catch is CancellationError {
            // No UI on cancellation.
        } catch {
            if userInitiated {
                await MainActor.run { presentCheckFailedAlert(message: error.localizedDescription) }
            }
        }
    }

    private func shouldSkipDueToThrottle() -> Bool {
        let last = UserDefaults.standard.double(forKey: PreferenceKeys.lastUpdateCheckTimestamp)
        guard last > 0 else { return false }
        return Date().timeIntervalSince1970 - last < minimumIntervalBetweenChecks
    }

    private func recordSuccessfulCheck() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: PreferenceKeys.lastUpdateCheckTimestamp)
    }

    private func fetchLatestRelease(from apiURL: URL) async throws -> GitHubRelease {
        var request = URLRequest(url: apiURL)
        request.setValue("Zipper/\(await MainActor.run { currentMarketingVersion() }) (macOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateCheckError.unexpectedResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw UpdateCheckError.httpStatus(http.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(GitHubRelease.self, from: data)
    }

    private func preferredDownloadAsset(in assets: [GitHubRelease.Asset]) -> GitHubRelease.Asset? {
        let dmgs = assets.filter { $0.name.lowercased().hasSuffix(".dmg") }
        guard !dmgs.isEmpty else { return nil }

        if let named = dmgs.first(where: { $0.name.lowercased().contains("zipper") }) {
            return named
        }
        return dmgs.first
    }

    private func downloadAndRevealUpdate(asset: GitHubRelease.Asset, remoteVersion: String) async throws {
        guard let sourceURL = URL(string: asset.browserDownloadURL) else {
            throw UpdateCheckError.invalidDownloadURL
        }

        let fileName = asset.name
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        var request = URLRequest(url: sourceURL)
        request.setValue("Zipper/\(await MainActor.run { currentMarketingVersion() }) (macOS)", forHTTPHeaderField: "User-Agent")

        let (tempURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw UpdateCheckError.downloadFailed
        }

        try FileManager.default.moveItem(at: tempURL, to: destination)

        await MainActor.run {
            NSWorkspace.shared.activateFileViewerSelecting([destination])
            presentDownloadedUpdateAlert(version: remoteVersion, fileName: destination.lastPathComponent)
        }
    }

    @MainActor
    private func presentUpToDateAlert() {
        let alert = NSAlert()
        alert.messageText = "You’re up to date"
        alert.informativeText = "Zipper \(currentMarketingVersion()) is the latest release."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @MainActor
    private func presentCheckFailedAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Update check failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @MainActor
    private func presentUpdateAvailableAlert(localVersion: String, remoteVersion: String, downloadPageURL: URL) {
        let alert = NSAlert()
        alert.messageText = "A new version of Zipper is available"
        alert.informativeText = "You have \(localVersion). The latest release is \(remoteVersion)."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Download")
        alert.addButton(withTitle: "Not Now")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(downloadPageURL)
        }
    }

    @MainActor
    private func presentDownloadedUpdateAlert(version: String, fileName: String) {
        let alert = NSAlert()
        alert.messageText = "Update downloaded"
        alert.informativeText = "“\(fileName)” for Zipper \(version) is in your temporary files. Open the disk image to install, then eject and replace the app in Applications."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func versionString(fromReleaseTag tag: String) -> String {
        var trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("v") {
            trimmed.removeFirst()
        }
        return trimmed
    }

    /// Returns `true` if `lhs` is strictly newer than `rhs` using dotted numeric components.
    private static func compareVersions(_ lhs: String, isNewerThan rhs: String) -> Bool {
        let left = lhs.split(separator: ".").compactMap { Int($0) }
        let right = rhs.split(separator: ".").compactMap { Int($0) }
        let maxCount = max(left.count, right.count, 1)
        for index in 0 ..< maxCount {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r {
                return l > r
            }
        }
        return false
    }
}

private enum UpdateCheckError: LocalizedError {
    case unexpectedResponse
    case httpStatus(Int)
    case invalidDownloadURL
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .unexpectedResponse:
            return "The update server returned an unexpected response."
        case .httpStatus(let code):
            return "The update server responded with HTTP \(code)."
        case .invalidDownloadURL:
            return "The download link for this release is invalid."
        case .downloadFailed:
            return "The update could not be downloaded."
        }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }

    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }
}
