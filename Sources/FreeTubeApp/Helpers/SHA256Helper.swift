import Foundation
import CryptoKit

enum SHA256Error: Error, LocalizedError {
    case fileNotFound(URL)
    case readFailed(Error)
    case mismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "File not found: \(url.path)"
        case .readFailed(let error):
            return "Failed to read file: \(error.localizedDescription)"
        case .mismatch(let expected, let actual):
            return "SHA-256 mismatch. Expected: \(expected), Got: \(actual)"
        }
    }
}

struct SHA256Helper {
    /// Computes the SHA-256 hash of a file.
    static func hash(of fileURL: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw SHA256Error.fileNotFound(fileURL)
        }

        do {
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { handle.close() }

            var hasher = SHA256()
            while true {
                let data = handle.readData(ofLength: 1 << 20) // 1MB chunks
                if data.isEmpty { break }
                hasher.update(data: data)
            }
            return hasher.finalize().hexString
        } catch {
            throw SHA256Error.readFailed(error)
        }
    }

    /// Verifies that a file's SHA-256 matches the expected digest.
    static func verify(fileURL: URL, expectedDigest: String) throws -> Bool {
        let actual = try hash(of: fileURL)
        let normalizedExpected = expectedDigest.replacingOccurrences(of: "sha256:", with: "")
            .lowercased()
        let normalizedActual = actual.lowercased()

        if normalizedExpected != normalizedActual {
            throw SHA256Error.mismatch(expected: normalizedExpected, actual: normalizedActual)
        }
        return true
    }

    /// Computes SHA-256 of a string.
    static func hash(string: String) -> String {
        let data = Data(string.utf8)
        return SHA256.hash(data: data).hexString
    }
}

private extension SHA256.Digest {
    var hexString: String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}
