import AppKit
// itemcrop <times.txt> <framesDir> <outDir> <regionX>: crops each 2x frame to the menu bar item (per-frame "t x y w h"),
// left-aligned on a fixed-width canvas filled with the menu bar colour next to the item.
let a = CommandLine.arguments
let lines = try! String(contentsOfFile: a[1], encoding: .utf8).split(separator: "\n").map { $0.split(separator: " ").map(String.init) }
let frames = try! FileManager.default.contentsOfDirectory(atPath: a[2]).sorted()
let regionX = Double(a[4])!, pad = 8.0, scale = 2.0
let maxW = lines.compactMap { Double($0[3]) }.max()! + 2 * pad
for (i, name) in frames.enumerated() where i < lines.count {
    let l = lines[i]
    let img = NSImage(contentsOfFile: "\(a[2])/\(name)")!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    let x = (Double(l[1])! - regionX - pad) * scale, w = (Double(l[3])! + 2 * pad) * scale
    let crop = img.cropping(to: CGRect(x: max(0, x), y: 0, width: min(w, Double(img.width) - max(0, x)), height: Double(img.height)))!
    let W = Int(maxW * scale), H = img.height
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Background: stretch the item's leftmost padding column across the canvas.
    if let edge = crop.cropping(to: CGRect(x: 0, y: 0, width: 2, height: H)) { ctx.draw(edge, in: CGRect(x: 0, y: 0, width: W, height: H)) }
    ctx.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: H))
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(a[3])/\(name)"))
}
