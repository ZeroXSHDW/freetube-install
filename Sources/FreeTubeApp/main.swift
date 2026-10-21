import SwiftUI

@main
struct FreeTubeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandMenu("FreeTube") {
                Button("Check for Updates…") {
                    UpdateService.shared.checkForUpdates(showUI: true)
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])

                Button("Refresh Top Charts") {
                    PlaylistService.shared.refreshCharts(showUI: true)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Divider()

                Button("Open FreeTube.app") {
                    InstallationService.shared.openFreeTube()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Quit Installer") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: [.command])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure app runs as accessory (menu bar style optional)
        NSApplication.shared.setActivationPolicy(.regular)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return true
    }
}
