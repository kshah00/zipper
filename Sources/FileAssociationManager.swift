import Foundation
import AppKit
import UniformTypeIdentifiers
import CoreServices

enum FileAssociationManager {
    private static let archiveTypeIdentifiers = [
        "public.zip-archive",
        "com.rarlab.rar-archive",
        "org.7-zip.7-zip-archive"
    ]

    static func registerAsDefaultArchiveHandler() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        for typeIdentifier in archiveTypeIdentifiers {
            LSSetDefaultRoleHandlerForContentType(typeIdentifier as CFString, .all, bundleID as CFString)
        }
    }
}
