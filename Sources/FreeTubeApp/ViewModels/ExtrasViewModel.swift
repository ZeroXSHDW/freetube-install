import Foundation
import SwiftUI

@MainActor
final class ExtrasViewModel: ObservableObject {
    let sponsor = SponsorBlockService.shared
    let power = PowerEventsService.shared
    let backup = BackupService.shared
    let doctor = DoctorService.shared
    let launchAgents = LaunchAgentService.shared

    @Published var statusLine: String?
    @Published var confirmation: String?

    // MARK: - SponsorBlock

    func toggleAutoSkip() {
        sponsor.autoSkipEnabled.toggle()
        statusLine = sponsor.autoSkipEnabled ? "SponsorBlock auto-skip enabled" : "SponsorBlock auto-skip off"
    }

    // MARK: - Doctor

    func runDoctor() {
        statusLine = "Running doctor…"
        Task {
            await doctor.run()
            let failures = doctor.checks.filter { !$0.ok }.count
            statusLine = failures == 0 ? "Doctor: all checks passed ✅" : "Doctor: \(failures) issue(s) found"
        }
    }

    func fixEverything() {
        statusLine = "Repairing…"
        Task {
            await doctor.fixEverything()
            statusLine = "Repairs applied — re-running doctor"
        }
    }

    // MARK: - Backup

    func backupNow() {
        do {
            let snapshot = try backup.createBackup()
            statusLine = "Backup created: \(snapshot.name) (\(snapshot.sizeLabel))"
        } catch {
            statusLine = "Backup failed: \(error.localizedDescription)"
        }
    }

    func restore(_ snapshot: BackupService.Snapshot) {
        do {
            _ = try? ShellHelper.run("/usr/bin/osascript", arguments: ["-e", "tell application \"FreeTube\" to quit"])
            try backup.restore(snapshot)
            statusLine = "Restored \(snapshot.name). Launch FreeTube to pick up the restored data."
        } catch {
            statusLine = "Restore failed: \(error.localizedDescription)"
        }
    }

    func deleteSnapshot(_ snapshot: BackupService.Snapshot) {
        backup.delete(snapshot)
        statusLine = "Deleted \(snapshot.name)"
    }

    func cleanup() {
        let logs = backup.cleanupOldLogs()
        let tmp = backup.cleanupTempJT()
        statusLine = "Cleaned \(logs) old logs and \(tmp) temp files"
    }

    // MARK: - LaunchAgents

    func toggleAgent(_ name: LaunchAgentName) {
        launchAgents.toggle(name)
        statusLine = "Toggled \(name.displayName)"
    }
}
