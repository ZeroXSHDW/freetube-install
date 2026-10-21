import SwiftUI
import AppKit

/// Native bootstrap. We avoid SwiftUI's `@main`/Entry macro (the Command Line
/// Tools toolchain ships no `SwiftUIMacros` plugin) and instead start the app
/// the classic AppKit way: a window hosting `ContentView` plus an `NSStatusItem`
/// menu bar popover hosting `MenuBarPopoverView`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenuBar()
        buildMainMenu()
        buildMainWindow()
        PowerEventsService.shared.activate()
        NowPlayingViewModel.shared.startMonitoring()
        NSApp.activate(ignoringOtherApps: true)
        // Silently check for add-on updates at launch.
        Task { await AppUpdateService.shared.check() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window?.makeKeyAndOrderFront(nil)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Main window

    private func buildMainWindow() {
        let size = NSSize(width: 1020, height: 720)
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "FreeTube · Installer & Music Add-On"
        window.minSize = NSSize(width: 960, height: 680)
        window.center()
        window.contentView = NSHostingView(rootView: ContentView())
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Menu bar (♫)

    private func buildMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "FreeTube")
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let controller = NSHostingController(rootView: MenuBarPopoverView())
        popover = NSPopover()
        popover.contentSize = NSSize(width: 330, height: 500)
        popover.behavior = .transient
        popover.contentViewController = controller
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Main menu

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "u")
        appMenu.addItem(withTitle: "Refresh Top Charts", action: #selector(refreshCharts), keyEquivalent: "r")
        appMenu.addItem(withTitle: "Check for Add-On Updates…", action: #selector(checkForAddOnUpdates), keyEquivalent: "u")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Open FreeTube.app", action: #selector(openFreeTube), keyEquivalent: "o")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit FreeTube Add-On", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func checkForUpdates() {
        UpdateService.shared.checkForUpdates(showUI: true)
    }

    @objc private func refreshCharts() {
        PlaylistService.shared.refreshCharts(showUI: true)
    }

    @objc private func openFreeTube() {
        InstallationService.shared.openFreeTube()
    }

    @objc private func checkForAddOnUpdates() {
        Task { await AppUpdateService.shared.check() }
    }
}

// Top-level entry (must live in main.swift).
let delegate = AppDelegate()
let application = NSApplication.shared
application.setActivationPolicy(.regular)
application.delegate = delegate
application.run()
