import Foundation

/// The agent holding the keyboard.
public struct Holder: Codable, Sendable, Equatable {
    public var reason: String
    /// Who it is, e.g. the repo and branch it runs in.
    public var label: String
    public var pid: Int32
    public var started: Date
    /// How long it expects to need the keyboard, when it said.
    public var seconds: Double?

    public init(reason: String, label: String, pid: Int32, started: Date, seconds: Double? = nil) {
        self.reason = reason; self.label = label; self.pid = pid; self.started = started; self.seconds = seconds
    }
}

/// An agent queued for the keyboard.
public struct Waiter: Codable, Sendable, Equatable {
    public var reason: String
    public var label: String
    public var pid: Int32
    public var since: Date

    public init(reason: String, label: String, pid: Int32, since: Date) {
        self.reason = reason; self.label = label; self.pid = pid; self.since = since
    }
}

public struct Rect: Codable, Sendable, Equatable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

/// The virtual display, as the menu bar app last published it.
public struct DisplayInfo: Codable, Sendable, Equatable {
    public var id: UInt32
    /// The menu bar app's process; the display exists only while it runs.
    public var pid: Int32
    public var scale: Double
    /// CoreGraphics coordinates: origin at the top left of the main display, y down.
    public var cg: Rect
    /// AppKit coordinates (`NSWindow` frames): origin at the bottom left of the main display, y up.
    public var appKit: Rect

    public init(id: UInt32, pid: Int32, scale: Double, cg: Rect, appKit: Rect) {
        self.id = id; self.pid = pid; self.scale = scale; self.cg = cg; self.appKit = appKit
    }
}
