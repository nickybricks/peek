import AppKit
import SwiftUI

enum SwitcherMode {
    case allApps    // Cmd-Tab
    case currentApp // Option-Tab
}

final class SwitcherController {
    private var eventTap: CFMachPort?
    private let state = SwitcherState()
    private var panel: NSPanel?
    private var mode: SwitcherMode = .allApps
    private(set) var isActive = false

    private enum KeyCode {
        static let tab: Int64 = 48
        static let backtick: Int64 = 50
        static let escape: Int64 = 53
        static let returnKey: Int64 = 36
        static let left: Int64 = 123
        static let right: Int64 = 124
        static let down: Int64 = 125
        static let up: Int64 = 126
    }

    private var mouseLocationAtOpen: CGPoint = .zero

    /// Most recently used windows, newest first. Drives the order in the switcher so a
    /// quick Cmd-Tab always flips back to the window you came from.
    private var mruWindowIDs: [CGWindowID] = []
    private var sessionID = 0

    private func bumpMRU(_ id: CGWindowID) {
        mruWindowIDs.removeAll { $0 == id }
        mruWindowIDs.insert(id, at: 0)
        if mruWindowIDs.count > 100 { mruWindowIDs.removeLast() }
    }

    private func sortedByMRU(_ windows: [WindowInfo]) -> [WindowInfo] {
        let rank = Dictionary(mruWindowIDs.enumerated().map { ($1, $0) },
                              uniquingKeysWith: { first, _ in first })
        return windows.enumerated().sorted { a, b in
            let ra = rank[a.element.id] ?? Int.max
            let rb = rank[b.element.id] ?? Int.max
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
    }

    func start() {
        state.commitHandler = { [weak self] index in self?.commit(index: index) }
        state.cancelHandler = { [weak self] in self?.cancel() }
        state.hoverHandler = { [weak self] index in
            guard let self, self.isActive else { return }
            // Only react once the mouse actually moved, otherwise a resting cursor
            // immediately overrides the keyboard selection when the panel opens
            let location = NSEvent.mouseLocation
            guard abs(location.x - self.mouseLocationAtOpen.x) > 10
                || abs(location.y - self.mouseLocationAtOpen.y) > 10 else { return }
            if self.state.selectedIndex != index {
                self.state.selectedIndex = index
            }
        }
        createEventTap()
    }

    // MARK: - Event tap

    private func createEventTap() {
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<SwitcherController>.fromOpaque(refcon).takeUnretainedValue()
            return controller.handle(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            // Happens while the accessibility permission is still missing — retry later
            NSLog("Peek: Event-Tap konnte nicht erstellt werden, neuer Versuch in 2s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.createEventTap()
            }
            return
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        if !isActive {
            guard type == .keyDown, keyCode == KeyCode.tab else {
                return Unmanaged.passUnretained(event)
            }
            if flags.contains(.maskCommand) && !flags.contains(.maskAlternate) {
                begin(mode: .allApps, backwards: flags.contains(.maskShift))
                return nil
            }
            if flags.contains(.maskAlternate) && !flags.contains(.maskCommand) {
                begin(mode: .currentApp, backwards: flags.contains(.maskShift))
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        // Switcher is open
        switch type {
        case .flagsChanged:
            let stillHeld = mode == .allApps
                ? flags.contains(.maskCommand)
                : flags.contains(.maskAlternate)
            if !stillHeld {
                commit(index: state.selectedIndex)
            }
            return Unmanaged.passUnretained(event)

        case .keyDown:
            switch keyCode {
            case KeyCode.tab:
                flags.contains(.maskShift) ? selectPrevious() : selectNext()
            case KeyCode.backtick:
                selectPrevious()
            case KeyCode.right:
                selectNext()
            case KeyCode.left:
                selectPrevious()
            case KeyCode.down:
                moveVertically(1)
            case KeyCode.up:
                moveVertically(-1)
            case KeyCode.returnKey:
                commit(index: state.selectedIndex)
            case KeyCode.escape:
                cancel()
            default:
                break
            }
            return nil // swallow all keys while the switcher is open

        case .keyUp:
            return nil

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    // MARK: - Lifecycle

    private func begin(mode: SwitcherMode, backwards: Bool) {
        var windows = WindowManager.listWindows()
        if mode == .currentApp {
            let frontPid = NSWorkspace.shared.frontmostApplication?.processIdentifier
            windows = windows.filter { $0.pid == frontPid }
        }
        guard !windows.isEmpty else { return }

        // Move the currently focused (frontmost) window to the head of the history, then
        // sort by history — this puts the previous window at position 2
        bumpMRU(windows[0].id)
        windows = sortedByMRU(windows)

        self.mode = mode
        isActive = true
        sessionID += 1
        mouseLocationAtOpen = NSEvent.mouseLocation
        state.windows = windows
        state.columns = columnCount(for: windows.count)
        if windows.count > 1 {
            state.selectedIndex = backwards ? windows.count - 1 : 1
        } else {
            state.selectedIndex = 0
        }

        // Show the panel only after a short delay: a quick tap switches straight
        // to the previous window without the panel ever flashing up
        let session = sessionID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, self.isActive, self.sessionID == session else { return }
            self.showPanel()
        }

        WindowManager.captureThumbnails(for: windows) { [weak self] id, image in
            guard let self, self.isActive else { return }
            if let index = self.state.windows.firstIndex(where: { $0.id == id }) {
                self.state.windows[index].thumbnail = image
            }
        }
    }

    private func commit(index: Int) {
        guard isActive else { return }
        isActive = false
        panel?.orderOut(nil)
        if state.windows.indices.contains(index) {
            let window = state.windows[index]
            bumpMRU(window.id)
            WindowManager.raise(window)
        }
        state.windows = []
    }

    private func cancel() {
        guard isActive else { return }
        isActive = false
        panel?.orderOut(nil)
        state.windows = []
    }

    // MARK: - Selection

    private func selectNext() {
        guard !state.windows.isEmpty else { return }
        state.selectedIndex = (state.selectedIndex + 1) % state.windows.count
    }

    private func selectPrevious() {
        guard !state.windows.isEmpty else { return }
        state.selectedIndex = (state.selectedIndex - 1 + state.windows.count) % state.windows.count
    }

    private func moveVertically(_ direction: Int) {
        let target = state.selectedIndex + direction * state.columns
        if state.windows.indices.contains(target) {
            state.selectedIndex = target
        }
    }

    private func columnCount(for count: Int) -> Int {
        let usableWidth = (NSScreen.main?.visibleFrame.width ?? 1440) - 120
        let cellWidth: CGFloat = 288 // cell + spacing
        return max(1, min(count, Int(usableWidth / cellWidth)))
    }

    // MARK: - Panel

    private func showPanel() {
        guard let screen = NSScreen.main else { return }
        if panel == nil {
            let p = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
            p.level = .statusBar
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.acceptsMouseMovedEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel = p
        }
        guard let panel else { return }

        // Fresh hosting view so fittingSize measures the current window list
        let hosting = NSHostingView(rootView: SwitcherView(state: state))
        panel.contentView = hosting
        var size = hosting.fittingSize
        size.width = min(size.width, screen.visibleFrame.width - 40)
        size.height = min(size.height, screen.visibleFrame.height - 40)
        let origin = CGPoint(x: screen.frame.midX - size.width / 2,
                             y: screen.frame.midY - size.height / 2)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }
}
