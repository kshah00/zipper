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

    enum ErrorCode {
        static let bundledSevenZipMissing = -1
        static let passwordRequired = -2
        static let cancelled = -999
    }

    struct ArchiveInspection {
        let requiresPassword: Bool
    }

    private let sevenZipPercentRegex = try! NSRegularExpression(pattern: "(\\d{1,3})%")

    struct ExcludedPath {
        let relativePath: String
        let isDirectory: Bool
    }

    func inspectArchive(
        archiveURL: URL,
        completion: @escaping (Result<ArchiveInspection, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let sevenZipURL = Bundle.main.url(forResource: "7zz", withExtension: nil) else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(
                        domain: "ArchiveError",
                        code: ErrorCode.bundledSevenZipMissing,
                        userInfo: [NSLocalizedDescriptionKey: "Bundled 7zz not found"]
                    )))
                }
                return
            }

            let process = Process()
            let outputPipe = Pipe()
            var outputLog = ""

            process.standardOutput = outputPipe
            process.standardError = outputPipe
            process.executableURL = sevenZipURL
            process.currentDirectoryURL = archiveURL.deletingLastPathComponent()
            process.arguments = ["l", "-slt", archiveURL.path]

            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                outputLog += chunk
            }

            do {
                try process.run()
                process.waitUntilExit()
                outputPipe.fileHandleForReading.readabilityHandler = nil

                DispatchQueue.main.async {
                    if process.terminationStatus == 0 {
                        completion(.success(ArchiveInspection(requiresPassword: outputLog.contains("Encrypted = +"))))
                    } else {
                        completion(.failure(NSError(
                            domain: "ArchiveError",
                            code: Int(process.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: self.failureDescription(
                                for: "archive inspection",
                                terminationStatus: process.terminationStatus,
                                output: outputLog
                            )]
                        )))
                    }
                }
            } catch {
                outputPipe.fileHandleForReading.readabilityHandler = nil
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func isPasswordError(_ error: Error) -> Bool {
        (error as NSError).code == ErrorCode.passwordRequired
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
        gitignoreExcludedPaths: [ExcludedPath],
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) -> ArchiveTask {
        let task = ArchiveTask()
        
        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default

            // Write to a temp dir — always sandbox-accessible
            let tempDir = fileManager.temporaryDirectory
                .appendingPathComponent("ZipperOutput", isDirectory: true)
            try? fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let baseName = url.lastPathComponent
            let outputName = "\(baseName).\(format)"
            let outputURL = tempDir.appendingPathComponent(outputName)

            if fileManager.fileExists(atPath: outputURL.path) {
                try? fileManager.removeItem(at: outputURL)
            }

            let normalizedExclusions = Self.normalizedExcludedPaths(excludedPaths)
            let normalizedGitignore = Self.normalizedExcludedPaths(gitignoreExcludedPaths)
            let mergedExclusions = Self.mergedExcludedPaths(normalizedExclusions, normalizedGitignore)

            let progressPlan = self.makeProgressPlan(
                sourceURL: url,
                baseName: baseName,
                removeMacFiles: removeMacFiles,
                exclusions: mergedExclusions
            )
            var processedBytes: Int64 = 0
            var seenEntries = Set<String>()
            var reportedProgress = 0.0

            let process = Process()
            task.process = process
            
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe
            var cleanupURLs: [URL] = []
            defer {
                for cleanupURL in cleanupURLs {
                    try? fileManager.removeItem(at: cleanupURL)
                }
            }

            do {
                if format == "zip" {
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                    var args = ["-r"]

                    if !password.isEmpty {
                        args += ["-P", password]
                    }

                    args.append(outputURL.path)
                    args.append(baseName)

                    let excludePatterns = self.zipExcludePatterns(
                        baseName: baseName,
                        removeMacFiles: removeMacFiles,
                        exclusions: mergedExclusions
                    )
                    if !excludePatterns.isEmpty {
                        let excludeListURL = try self.writeListFile(
                            patterns: excludePatterns,
                            in: tempDir,
                            prefix: "zip-excludes"
                        )
                        cleanupURLs.append(excludeListURL)
                        args.append("-x@\(excludeListURL.path)")
                    }

                    process.arguments = args
                    process.currentDirectoryURL = url.deletingLastPathComponent()

                } else if format == "7z" {
                    guard let sevenZipURL = Bundle.main.url(forResource: "7zz", withExtension: nil) else {
                        DispatchQueue.main.async {
                            completion(.failure(NSError(
                                domain: "ArchiveError", code: ErrorCode.bundledSevenZipMissing,
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

                    let excludePatterns = self.sevenZipExcludePatterns(
                        baseName: baseName,
                        removeMacFiles: removeMacFiles,
                        exclusions: mergedExclusions
                    )
                    if !excludePatterns.isEmpty {
                        let excludeListURL = try self.writeListFile(
                            patterns: excludePatterns,
                            in: tempDir,
                            prefix: "7z-excludes"
                        )
                        cleanupURLs.append(excludeListURL)
                        args += ["-scsUTF-8", "-xr@\(excludeListURL.path)"]
                    }

                    process.arguments = args
                    process.currentDirectoryURL = url.deletingLastPathComponent()
                }

                if task.isCancelled {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "ArchiveError", code: ErrorCode.cancelled, userInfo: [NSLocalizedDescriptionKey: "Cancelled"])))
                    }
                    return
                }

                var outputBuffer = ""
                outputPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }

                    if format == "7z" {
                        self.reportSevenZipProgress(from: chunk, reportedProgress: &reportedProgress, progress: progress)
                        return
                    }

                    outputBuffer += chunk.replacingOccurrences(of: "\r", with: "\n")
                    let lines = outputBuffer.components(separatedBy: "\n")
                    outputBuffer = lines.last ?? ""

                    for line in lines.dropLast() {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty, trimmed.contains("adding:") else { continue }
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
                    }
                }

                try process.run()
                process.waitUntilExit()
                outputPipe.fileHandleForReading.readabilityHandler = nil

                DispatchQueue.main.async {
                    if task.isCancelled {
                        try? fileManager.removeItem(at: outputURL)
                        completion(.failure(NSError(
                            domain: "ArchiveError",
                            code: ErrorCode.cancelled,
                            userInfo: [NSLocalizedDescriptionKey: "Cancelled"]
                        )))
                        return
                    }
                    
                    progress(1.0)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        if process.terminationStatus == 0 {
                            completion(.success(outputURL))
                        } else {
                            try? fileManager.removeItem(at: outputURL)
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
                try? fileManager.removeItem(at: outputURL)
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        
        return task
    }

    @discardableResult
    func extract(
        archiveURL: URL,
        destinationURL: URL,
        password: String,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) -> ArchiveTask {
        let task = ArchiveTask()

        DispatchQueue.global(qos: .userInitiated).async {
            guard let sevenZipURL = Bundle.main.url(forResource: "7zz", withExtension: nil) else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(
                        domain: "ArchiveError",
                        code: ErrorCode.bundledSevenZipMissing,
                        userInfo: [NSLocalizedDescriptionKey: "Bundled 7zz not found"]
                    )))
                }
                return
            }

            let process = Process()
            task.process = process

            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe
            process.executableURL = sevenZipURL
            process.currentDirectoryURL = archiveURL.deletingLastPathComponent()

            var args = ["x", "-y", "-bsp1", archiveURL.path, "-o\(destinationURL.path)"]
            if !password.isEmpty {
                args.insert("-p\(password)", at: 1)
            }
            process.arguments = args

            if task.isCancelled {
                DispatchQueue.main.async {
                    completion(.failure(NSError(
                        domain: "ArchiveError",
                        code: ErrorCode.cancelled,
                        userInfo: [NSLocalizedDescriptionKey: "Cancelled"]
                    )))
                }
                return
            }

            var outputBuffer = ""
            var outputLog = ""
            var reportedProgress = 0.0
            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }

                outputLog += chunk
                outputBuffer += chunk.replacingOccurrences(of: "\r", with: "\n")
                self.reportSevenZipProgress(from: outputBuffer, reportedProgress: &reportedProgress, progress: progress)
                outputBuffer.removeAll(keepingCapacity: true)
            }

            do {
                try process.run()
                process.waitUntilExit()
                outputPipe.fileHandleForReading.readabilityHandler = nil

                DispatchQueue.main.async {
                    if task.isCancelled {
                        try? FileManager.default.removeItem(at: destinationURL)
                        completion(.failure(NSError(
                            domain: "ArchiveError",
                            code: ErrorCode.cancelled,
                            userInfo: [NSLocalizedDescriptionKey: "Cancelled"]
                        )))
                        return
                    }

                    progress(1.0)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if process.terminationStatus == 0 {
                            completion(.success(destinationURL))
                        } else {
                            try? FileManager.default.removeItem(at: destinationURL)
                            let passwordFailure = self.passwordFailureDescription(for: outputLog)
                            completion(.failure(NSError(
                                domain: "ArchiveError",
                                code: passwordFailure == nil ? Int(process.terminationStatus) : ErrorCode.passwordRequired,
                                userInfo: [NSLocalizedDescriptionKey: passwordFailure ?? self.failureDescription(
                                    for: "extraction",
                                    terminationStatus: process.terminationStatus,
                                    output: outputLog
                                )]
                            )))
                        }
                    }
                }
            } catch {
                outputPipe.fileHandleForReading.readabilityHandler = nil
                try? FileManager.default.removeItem(at: destinationURL)
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }

        return task
    }

    private static func normalizedExcludedPaths(_ paths: [ExcludedPath]) -> [ExcludedPath] {
        paths
            .map { exclusion -> ExcludedPath in
                let cleanPath = exclusion.relativePath
                    .replacingOccurrences(of: "\\", with: "/")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                return ExcludedPath(relativePath: cleanPath, isDirectory: exclusion.isDirectory)
            }
            .filter { !$0.relativePath.isEmpty }
    }

    /// Manual tree exclusions override `.gitignore` for the same relative path.
    private static func mergedExcludedPaths(_ manual: [ExcludedPath], _ gitignore: [ExcludedPath]) -> [ExcludedPath] {
        var byPath: [String: ExcludedPath] = [:]
        for entry in gitignore { byPath[entry.relativePath] = entry }
        for entry in manual { byPath[entry.relativePath] = entry }
        return byPath.values.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
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

    private func zipExcludePatterns(
        baseName: String,
        removeMacFiles: Bool,
        exclusions: [ExcludedPath]
    ) -> [String] {
        var patterns: [String] = []

        if removeMacFiles {
            patterns += ["*.DS_Store*", "*__MACOSX*"]
        }

        for exclusion in exclusions {
            let fullPath = "\(baseName)/\(exclusion.relativePath)"
            patterns.append(fullPath)
            if exclusion.isDirectory {
                patterns.append("\(fullPath)/*")
            }
        }

        return patterns
    }

    private func sevenZipExcludePatterns(
        baseName: String,
        removeMacFiles: Bool,
        exclusions: [ExcludedPath]
    ) -> [String] {
        var patterns: [String] = []

        if removeMacFiles {
            patterns += ["*.DS_Store", "__MACOSX"]
        }

        for exclusion in exclusions {
            let fullPath = "\(baseName)/\(exclusion.relativePath)"
            patterns.append(fullPath)
            if exclusion.isDirectory {
                patterns.append("\(fullPath)/*")
            }
        }

        return patterns
    }

    private func writeListFile(
        patterns: [String],
        in directory: URL,
        prefix: String
    ) throws -> URL {
        let listFileURL = directory.appendingPathComponent("\(prefix)-\(UUID().uuidString).txt")
        let contents = patterns.joined(separator: "\n") + "\n"
        try contents.write(to: listFileURL, atomically: true, encoding: .utf8)
        return listFileURL
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

    private func reportSevenZipProgress(
        from text: String,
        reportedProgress: inout Double,
        progress: @escaping (Double) -> Void
    ) {
        let nsText = text as NSString
        let matches = sevenZipPercentRegex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let percentString = nsText.substring(with: match.range(at: 1))
            guard let percent = Double(percentString) else { continue }

            let scaled = min(0.97, max(reportedProgress, (percent / 100.0) * 0.97))
            if scaled > reportedProgress {
                reportedProgress = scaled
                DispatchQueue.main.async { progress(scaled) }
            }
        }
    }

    private func passwordFailureDescription(for output: String) -> String? {
        let lowercasedOutput = output.lowercased()

        if lowercasedOutput.contains("wrong password") {
            return "Incorrect password. Try again."
        }

        if lowercasedOutput.contains("enter password") ||
            lowercasedOutput.contains("can not open encrypted archive") {
            return "This archive is password protected. Enter the password to extract it."
        }

        return nil
    }

    private func failureDescription(
        for operation: String,
        terminationStatus: Int32,
        output: String
    ) -> String {
        let trimmedOutput = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .last(where: { !$0.isEmpty })

        if let trimmedOutput {
            return "\(operation.capitalized) failed: \(trimmedOutput)"
        }

        return "\(operation.capitalized) failed (exit \(terminationStatus))"
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
