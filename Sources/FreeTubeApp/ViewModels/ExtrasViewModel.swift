import Foundation
import SwiftUI
import AppKit

@MainActor
final class ExtrasViewModel: ObservableObject {
    let sponsor = SponsorBlockService.shared
    let power = PowerEventsService.shared
    let backup = BackupService.shared
    let doctor = DoctorService.shared
    let launchAgents = LaunchAgentService.shared
    let appUpdate = AppUpdateService.shared
    let license = LicenseService.shared

    @Published var statusLine: String?
    @Published var confirmation: String?
    @Published var licenseInput = ""

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

    // MARK: - Self-update

    func checkAppUpdate() {
        statusLine = "Checking for add-on updates…"
        Task {
            await appUpdate.check()
            statusLine = appUpdate.updateAvailable
                ? "Add-on update available: \(appUpdate.latestVersion ?? "")"
                : "Add-on is up to date (v\(appUpdate.currentVersion))"
        }
    }

    func applyAppUpdate() {
        statusLine = "Updating the add-on…"
        Task {
            await appUpdate.update()
            if let error = appUpdate.lastError {
                statusLine = "Update failed: \(error)"
            }
        }
    }

    // MARK: - License

    func activateLicense() {
        if license.activate(licenseInput) {
            statusLine = "License activated — \(license.statusText)"
        } else {
            statusLine = "Invalid license key"
        }
    }

    func deactivateLicense() {
        license.deactivate()
        licenseInput = ""
        statusLine = "License removed"
    }

    /// Opens the buy page in the default browser.
    func openBuyPage() {
        if let url = URL(string: "https://zeroxshdw.github.io/freetube-install/buy.html") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Pre-fills the license field from the clipboard and auto-activates a
    /// pasted `FT1.…` key.
    func pasteLicense() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        guard !text.isEmpty else {
            statusLine = "Clipboard is empty — copy the license key first"
            return
        }
        licenseInput = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if licenseInput.hasPrefix("FT1.") {
            activateLicense()
        } else {
            statusLine = "Pasted — tap Activate to verify"
        }
    }
}
