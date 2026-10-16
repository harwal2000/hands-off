import CoreGraphics
// Prints the window ID of the open menu belonging to the app named in argv[1].
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list where (w[kCGWindowOwnerName as String] as? String) == CommandLine.arguments[1] && ((w[kCGWindowLayer as String] as? Int) ?? 0) >= 20 {
    if let b = w[kCGWindowBounds as String] as? [String: Any], let h = b["Height"] as? Double, h > 40 { print(w[kCGWindowNumber as String]!); break }
}
