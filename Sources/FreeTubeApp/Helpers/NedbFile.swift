import Foundation

/// FreeTube stores its data (playlists.db, history.db, subscriptions.db,
/// profiles.db, settings.db) in nedb-style JSON-lines files.
/// This helper reads and appends to those safely.
enum NedbFile {

    /// Parses a nedb JSON-lines file, applying deletions and keeping the last
    /// write of every document (same semantics the app itself uses).
    static func documents(at url: URL) -> [NedbDocument] {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var order: [String] = []
        var docs: [String: [String: Any]] = [:]

        for line in raw.split(separator: "\n") {
            let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty,
                  let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let id = obj["_id"] as? String else { continue }

            if (obj["$$deleted"] as? Bool) == true || (obj["deleted"] as? Bool) == true {
                if docs[id] != nil {
                    docs.removeValue(forKey: id)
                    order.removeAll { $0 == id }
                }
                continue
            }
            if docs[id] == nil { order.append(id) }
            docs[id] = obj
        }

        return order.compactMap { id in docs[id].map { NedbDocument(id: id, data: $0) } }
    }

    /// Appends one JSON document line to the database.
    static func append(_ doc: [String: Any], to url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
        }
        let data = try JSONSerialization.data(withJSONObject: doc)
        let delimiter = Data("\n".utf8)

        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.write(delimiter)
            try? handle.close()
        } else {
            try (data + delimiter).write(to: url, options: .atomic)
        }
    }

    /// Replaces the whole database with the provided JSON-lines content.
    /// Only safe while FreeTube is closed.
    static func replace(lines: [String], at url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}

/// A single document from a nedb file.
struct NedbDocument {
    let id: String
    let data: [String: Any]
}

extension NedbDocument {
    func int64Value(_ key: String) -> Int64? {
        data[key] as? Int64 ?? (data[key] as? Int).map { Int64($0) }
    }

    func stringValue(_ key: String) -> String? {
        data[key] as? String
    }

    func doubleValue(_ key: String) -> Double? {
        data[key] as? Double ?? (data[key] as? Int).map { Double($0) }
    }
}
