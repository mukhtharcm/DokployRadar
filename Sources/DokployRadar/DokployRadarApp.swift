import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let preferences = AppPreferences()
    private lazy var store = MonitorStore(preferences: preferences)
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePopover()
        store.startMonitoring()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stopMonitoring()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "dot.radiowaves.left.and.right",
            accessibilityDescription: "Dokploy Radar"
        )
        item.button?.image?.isTemplate = true
        item.button?.imagePosition = .imageOnly
        item.button?.action = #selector(togglePopover(_:))
        item.button?.target = self
        statusItem = item
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: MainMenuView(
                store: store,
                preferences: preferences,
                onOpenApp: { [weak self] in
                    self?.openMainWindowFromPopover()
                },
                onOpenSettings: { [weak self] in
                    self?.openSettingsWindowFromPopover()
                }
            )
        )
    }

    @objc
    private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button else {
            return
        }

        if popover.isShown {
            popover.performClose(sender)
            return
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func openMainWindowFromPopover() {
        popover.performClose(nil)
        showMainWindow()
    }

    private func openSettingsWindowFromPopover() {
        popover.performClose(nil)
        showSettingsWindow()
    }

    private func showMainWindow() {
        if mainWindow == nil {
            mainWindow = makeMainWindow()
        }

        guard let mainWindow else {
            return
        }

        setFullAppVisibility(isVisible: true)
        NSApp.activate(ignoringOtherApps: true)
        mainWindow.makeKeyAndOrderFront(nil)
    }

    private func showSettingsWindow() {
        if settingsWindow == nil {
            settingsWindow = makeSettingsWindow()
        }

        guard let settingsWindow else {
            return
        }

        setFullAppVisibility(isVisible: true)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow.makeKeyAndOrderFront(nil)
    }

    private func makeMainWindow() -> NSWindow {
        let rootView = MainMenuView(
            store: store,
            preferences: preferences,
            preferredWidth: 980,
            fillsWindow: true,
            showsQuitButton: false,
            onOpenSettings: { [weak self] in
                self?.showSettingsWindow()
            }
        )

        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Dokploy Radar"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.setContentSize(NSSize(width: 1120, height: 720))
        window.contentMinSize = NSSize(width: 920, height: 560)
        window.center()
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("DokployRadarMainWindow")
        window.delegate = self
        return window
    }

    private func makeSettingsWindow() -> NSWindow {
        let hostingController = NSHostingController(
            rootView: PreferencesView(preferences: preferences)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 520, height: 480))
        window.contentMinSize = NSSize(width: 520, height: 440)
        window.center()
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("DokployRadarSettingsWindow")
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }

        if window === mainWindow || window === settingsWindow {
            updateAppVisibilityAfterClosing(window)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else {
            return false
        }

        showMainWindow()
        return true
    }

    private func setFullAppVisibility(isVisible: Bool) {
        let targetPolicy: NSApplication.ActivationPolicy = isVisible ? .regular : .accessory
        guard NSApp.activationPolicy() != targetPolicy else {
            return
        }

        NSApp.setActivationPolicy(targetPolicy)
        statusItem?.isVisible = true
    }

    private func updateAppVisibilityAfterClosing(_ closingWindow: NSWindow) {
        let hasVisibleManagedWindow =
            (mainWindow != closingWindow && mainWindow?.isVisible == true)
            || (settingsWindow != closingWindow && settingsWindow?.isVisible == true)
        setFullAppVisibility(isVisible: hasVisibleManagedWindow)
    }
}

@main
struct DokployRadarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
