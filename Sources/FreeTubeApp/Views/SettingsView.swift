import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("API Backend") {
                Picker("Preferred Backend", selection: $viewModel.backendPreference) {
                    ForEach(viewModel.availableBackends, id: \.self) { backend in
                        Text(backend.capitalized).tag(backend)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Enable Invidious Fallback", isOn: $viewModel.backendFallback)
                Toggle("Enable RSS Feeds", isOn: $viewModel.useRSS)
            }

            Section("Playback") {
                Picker("Default Quality", selection: $viewModel.defaultQuality) {
                    ForEach(viewModel.availableQualities, id: \.self) { q in
                        Text("\(q)p").tag(q)
                    }
                }

                Stepper("Autoplay Interruption (\(viewModel.interruptionHours) hours)",
                        value: $viewModel.interruptionHours, in: 1...48, step: 1)
            }

            Section("General") {
                Toggle("Check for Updates", isOn: .constant(viewModel.configService.config.checkForUpdates))
                Toggle("Remember History", isOn: .constant(viewModel.configService.config.rememberHistory))
                Toggle("Expand Sidebar", isOn: .constant(viewModel.configService.config.expandSideBar))
            }

            Section("Actions") {
                Button("Save Configuration") {
                    do {
                        try viewModel.save()
                    } catch {
                        print("Save failed: \(error)")
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Reset to Defaults") {
                    viewModel.showingResetAlert = true
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 450)
        .navigationTitle("Settings")
        .alert("Reset Configuration", isPresented: $viewModel.showingResetAlert) {
            Button("Reset", role: .destructive) {
                viewModel.resetDefaults()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will reset all FreeTube settings to their default values.")
        }
    }
}
