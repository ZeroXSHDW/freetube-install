import SwiftUI

struct StatusView: View {
    @ObservedObject var viewModel: StatusViewModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("System Status")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Diagnostic information about your FreeTube installation.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            Divider()

            // App Status
            VStack(alignment: .leading, spacing: 12) {
                Text("Application")
                    .font(.headline)
                if let app = InstallationService.shared.appDir.appendingPathComponent("FreeTube.app") as URL?,
                   FileManager.default.fileExists(atPath: app.path) {
                    let version = CodeSignHelper.bundleVersion(app) ?? "unknown"
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("FreeTube.app v\(version) installed at \(app.path)")
                            .font(.body)
                    }
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                        Text("FreeTube.app not found")
                            .font(.body)
                    }
                }
            }
            .padding()

            // LaunchAgents
            VStack(alignment: .leading, spacing: 12) {
                Text("LaunchAgents")
                    .font(.headline)
                ForEach(viewModel.launchAgentService.agents) { agent in
                    HStack {
                        Image(systemName: agent.isLoaded ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(agent.isLoaded ? .green : .red)
                        Text(agent.name.displayName)
                            .font(.body)
                        Spacer()
                        Text(agent.isLoaded ? "Loaded" : "Not Loaded")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(agent.isLoaded ? "Disable" : "Enable") {
                            if agent.isLoaded {
                                viewModel.launchAgentService.disable(agent.name)
                            } else {
                                viewModel.launchAgentService.enable(agent.name)
                            }
                        }
                        .buttonStyle(.borderless)
                        .buttonBorderShape(.roundedRectangle)
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding()

            // Playlists
            VStack(alignment: .leading, spacing: 12) {
                Text("Playlists")
                    .font(.headline)
                Text("\(viewModel.playlistService.playlists.count) playlists configured")
                    .font(.body)
                ForEach(viewModel.playlistService.playlists.prefix(10), id: \.id) { pl in
                    HStack {
                        Text("• \(pl.playlistName)")
                            .font(.body)
                        Spacer()
                        Text("\(pl.trackCount) tracks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if viewModel.playlistService.playlists.count > 10 {
                    Text("... and \(viewModel.playlistService.playlists.count - 10) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()

            // Config
            VStack(alignment: .leading, spacing: 12) {
                Text("Configuration")
                    .font(.headline)
                HStack {
                    Text("Backend:")
                    Spacer()
                    Text(viewModel.configService.config.backendPreference)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Invidious Fallback:")
                    Spacer()
                    Text(viewModel.configService.config.backendFallback ? "Enabled" : "Disabled")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("RSS Feeds:")
                    Spacer()
                    Text(viewModel.configService.config.useRssFeeds ? "Enabled" : "Disabled")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Default Quality:")
                    Spacer()
                    Text("\(viewModel.configService.config.defaultQuality)p")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()

            // Audio Device
            VStack(alignment: .leading, spacing: 12) {
                Text("Audio Device")
                    .font(.headline)
                if let device = viewModel.audioService.currentDevice {
                    HStack {
                        Text("Device:")
                        Spacer()
                        Text(device.name)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Headphones:")
                        Spacer()
                        Text(device.isHeadphones ? "Yes" : "No")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Built-in:")
                        Spacer()
                        Text(device.isBuiltin ? "Yes" : "No")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Audio device not detected")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()

            Spacer(minLength: 20)

            HStack {
                Button("Refresh Status") {
                    viewModel.launchAgentService.refresh()
                    viewModel.audioService.currentDevice = viewModel.audioService.getCurrentDevice()
                }
                .buttonStyle(.bordered)

                Button("Run Doctor") {
                    viewModel.runDoctor()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Close") {
                    // Close handled by parent
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 700, height: 650)
        .sheet(isPresented: $viewModel.showingDoctorOutput) {
            VStack(spacing: 0) {
                Text("Doctor Output")
                    .font(.headline)
                    .padding()
                ScrollView {
                    Text(viewModel.doctorOutput)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                HStack {
                    Spacer()
                    Button("Close") {
                        viewModel.showingDoctorOutput = false
                    }
                    .keyboardShortcut(.cancelAction)
                }
                .padding()
            }
            .frame(width: 600, height: 400)
        }
    }
}
