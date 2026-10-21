import Foundation

/// Snapshot backups of every FreeTube database + the add-on's own JSON files,
/// plus log cleanup helpers (replacing freetube-backup.sh / freetube-cleanup.sh).
final class BackupService: ObservableObject {
    static let shared = BackupService()

    struct Snapshot: Identifiable, Equatable {
        let name: String
        let path: URL
        let created: Date
        let totalBytes: Int64

        var id: String { name }
        var sizeLabel: String { ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file) }
        var dateLabel: String { DateFormatter.localizedString(from: created, dateStyle: .medium, timeStyle: .short) }
    }

    private let supportDir: URL
    private let backupsDir: URL
    private let keepCount = 10

    private static let backupFiles: Set<String> = [
        "playlists.db", "history.db", "subscriptions.db", "profiles.db",
        "settings.db", "top-charts.json", "favorites.json", "watchLater.json",
        "last-genre.json"
    ]

    @Published var snapshots: [Snapshot] = []
    @Published var isBusy = false

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        supportDir = home.appendingPathComponent("Library/Application Support/FreeTube")
        backupsDir = home.appendingPathComponent("Library/Application Support/FreeTubeBackups")
        createDirsIfNeeded()
        reload()
    }

    private func createDirsIfNeeded() {
        try? FileManager.default.createDirectory(at: backupsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    }

    func reload() {
        createDirsIfNeeded()
        var list: [Snapshot] = []
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: backupsDir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else {
            snapshots = []
            return
        }
        for item in entries where item.hasDirectoryPath && item.lastPathComponent.hasPrefix("backup-") {
            var total: Int64 = 0
            if let dirEnum = fm.enumerator(at: item, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let file as URL in dirEnum {
                    if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        total += Int64(size)
                    }
                }
            }
            let created = (try? item.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            list.append(Snapshot(name: item.lastPathComponent, path: item, created: created, totalBytes: total))
        }
        snapshots = list.sorted { $0.created > $1.created }
    }

    @discardableResult
    func createBackup() throws -> Snapshot {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let snapshotDir = backupsDir.appendingPathComponent("backup-\(formatter.string(from: Date()))")

        try FileManager.default.createDirectory(at: snapshotDir, withIntermediateDirectories: true)
        var copied = 0
        for name in Self.backupFiles {
            let source = supportDir.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            try FileManager.default.copyItem(at: source, to: snapshotDir.appendingPathComponent(name))
            copied += 1
        }
        try "FreeTube backup — \(copied) files copied.\nCreated \(Date())".write(
            to: snapshotDir.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)

        rotate()
        reload()
        guard let snapshot = snapshots.first else {
            throw NSError(domain: "BackupService", code: 10,
                          userInfo: [NSLocalizedDescriptionKey: "Snapshot could not be enumerated"])
        }
        return snapshot
    }

    /// Restores a snapshot by copying its DB files back over the live ones.
    func restore(_ snapshot: Snapshot) throws {
        let fm = FileManager.default
        for name in Self.backupFiles {
            let source = snapshot.path.appendingPathComponent(name)
            guard fm.fileExists(atPath: source.path) else { continue }
            let dest = supportDir.appendingPathComponent(name)
            try? fm.removeItem(at: dest)
            try fm.copyItem(at: source, to: dest)
        }
    }

    func delete(_ snapshot: Snapshot) {
        try? FileManager.default.removeItem(at: snapshot.path)
        reload()
    }

    /// Keeps only the newest `keepCount` snapshots.
    private func rotate() {
        let fm = FileManager.default
        let all = (try? fm.contentsOfDirectory(at: backupsDir, includingPropertiesForKeys: nil))?
            .filter { $0.hasDirectoryPath && $0.lastPathComponent.hasPrefix("backup-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent } ?? []
        guard all.count > keepCount else { return }
        for old in all.dropFirst(keepCount) {
            try? fm.removeItem(at: old)
        }
    }

    // MARK: - Cleanup (log rotation / temp files)

    /// Deletes FreeTube-related logs older than the given days; returns count.
    @discardableResult
    func cleanupOldLogs(days: Int = 14) -> Int {
        let fm = FileManager.default
        let logsDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs")
        guard let entries = try? fm.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return 0
        }
        let cutoff = Date().addingTimeInterval(-Double(days) * 24 * 3600)
        var removed = 0
        for item in entries where item.lastPathComponent.lowercased().contains("freetube") {
            if let modified = try? item.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               modified < cutoff {
                try? fm.removeItem(at: item)
                removed += 1
            }
        }
        return removed
    }

    /// Removes stale queued DMG files in /tmp older than a day.
    @discardableResult
    func cleanupTempJT() -> Int {
        let fm = FileManager.default
        let tmp = FileManager.default.temporaryDirectory
        guard let entries = try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return 0
        }
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        var removed = 0
        for item in entries where item.lastPathComponent.contains("freetube") {
            if let modified = try? item.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               modified < cutoff {
                try? fm.removeItem(at: item)
                removed += 1
            }
        }
        return removed
    }
}
