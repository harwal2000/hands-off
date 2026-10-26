import AppKit

enum AppBundle {
    /// This build's identifier, so a second copy built for testing (another identifier) never quits or launches the
    /// installed app.
    static let identifier = Bundle.main.bundleIdentifier ?? "com.harwal2000.handsoff"

    /// The installed (or this) `Hands Off.app`, if there is one.
    static var url: URL? {
        let own = Bundle.main.bundleURL
        if own.pathExtension == "app" { return own }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
    }

    /// Starts the menu bar app in the background (no-op when it is already running).
    @discardableResult
    static func launch() -> Bool {
        guard let url else { return false }
        let open = Process()
        open.executableURL = URL(filePath: "/usr/bin/open")
        open.arguments = ["-g", url.path]
        do { try open.run(); open.waitUntilExit() } catch { return false }
        return open.terminationStatus == 0
    }
}
