import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("FreeTube macOS")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("One-command installer, menu bar app, 18 genre charts, Now Playing, favorites sync & AirPods auto-pause.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top)

                // Status cards
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                    StatusCard(
                        title: "FreeTube Version",
                        value: viewModel.currentVersionText,
                        icon: "apple.logo",
                        color: .gray
                    )
                    StatusCard(
                        title: "Latest Version",
                        value: viewModel.latestVersionText,
                        icon: "arrow.down.circle",
                        color: viewModel.needsUpdate ? .orange : .green
                    )
                    StatusCard(
                        title: "Auto-Updater",
                        value: launchAgentStatus(.autoupdate),
                        icon: "arrow.clockwise",
                        color: .blue
                    )
                    StatusCard(
                        title: "Menu Bar App",
                        value: launchAgentStatus(.bar),
                        icon: "music.note",
                        color: .purple
                    )
                }

                // Quick actions
                VStack(alignment: .leading, spacing: 12) {
                    Text("Quick Actions")
                        .font(.headline)
                    HStack(spacing: 12) {
                        Button(action: { viewModel.showingInstallView = true }) {
                            Label("Install / Update", systemImage: "arrow.down.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button(action: {
                            viewModel.playlistService.refreshCharts(showUI: true)
                        }) {
                            Label("Refresh Charts", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button(action: {
                            viewModel.showingGenres = true
                        }) {
                            Label("Open Genres", systemImage: "music.note.list")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button(action: {
                            viewModel.showingSettings = true
                        }) {
                            Label("Settings", systemImage: "gearshape")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // Log
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Activity Log")
                            .font(.headline)
                        Spacer()
                        Button("Clear") {
                            viewModel.installation.installLog.removeAll()
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                    }
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(viewModel.installation.installLog.suffix(20), id: \.self) { line in
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }

                Spacer(minLength: 40)
            }
            .padding()
        }
        .sheet(isPresented: $viewModel.showingInstallView) {
            InstallView(viewModel: InstallViewModel())
        }
        .sheet(isPresented: $viewModel.showingGenres) {
            GenresView(viewModel: GenresViewModel())
        }
        .sheet(isPresented: $viewModel.showingSettings) {
            SettingsView(viewModel: SettingsViewModel())
        }
    }

    private func launchAgentStatus(_ name: LaunchAgentName) -> String {
        if let status = viewModel.launchAgentService.agents.first(where: { $0.name == name }) {
            return status.isLoaded ? "Running" : "Stopped"
        }
        return "Unknown"
    }
}

struct StatusCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(10)
    }
}
