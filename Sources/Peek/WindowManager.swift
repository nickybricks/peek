import AppKit
import ApplicationServices
import ScreenCaptureKit

struct WindowInfo: Identifiable {
    let id: CGWindowID
    let pid: pid_t
    let appName: String
    let title: String
    let frame: CGRect
    let appIcon: NSImage?
    var thumbnail: CGImage?
}

// Private API: maps an AXUIElement window to its CGWindowID (same approach as AltTab/Rectangle)
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

enum WindowManager {

    /// Normal windows across all Spaces: visible ones first (frontmost first), then other desktops.
    static func listWindows() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        // Only .optionOnScreenOnly guarantees z-order (frontmost first); with .optionAll
        // the order is undefined, so query it separately here
        let zOrderedIDs: [CGWindowID] = (CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]])?
            .compactMap { $0[kCGWindowNumber as String] as? UInt32 } ?? []
        let zRank = Dictionary(zOrderedIDs.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let myPid = getpid()
        var onscreen: [WindowInfo] = []
        var offscreen: [WindowInfo] = []
        for entry in list {
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let windowID = entry[kCGWindowNumber as String] as? UInt32,
                  let pid = entry[kCGWindowOwnerPID as String] as? Int32,
                  pid != myPid,
                  let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat],
                  let app = NSRunningApplication(processIdentifier: pid),
                  app.activationPolicy == .regular
            else { continue }

            if let alpha = entry[kCGWindowAlpha as String] as? Double, alpha == 0 { continue }

            let frame = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0,
                               width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
            // Skip tiny helper windows (popups, status bar leftovers)
            if frame.width < 80 || frame.height < 50 { continue }

            let title = entry[kCGWindowName as String] as? String ?? ""
            let isOnscreen = entry[kCGWindowIsOnscreen as String] as? Bool ?? false
            // Offscreen windows without a title are almost always app-internal helpers
            if !isOnscreen && title.isEmpty { continue }

            let info = WindowInfo(id: windowID, pid: pid,
                                  appName: app.localizedName ?? (entry[kCGWindowOwnerName as String] as? String ?? ""),
                                  title: title, frame: frame,
                                  appIcon: app.icon, thumbnail: nil)
            if isOnscreen {
                onscreen.append(info)
            } else {
                offscreen.append(info)
            }
        }
        let sortedOnscreen = onscreen.enumerated().sorted { a, b in
            let ra = zRank[a.element.id] ?? Int.max
            let rb = zRank[b.element.id] ?? Int.max
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
        return sortedOnscreen + offscreen
    }

    /// Raises the window and activates its app. The accessibility API only sees windows on
    /// other Spaces after the Space switch that activating the app triggers, so the raise is
    /// retried a few times with a short pause.
    static func raise(_ info: WindowInfo) {
        NSRunningApplication(processIdentifier: info.pid)?.activate()
        attemptRaise(info, remainingAttempts: 8)
    }

    private static func attemptRaise(_ info: WindowInfo, remainingAttempts: Int) {
        if raiseViaAccessibility(info) || remainingAttempts <= 1 { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            attemptRaise(info, remainingAttempts: remainingAttempts - 1)
        }
    }

    private static func raiseViaAccessibility(_ info: WindowInfo) -> Bool {
        let appElement = AXUIElementCreateApplication(info.pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let cfValue = value, CFGetTypeID(cfValue) == CFArrayGetTypeID() else { return false }
        let axWindows = cfValue as! [AXUIElement]
        for axWindow in axWindows {
            var windowID: CGWindowID = 0
            if _AXUIElementGetWindow(axWindow, &windowID) == .success, windowID == info.id {
                AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
                return true
            }
        }
        return false
    }

    /// Captures thumbnails asynchronously via ScreenCaptureKit, reporting each one on the main thread.
    static func captureThumbnails(for windows: [WindowInfo], update: @escaping (CGWindowID, CGImage) -> Void) {
        let ids = windows.map(\.id)
        Task {
            guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else {
                return
            }
            for id in ids {
                guard let scWindow = content.windows.first(where: { $0.windowID == id }) else { continue }
                let scale = min(1.0, 720.0 / max(scWindow.frame.width, 1))
                let config = SCStreamConfiguration()
                config.width = max(1, Int(scWindow.frame.width * scale))
                config.height = max(1, Int(scWindow.frame.height * scale))
                config.showsCursor = false
                let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else {
                    continue
                }
                await MainActor.run { update(id, image) }
            }
        }
    }
}
