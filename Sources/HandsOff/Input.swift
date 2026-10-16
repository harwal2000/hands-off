import CoreGraphics

/// Seconds since the user last pressed a key or clicked. Reads the hardware (HID) event state, so events that
/// apps post themselves don't count, and mouse movement, which doesn't move focus, doesn't either. Needs no
/// permission.
func secondsSinceUserInput() -> Double {
    let types: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
    return types.map { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) }.min() ?? .infinity
}

/// Active displays in the order `screencapture -D` numbers them (1 is the main display).
func activeDisplays() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetActiveDisplayList(count, &ids, &count)
    return Array(ids.prefix(Int(count)))
}
