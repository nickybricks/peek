import AppKit
import ApplicationServices
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let controller = SwitcherController()
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        registerAsLoginItem()

        // Screen recording is required for window thumbnails and titles
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }

        // Accessibility is required for the keyboard tap and for raising windows
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            controller.start()
        } else {
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                if AXIsProcessTrusted() {
                    timer.invalidate()
                    self?.permissionTimer = nil
                    self?.controller.start()
                }
            }
        }
    }

    /// Launches the app at every login from now on — but only the installed copy
    /// in /Applications, never one running out of the build folder.
    private func registerAsLoginItem() {
        guard Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        if SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "Peek")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(header("Peek"))
        menu.addItem(caption("⌘⇥   All windows"))
        menu.addItem(caption("⌥⇥   Windows of the current app"))
        menu.addItem(caption("Tap to switch back, hold to choose."))
        menu.addItem(.separator())

        if !AXIsProcessTrusted() {
            let warning = NSMenuItem(title: "⚠︎  Allow Accessibility to enable shortcuts",
                                     action: #selector(openAccessibilitySettings), keyEquivalent: "")
            warning.target = self
            menu.addItem(warning)
            menu.addItem(.separator())
        } else if !CGPreflightScreenCaptureAccess() {
            let warning = NSMenuItem(title: "⚠︎  Allow Screen Recording to see previews",
                                     action: #selector(openScreenRecordingSettings), keyEquivalent: "")
            warning.target = self
            menu.addItem(warning)
            menu.addItem(.separator())
        }

        let launchItem = NSMenuItem(title: "Start Peek at login",
                                    action: #selector(toggleLoginItem), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchItem)

        let quit = NSMenuItem(title: "Quit Peek", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func header(_ text: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        ])
        item.isEnabled = false
        return item
    }

    private func caption(_ text: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        item.isEnabled = false
        return item
    }

    // MARK: - Actions

    @objc private func openAccessibilitySettings() {
        openSettings("Privacy_Accessibility")
    }

    @objc private func openScreenRecordingSettings() {
        openSettings("Privacy_ScreenCapture")
    }

    private func openSettings(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleLoginItem() {
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        } else {
            try? SMAppService.mainApp.register()
        }
    }

    /// Quitting hides the menu bar icon, so make sure the way back is obvious first.
    @objc private func quit() {
        let alert = NSAlert()
        alert.messageText = "Quit Peek?"
        alert.informativeText = "⌘⇥ goes back to the standard macOS app switcher.\n\nTo start Peek again, open it from Applications or Spotlight."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    // Rebuild on open so permission state and the login-item checkmark are always current
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(menu)
    }
}
