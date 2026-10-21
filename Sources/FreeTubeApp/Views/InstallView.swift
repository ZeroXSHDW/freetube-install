import SwiftUI

struct InstallView: View {
    @ObservedObject var viewModel: InstallViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Install FreeTube")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Download, verify, and install the official FreeTube DMG release with SHA-256 checksum verification.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Version info
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Current Version:")
                    Spacer()
                    Text(viewModel.installation.currentVersion ?? "Not installed")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Latest Version:")
                    Spacer()
                    Text(viewModel.installation.latestVersion ?? "Checking...")
                        .foregroundStyle(viewModel.installation.isUpToDate ? .green : .orange)
                }
                if viewModel.installation.isUpToDate && viewModel.installation.currentVersion != nil {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("You are on the latest version.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.08))
            .cornerRadius(10)

            // Progress
            if viewModel.installation.isInstalling {
                VStack(spacing: 12) {
                    ProgressView(value: viewModel.installation.downloadProgress.fraction)
                        .frame(maxWidth: .infinity)
                    Text("\(viewModel.installation.downloadProgress.percentage)%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(viewModel.installation.downloadProgress.readableDownloaded + " / " + viewModel.installation.downloadProgress.readableTotal)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Log
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Install Log")
                        .font(.headline)
                    Spacer()
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(viewModel.installation.installLog.suffix(30), id: \.self) { line in
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

            // Error
            if let error = viewModel.installation.lastError {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(error.errorDescription ?? "Unknown error")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }

            // Actions
            HStack(spacing: 12) {
                Button("Check for Updates") {
                    viewModel.checkUpdates()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.installation.isInstalling)

                Button(action: {
                    if viewModel.installation.currentVersion == nil {
                        viewModel.install()
                    } else {
                        viewModel.showingForceInstall = true
                    }
                }) {
                    Text(viewModel.installButtonText)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.installation.isInstalling)

                Button("Open FreeTube.app") {
                    viewModel.installation.openFreeTube()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.installation.currentVersion == nil)

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .frame(width: 600, height: 650)
        .padding()
        .confirmationDialog("Force Reinstall", isPresented: $viewModel.showingForceInstall, titleVisibility: .visible) {
            Button("Force Reinstall", role: .destructive) {
                viewModel.forceInstall()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will download and reinstall FreeTube even if you already have the latest version.")
        }
    }
}
