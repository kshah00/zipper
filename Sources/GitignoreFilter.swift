import Foundation

/// Evaluates `.gitignore` rules under a root directory for paths relative to that root.
/// Approximates common gitignore behavior: per-file last matching rule wins, then directory propagation.
enum GitignoreFilter {

    struct IgnoredEntry {
        let relativePath: String
        let isDirectory: Bool
    }

    static func containsGitignoreFile(under rootURL: URL) -> Bool {
        let fm = FileManager.default
        var isRootDir: ObjCBool = false
        guard fm.fileExists(atPath: rootURL.path, isDirectory: &isRootDir), isRootDir.boolValue else {
            return fm.fileExists(atPath: rootURL.appendingPathComponent(".gitignore").path)
        }
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsPackageDescendants]
        ) else {
            return false
        }
        for case let itemURL as URL in enumerator {
            if itemURL.lastPathComponent == ".gitignore" { return true }
        }
        return false
    }

    static func ignoredEntries(relativeTo rootURL: URL) -> [IgnoredEntry] {
        let fm = FileManager.default
        var isRootDir: ObjCBool = false
        guard fm.fileExists(atPath: rootURL.path, isDirectory: &isRootDir), isRootDir.boolValue else {
            return []
        }

        let rootPath = rootURL.path

        guard let scan = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        var ignoreFileURLs: [URL] = []
        for case let itemURL as URL in scan where itemURL.lastPathComponent == ".gitignore" {
            ignoreFileURLs.append(itemURL)
        }

        ignoreFileURLs.sort {
            let da = depth(of: $0.deletingLastPathComponent().path, root: rootPath)
            let db = depth(of: $1.deletingLastPathComponent().path, root: rootPath)
            if da != db { return da < db }
            return $0.path < $1.path
        }

        var orderedRules: [(scopePrefix: String, rule: IgnoreRule)] = []
        for ignoreURL in ignoreFileURLs {
            let parentPath = ignoreURL.deletingLastPathComponent().path
            guard parentPath.hasPrefix(rootPath) else { continue }
            let scopePrefix: String
            if parentPath == rootPath {
                scopePrefix = ""
            } else {
                scopePrefix = parentPath.replacingOccurrences(of: rootPath + "/", with: "")
            }
            let raw = (try? String(contentsOf: ignoreURL, encoding: .utf8)) ?? ""
            for rule in parseLines(raw) {
                orderedRules.append((scopePrefix: scopePrefix, rule: rule))
            }
        }

        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        var entries: [(rel: String, isDirectory: Bool)] = []
        for case let itemURL as URL in enumerator {
            guard let rel = relativePath(from: rootPath, to: itemURL.path), !rel.isEmpty else { continue }
            if rel == ".git" || rel.hasPrefix(".git/") { continue }
            let values = try? itemURL.resourceValues(forKeys: [.isDirectoryKey])
            let isDir = values?.isDirectory ?? false
            entries.append((rel, isDir))
        }

        var isDirByPath: [String: Bool] = [:]
        for e in entries {
            isDirByPath[e.rel] = e.isDirectory
        }

        entries.sort { depthString($0.rel) < depthString($1.rel) }

        enum Effect {
            case ignore
            case include
        }

        var lastEffect: [String: Effect] = [:]

        for (rel, isDir) in entries {
            var winner: Effect?
            for pair in orderedRules {
                let scope = pair.scopePrefix
                if !scope.isEmpty {
                    if rel != scope && !rel.hasPrefix(scope + "/") {
                        continue
                    }
                }
                let local: String
                if scope.isEmpty {
                    local = rel
                } else if rel == scope {
                    local = ""
                } else {
                    local = String(rel.dropFirst(scope.count + 1))
                }
                if pair.rule.matches(localPath: local, isDirectory: isDir) {
                    winner = pair.rule.negated ? .include : .ignore
                }
            }
            if let winner {
                lastEffect[rel] = winner
            }
        }

        func isExplicitlyIncluded(_ rel: String) -> Bool {
            if lastEffect[rel] == .include { return true }
            var prefix = rel
            while let slash = prefix.lastIndex(of: "/") {
                prefix = String(prefix[..<slash])
                if lastEffect[prefix] == .include {
                    return rel == prefix || rel.hasPrefix(prefix + "/")
                }
            }
            return false
        }

        func isIgnoredByAncestor(_ rel: String) -> Bool {
            var prefix = rel
            while let slash = prefix.lastIndex(of: "/") {
                prefix = String(prefix[..<slash])
                if lastEffect[prefix] == .ignore, isDirByPath[prefix] == true {
                    return true
                }
            }
            return false
        }

        var excluded: Set<String> = []
        for (rel, _) in entries {
            if isExplicitlyIncluded(rel) { continue }
            if lastEffect[rel] == .ignore {
                excluded.insert(rel)
                continue
            }
            if isIgnoredByAncestor(rel) {
                excluded.insert(rel)
            }
        }

        return excluded.map { IgnoredEntry(relativePath: $0, isDirectory: isDirByPath[$0] ?? false) }
            .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    private static func depth(of path: String, root: String) -> Int {
        guard path.hasPrefix(root) else { return 0 }
        if path == root { return 0 }
        let rel = path.replacingOccurrences(of: root + "/", with: "")
        return depthString(rel)
    }

    private static func depthString(_ rel: String) -> Int {
        rel.split(separator: "/").count
    }

    private static func relativePath(from root: String, to path: String) -> String? {
        guard path.hasPrefix(root) else { return nil }
        if path == root { return "" }
        return path.replacingOccurrences(of: root + "/", with: "")
    }

    private struct IgnoreRule {
        let pattern: String
        let anchored: Bool
        let directoryOnly: Bool
        let negated: Bool

        func matches(localPath: String, isDirectory: Bool) -> Bool {
            if directoryOnly && !isDirectory { return false }

            let path = normalizeSlashes(localPath)
            let pat = normalizeSlashes(pattern)
            guard !pat.isEmpty else {
                return path.isEmpty
            }

            if anchored {
                return matchAnchored(pattern: pat, path: path, isDirectory: isDirectory)
            }
            return matchUnanchored(pattern: pat, path: path, isDirectory: isDirectory)
        }

        private func matchAnchored(pattern: String, path: String, isDirectory: Bool) -> Bool {
            pathMatches(
                patternSegments: pattern.split(separator: "/").map(String.init),
                pathSegments: path.split(separator: "/").map(String.init),
                isDirectory: isDirectory
            )
        }

        private func matchUnanchored(pattern: String, path: String, isDirectory: Bool) -> Bool {
            let pathSegments = path.split(separator: "/").map(String.init)
            let patSegs = pattern.split(separator: "/").map(String.init)
            for start in pathSegments.indices {
                let suffix = Array(pathSegments[start...])
                if pathMatches(patternSegments: patSegs, pathSegments: suffix, isDirectory: isDirectory) {
                    return true
                }
            }
            return false
        }

        private func pathMatches(patternSegments: [String], pathSegments: [String], isDirectory: Bool) -> Bool {
            if patternSegments.contains("**") {
                return matchDoubleStar(patternSegments: patternSegments, pathSegments: pathSegments, isDirectory: isDirectory)
            }
            if patternSegments.count != pathSegments.count { return false }
            for (i, ps) in patternSegments.enumerated() {
                let last = i == patternSegments.count - 1
                if !globMatch(pattern: ps, string: pathSegments[i], isLastPatternSegment: last, pathIsDirectory: isDirectory) {
                    return false
                }
            }
            return true
        }

        private func matchDoubleStar(patternSegments: [String], pathSegments: [String], isDirectory: Bool) -> Bool {
            guard let starIdx = patternSegments.firstIndex(of: "**") else { return false }
            let prefix = Array(patternSegments[..<starIdx])
            let suffix = Array(patternSegments[(starIdx + 1)...])

            if pathSegments.count < prefix.count + suffix.count { return false }

            for i in prefix.indices {
                if !globMatch(pattern: prefix[i], string: pathSegments[i], isLastPatternSegment: false, pathIsDirectory: true) {
                    return false
                }
            }

            if suffix.isEmpty {
                return pathSegments.count >= prefix.count
            }

            let sufLen = suffix.count
            for start in prefix.count...(pathSegments.count - sufLen) {
                var ok = true
                for j in suffix.indices {
                    let idx = start + j
                    let isLast = idx == pathSegments.count - 1
                    if !globMatch(pattern: suffix[j], string: pathSegments[idx], isLastPatternSegment: isLast, pathIsDirectory: isDirectory) {
                        ok = false
                        break
                    }
                }
                if ok { return true }
            }
            return false
        }

        private func globMatch(pattern: String, string: String, isLastPatternSegment: Bool, pathIsDirectory: Bool) -> Bool {
            if pattern == "**" { return true }
            if pattern.hasPrefix("*.") {
                let ext = String(pattern.dropFirst(1))
                if ext.rangeOfCharacter(from: CharacterSet(charactersIn: "*?[")) == nil {
                    if string.hasSuffix(ext) { return true }
                }
            }
            _ = isLastPatternSegment
            _ = pathIsDirectory
            return Glob.pathNameMatch(pattern: Array(pattern), string: Array(string))
        }
    }

    private static func parseLines(_ contents: String) -> [IgnoreRule] {
        var rules: [IgnoreRule] = []
        for var line in contents.components(separatedBy: .newlines) {
            if let hash = line.firstIndex(of: "#") {
                line = String(line[..<hash])
            }
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            var negated = false
            if line.first == "!" {
                negated = true
                line.removeFirst()
                line = line.trimmingCharacters(in: .whitespaces)
                if line.isEmpty { continue }
            }

            var directoryOnly = false
            if line.hasSuffix("/") {
                directoryOnly = true
                line.removeLast()
                line = line.trimmingCharacters(in: .whitespaces)
            }
            if line.isEmpty { continue }

            var anchored = false
            if line.first == "/" {
                anchored = true
                line.removeFirst()
                line = line.trimmingCharacters(in: .whitespaces)
            } else if line.contains("/") {
                anchored = true
            }
            if line.isEmpty { continue }

            let patternBody = normalizeSlashes(line)
            rules.append(IgnoreRule(pattern: patternBody, anchored: anchored, directoryOnly: directoryOnly, negated: negated))
        }
        return rules
    }

    private static func normalizeSlashes(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .filter { !$0.isEmpty }
            .joined(separator: "/")
    }

    private enum Glob {
        static func pathNameMatch(pattern: [Character], string: [Character]) -> Bool {
            match(pattern, string, 0, 0)
        }

        private static func match(_ p: [Character], _ s: [Character], _ i: Int, _ j: Int) -> Bool {
            if i == p.count {
                return j == s.count
            }
            if p[i] == "*" {
                if match(p, s, i + 1, j) { return true }
                if j < s.count, s[j] != "/" {
                    return match(p, s, i, j + 1)
                }
                return false
            }
            if j == s.count {
                return false
            }
            if p[i] == "?" {
                if s[j] == "/" { return false }
                return match(p, s, i + 1, j + 1)
            }
            if p[i] == "[" {
                var k = i + 1
                while k < p.count, p[k] != "]" {
                    k += 1
                }
                guard k < p.count else { return false }
                let inner = String(p[(i + 1)..<k])
                if s[j] == "/" { return false }
                if !charClass(inner, matches: s[j]) {
                    return false
                }
                return match(p, s, k + 1, j + 1)
            }
            if p[i] == s[j] {
                return match(p, s, i + 1, j + 1)
            }
            return false
        }

        private static func charClass(_ inner: String, matches char: Character) -> Bool {
            var body = inner
            var negated = false
            if body.first == "!" || body.first == "^" {
                negated = true
                body.removeFirst()
            }
            let hit = body.contains(char)
            return negated ? !hit : hit
        }
    }
}
