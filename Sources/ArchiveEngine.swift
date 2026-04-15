import Foundation
import AppKit

class ArchiveTask {
    var process: Process?
    var isCancelled = false
    
    func cancel() {
        isCancelled = true
        if process?.isRunning == true {
            process?.terminate()
        }
    }
}

class ArchiveEngine {
    static let shared = ArchiveEngine()

    private let sevenZipPercentRegex = try! NSRegularExpression(pattern: "(\\d{1,3})%")

    struct ExcludedPath {
        let relativePath: String
        let isDirectory: Bool
    }

    /// Compresses to a temp directory (always writable), then hands back the URL.
    /// The caller is responsible for prompting the user to save/move the file.
    @discardableResult
    func compress(
        url: URL,
        format: String,
        password: String,
        removeMacFiles: Bool,
        excludedPaths: [ExcludedPath],
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) -> ArchiveTask {
        let task = ArchiveTask()
        
        DispatchQueue.global(qos: .userInitiated).async {

            // Write to a temp dir — always sandbox-accessible
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("ZipperOutput", isDirectory: true)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let baseName = url.lastPathComponent
            let outputName = "\(baseName).\(format)"
            let outputURL = tempDir.appendingPathComponent(outputName)

            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }

            let normalizedExclusions = excludedPaths
                .map { exclusion -> ExcludedPath in
                    let cleanPath = exclusion.relativePath
                        .replacingOccurrences(of: "\\", with: "/")
                        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    return ExcludedPath(relativePath: cleanPath, isDirectory: exclusion.isDirectory)
                }
                .filter { !$0.relativePath.isEmpty }

            let progressPlan = self.makeProgressPlan(
                sourceURL: url,
                baseName: baseName,
                removeMacFiles: removeMacFiles,
                exclusions: normalizedExclusions
            )
            var processedBytes: Int64 = 0
            var seenEntries = Set<String>()
            var reportedProgress = 0.0

            let process = Process()
            task.process = process
            
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe

            if format == "zip" {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                var args = ["-r"]

                if !password.isEmpty {
                    args += ["-P", password]
                }

                args.append(outputURL.path)
                args.append(baseName)

                if removeMacFiles {
                    args += ["-x", "*.DS_Store*", "-x", "*__MACOSX*"]
                }

                for ex in normalizedExclusions {
                    let fullPath = "\(baseName)/\(ex.relativePath)"
                    args += ["-x", fullPath]
                    if ex.isDirectory { args += ["-x", "\(fullPath)/*"] }
                }

                process.arguments = args
                process.currentDirectoryURL = url.deletingLastPathComponent()

            } else if format == "7z" {
                guard let sevenZipURL = Bundle.main.url(forResource: "7zz", withExtension: nil) else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(
                            domain: "ArchiveError", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Bundled 7zz not found"]
                        )))
                    }
                    return
                }

                process.executableURL = sevenZipURL
                var args = ["a", "-bsp1"]

                if !password.isEmpty {
                    args += ["-p\(password)", "-mhe=on"]
                }

                args.append(outputURL.path)
                args.append(baseName)

                if removeMacFiles {
                    args += ["-xr!*.DS_Store", "-xr!__MACOSX"]
                }

                for ex in normalizedExclusions {
                    let fullPath = "\(baseName)/\(ex.relativePath)"
                    args.append("-xr!\(fullPath)")
                    if ex.isDirectory { args.append("-xr!\(fullPath)/*") }
                }

                process.arguments = args
                process.currentDirectoryURL = url.deletingLastPathComponent()
            }

            if task.isCancelled {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "ArchiveError", code: -999, userInfo: [NSLocalizedDescriptionKey: "Cancelled"])))
                }
                return
            }

            var outputBuffer = ""
            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }

                outputBuffer += chunk.replacingOccurrences(of: "\r", with: "\n")
                let lines = outputBuffer.components(separatedBy: "\n")
                outputBuffer = lines.last ?? ""

                for line in lines.dropLast() {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }

                    if format == "zip", trimmed.contains("adding:") {
                        guard let entry = self.zipEntryPath(from: trimmed) else { continue }
                        guard !seenEntries.contains(entry) else { continue }
                        seenEntries.insert(entry)
                        processedBytes += progressPlan.sizeByEntry[entry] ?? 0

                        guard progressPlan.totalBytes > 0 else { continue }
                        let fraction = min(0.97, max(reportedProgress, Double(processedBytes) / Double(progressPlan.totalBytes)))
                        if fraction > reportedProgress {
                            reportedProgress = fraction
                            DispatchQueue.main.async { progress(fraction) }
                        }
                    } else if format == "7z", let fraction = self.sevenZipFraction(from: trimmed) {
                        let scaled = min(0.97, max(reportedProgress, fraction * 0.97))
                        if scaled > reportedProgress {
                            reportedProgress = scaled
                            DispatchQueue.main.async { progress(scaled) }
                        }
                    }
                }
            }

            do {
                try process.run()
                process.waitUntilExit()
                outputPipe.fileHandleForReading.readabilityHandler = nil

                DispatchQueue.main.async {
                    if task.isCancelled {
                        try? FileManager.default.removeItem(at: outputURL)
                        completion(.failure(NSError(
                            domain: "ArchiveError",
                            code: -999,
                            userInfo: [NSLocalizedDescriptionKey: "Cancelled"]
                        )))
                        return
                    }
                    
                    progress(1.0)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        if process.terminationStatus == 0 {
                            completion(.success(outputURL))
                        } else {
                            try? FileManager.default.removeItem(at: outputURL)
                            completion(.failure(NSError(
                                domain: "ArchiveError",
                                code: Int(process.terminationStatus),
                                userInfo: [NSLocalizedDescriptionKey: "Compression failed (exit \(process.terminationStatus))"]
                            )))
                        }
                    }
                }
            } catch {
                outputPipe.fileHandleForReading.readabilityHandler = nil
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        
        return task
    }

    private struct ProgressPlan {
        let totalBytes: Int64
        let sizeByEntry: [String: Int64]
    }

    private func makeProgressPlan(
        sourceURL: URL,
        baseName: String,
        removeMacFiles: Bool,
        exclusions: [ExcludedPath]
    ) -> ProgressPlan {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
            return ProgressPlan(totalBytes: 0, sizeByEntry: [:])
        }

        if !isDirectory.boolValue {
            let size = fileSize(at: sourceURL)
            return ProgressPlan(totalBytes: size, sizeByEntry: [baseName: size])
        }

        var sizeByEntry: [String: Int64] = [:]
        var totalBytes: Int64 = 0
        let excludedFiles = Set(exclusions.filter { !$0.isDirectory }.map(\ .relativePath))
        let excludedDirectories = exclusions.filter(\ .isDirectory).map(\ .relativePath)

        guard let enumerator = fm.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsPackageDescendants, .skipsHiddenFiles]
        ) else {
            return ProgressPlan(totalBytes: 0, sizeByEntry: [:])
        }

        for case let fileURL as URL in enumerator {
            guard let relativePath = relativePath(for: fileURL, base: sourceURL) else { continue }
            if shouldSkip(relativePath: relativePath, removeMacFiles: removeMacFiles, excludedFiles: excludedFiles, excludedDirectories: excludedDirectories) {
                continue
            }

            let size = fileSize(at: fileURL)
            let entryPath = "\(baseName)/\(relativePath)"
            sizeByEntry[entryPath] = size
            totalBytes += size
        }

        return ProgressPlan(totalBytes: totalBytes, sizeByEntry: sizeByEntry)
    }

    private func relativePath(for fileURL: URL, base: URL) -> String? {
        let basePath = base.path
        let filePath = fileURL.path
        guard filePath.hasPrefix(basePath) else { return nil }
        return filePath.replacingOccurrences(of: basePath + "/", with: "")
    }

    private func fileSize(at url: URL) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return 0 }
        return size
    }

    private func shouldSkip(
        relativePath: String,
        removeMacFiles: Bool,
        excludedFiles: Set<String>,
        excludedDirectories: [String]
    ) -> Bool {
        if excludedFiles.contains(relativePath) { return true }
        if excludedDirectories.contains(where: { relativePath == $0 || relativePath.hasPrefix($0 + "/") }) { return true }

        guard removeMacFiles else { return false }
        let components = relativePath.split(separator: "/").map(String.init)
        if components.contains("__MACOSX") { return true }
        if relativePath.hasSuffix(".DS_Store") { return true }
        return false
    }

    private func zipEntryPath(from line: String) -> String? {
        guard let addingRange = line.range(of: "adding:") else { return nil }
        var remainder = line[addingRange.upperBound...].trimmingCharacters(in: .whitespaces)
        if let parenIndex = remainder.firstIndex(of: "(") {
            remainder = remainder[..<parenIndex].trimmingCharacters(in: .whitespaces)
        }
        if remainder.hasSuffix("/") { return nil }
        return remainder
    }

    private func sevenZipFraction(from line: String) -> Double? {
        let nsLine = line as NSString
        guard let match = sevenZipPercentRegex.matches(in: line, range: NSRange(location: 0, length: nsLine.length)).last,
              match.numberOfRanges >= 2 else { return nil }
        let percentString = nsLine.substring(with: match.range(at: 1))
        guard let percent = Double(percentString) else { return nil }
        return min(max(percent / 100.0, 0), 1)
    }

    /// Copy the temp archive to a user-chosen destination via NSSavePanel.
    /// Returns the final saved URL or nil if cancelled.
    @MainActor
    func saveArchive(tempURL: URL, suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = []
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let destination = panel.url else { return nil }

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: tempURL, to: destination)
            return destination
        } catch {
            return nil
        }
    }
}
