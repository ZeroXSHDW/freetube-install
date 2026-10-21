import SwiftUI

/// Everything beyond playback: SponsorBlock auto-skip, sleep-aware playback,
/// LaunchAgents, snapshots/backups, cleanup and the one-click Doctor.
struct ExtrasView: View {
    @ObservedObject var viewModel: ExtrasViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Super-Add-On / Extras")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Everything that makes the native app more than a wrapper: SponsorBlock, power awareness, backups and a doctor that repairs your setup.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let status = viewModel.statusLine {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.08))
                        .cornerRadius(8)
                }

                // SponsorBlock
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "forward.end")
                            .foregroundStyle(.orange)
                        Text("SponsorBlock")
                            .font(.headline)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { viewModel.sponsor.autoSkipEnabled },
                            set: { _ in viewModel.toggleAutoSkip() }
                        ))
                        .labelsHidden()
                    }
                    Text("Auto-skips sponsor, self-promo, intro/outro, filler and recap segments via sponsor.ajay.app while FreeTube plays. Skipped seconds are tracked.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        Label("\(viewModel.sponsor.totalSkippedSeconds) s", systemImage: "clock.badge.checkmark")
                            .font(.caption)
                        if let toast = viewModel.sponsor.skipToast {
                            Text(toast).font(.caption).foregroundStyle(.green)
                        }
                        Spacer()
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.08))
                .cornerRadius(10)

                // Power awareness
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "zzz")
                            .foregroundStyle(.blue)
                        Text("Sleep-aware playback")
                            .font(.headline)
                    }
                    Toggle("Pause music when the Mac sleeps", isOn: Binding(
                        get: { viewModel.power.pauseOnSleep },
                        set: { viewModel.power.pauseOnSleep = $0 }
                    ))
                    Toggle("Resume after wake (if headphones still connected)", isOn: Binding(
                        get: { viewModel.power.resumeOnWake },
                        set: { viewModel.power.resumeOnWake = $0 }
                    ))
                    if let event = viewModel.power.lastEvent {
                        Text(event).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.08))
                .cornerRadius(10)

                // LaunchAgents
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "arrow.triangle.branch")
                            .foregroundStyle(.purple)
                        Text("Background agents")
                            .font(.headline)
                    }
                    ForEach(LaunchAgentName.allCases) { agent in
                        HStack {
                            Image(systemName: agentIcon(agent))
                                .foregroundStyle(agentLoaded(agent) ? .green : .secondary)
                            Text(agent.displayName)
                                .font(.body)
                            Spacer()
                            Button(agentLoaded(agent) ? "Disable" : "Enable") {
                                viewModel.toggleAgent(agent)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.08))
                .cornerRadius(10)

                // License / Pro
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundStyle(.yellow)
                        Text("License / Pro")
                            .font(.headline)
                        Spacer()
                        Text(viewModel.license.isPro ? "PRO ✓" : "Free")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(viewModel.license.isPro ? .green : .secondary)
                    }
                    TextField("Paste license key (FT1.…)", text: $viewModel.licenseInput)
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: 8) {
                        Button("Activate") { viewModel.activateLicense() }
                            .buttonStyle(.borderedProminent)
                            .disabled(viewModel.licenseInput.isEmpty)
                        Button("Paste") { viewModel.pasteLicense() }
                            .buttonStyle(.bordered)
                        if viewModel.license.isPro {
                            Button("Remove") { viewModel.deactivateLicense() }
                                .buttonStyle(.bordered)
                        }
                        Spacer()
                        Button {
                            viewModel.openBuyPage()
                        } label: {
                            Label("Get Pro", systemImage: "cart.fill")
                        }
                        .buttonStyle(.bordered)
                        .foregroundStyle(.orange)
                    }
                    Text(viewModel.license.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.gray.opacity(0.08))
                .cornerRadius(10)

                // Self-update (the add-on itself)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.teal)
                        Text("Add-on self-update")
                            .font(.headline)
                        Spacer()
                        if viewModel.appUpdate.updateAvailable {
                            Text("v\(viewModel.appUpdate.latestVersion ?? "") available")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    HStack(spacing: 10) {
                        Button("Check for Updates") { viewModel.checkAppUpdate() }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.appUpdate.isChecking)
                        if viewModel.appUpdate.updateAvailable {
                            Button("Update Now") { viewModel.applyAppUpdate() }
                                .buttonStyle(.borderedProminent)
                                .disabled(viewModel.appUpdate.isUpdating)
                        }
                        Spacer()
                        Text("installed v\(viewModel.appUpdate.currentVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !viewModel.appUpdate.log.isEmpty {
                        Text(viewModel.appUpdate.log.last ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.08))
                .cornerRadius(10)

                // Backups & cleanup
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "archivebox")
                            .foregroundStyle(.brown)
                        Text("Backups & cleanup")
                            .font(.headline)
                    }
                    HStack(spacing: 10) {
                        Button("Backup Now") { viewModel.backupNow() }
                            .buttonStyle(.borderedProminent)
                        Button("Clean Old Logs") { viewModel.cleanup() }
                            .buttonStyle(.bordered)
                    }
                    ForEach(viewModel.backup.snapshots.prefix(5)) { snapshot in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(snapshot.name).font(.caption)
                                Text("\(snapshot.dateLabel) · \(snapshot.sizeLabel)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Restore") { viewModel.restore(snapshot) }
                                .buttonStyle(.borderless)
                            Button("Delete") { viewModel.deleteSnapshot(snapshot) }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.08))
                .cornerRadius(10)

                // Doctor
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "stethoscope")
                            .foregroundStyle(.green)
                        Text("System doctor")
                            .font(.headline)
                        Spacer()
                        Button("Run") { viewModel.runDoctor() }
                            .buttonStyle(.bordered)
                        Button("Fix Everything") { viewModel.fixEverything() }
                            .buttonStyle(.bordered)
                            .foregroundStyle(.orange)
                    }
                    ForEach(viewModel.doctor.checks) { check in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: check.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(check.ok ? .green : .orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(check.name).font(.body)
                                Text(check.detail).font(.caption).foregroundStyle(.secondary)
                                if let hint = check.fixHint {
                                    Text(hint).font(.caption2).foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.08))
                .cornerRadius(10)

                Spacer(minLength: 20)
            }
            .padding()
        }
    }

    private func agentLoaded(_ agent: LaunchAgentName) -> Bool {
        viewModel.launchAgents.agents.first { $0.name == agent }?.isLoaded ?? false
    }

    private func agentIcon(_ agent: LaunchAgentName) -> String {
        switch agent {
        case .autoupdate: return "arrow.down.circle"
        case .topmusic: return "music.note.list"
        case .bar: return "menubar.rectangle"
        case .resume: return "clock.arrow.circlepath"
        case .audiopause: return "airpodsspatialaudio"
        case .installer: return "sparkles"
        }
    }
}
