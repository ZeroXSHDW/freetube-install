import Foundation

enum CodeSignError: Error, LocalizedError {
    case verificationFailed(String)
    case notSigned

    var errorDescription: String? {
        switch self {
        case .verificationFailed(let msg):
            return "Code signature verification failed: \(msg)"
        case .notSigned:
            return "Application is not code-signed"
        }
    }
}

struct CodeSignHelper {
    /// Verifies the code signature of an app bundle.
    static func verify(_ appURL: URL) throws -> Bool {
        let executableURL = appURL.appendingPathComponent("Contents/MacOS/FreeTube")
        guard FileManager.default.fileExists(atPath: executableURL.path) else {
            throw CodeSignError.notSigned
        }

        let output = try ShellHelper.run("/usr/bin/codesign",
                                         arguments: ["--verify", "--deep", "--strict", appURL.path])
        // codesign --verify returns empty stdout on success
        return true
    }

    /// Checks if quarantine attribute is present on an app bundle.
    static func hasQuarantineAttribute(_ appURL: URL) -> Bool {
        return ShellHelper.runOptional("/usr/bin/xattr", arguments: ["-p", "com.apple.quarantine", appURL.path]) != nil
    }

    /// Removes quarantine attribute from an app bundle.
    static func removeQuarantine(_ appURL: URL) throws {
        try ShellHelper.run("/usr/bin/xattr", arguments: ["-dr", "com.apple.quarantine", appURL.path])
    }

    /// Gets the bundle version string from Info.plist.
    static func bundleVersion(_ appURL: URL) -> String? {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let version = plist["CFBundleShortVersionString"] as? String else {
            return nil
        }
        return version
    }
}
