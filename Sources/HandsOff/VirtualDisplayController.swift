import AppKit
import CVirtualDisplay
import HandsOffCore

/// Keeps the virtual display alive and publishes where it is.
@MainActor final class VirtualDisplayController {
    private var display: HOVirtualDisplay?
    private let store: StateStore

    init(store: StateStore) { self.store = store }

    var isOn: Bool { display != nil }
    var displayID: CGDirectDisplayID? { display?.displayID }

    /// Same point size and scale as the main display, so apps lay out as they would there.
    func turnOn() {
        guard display == nil, let main = NSScreen.screens.first else { return }
        let size = main.frame.size
        display = HOVirtualDisplay(name: "Hands Off", width: UInt(size.width), height: UInt(size.height),
                                   hiDPI: main.backingScaleFactor > 1)
        guard display != nil else { NSLog("Hands Off: macOS refused to create the virtual display"); return }
        // macOS takes a moment to add the display; place it once it's there.
        for delay in [0.3, 1.0, 2.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.placeAndPublish() }
        }
    }

    func turnOff() {
        guard display != nil else { return }
        display = nil
        store.removeDisplay(pid: getpid())
    }

    /// Diagonally off the main display's bottom-right corner, touching it at a single point so the pointer
    /// doesn't drift onto it. Configured for this app only: macOS undoes it when the app quits.
    func placeAndPublish() {
        guard let id = display?.displayID else { return }
        let main = CGDisplayBounds(CGMainDisplayID())
        let target = CGPoint(x: main.maxX, y: main.maxY)
        if CGDisplayBounds(id).origin != target {
            var config: CGDisplayConfigRef?
            if CGBeginDisplayConfiguration(&config) == .success, let config {
                CGConfigureDisplayOrigin(config, id, Int32(target.x), Int32(target.y))
                CGCompleteDisplayConfiguration(config, .forAppOnly)
            }
        }
        publish()
    }

    func publish() {
        guard let id = display?.displayID else { return }
        let cg = CGDisplayBounds(id)
        guard cg.width > 0 else { return }
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        let screen = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }
        let info = DisplayInfo(
            id: id, pid: getpid(), scale: Double(screen?.backingScaleFactor ?? 1),
            cg: Rect(x: cg.minX, y: cg.minY, width: cg.width, height: cg.height),
            appKit: Rect(x: cg.minX, y: mainHeight - cg.maxY, width: cg.width, height: cg.height))
        do { try store.writeDisplay(info) } catch { NSLog("Hands Off: couldn't write display info: \(error)") }
    }

    /// Names of the apps with windows on the virtual display. Window owners are readable without Screen
    /// Recording permission (window titles aren't).
    func appsOnDisplay() -> [String] {
        guard let id = display?.displayID else { return [] }
        let bounds = CGDisplayBounds(id)
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var names: [String] = []
        for w in windows {
            guard let owner = w[kCGWindowOwnerName as String] as? String,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: dict),
                  frame.intersects(bounds), !names.contains(owner) else { continue }
            names.append(owner)
        }
        return names
    }
}
