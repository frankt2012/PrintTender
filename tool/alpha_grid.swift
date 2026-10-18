// Dumps a 16x16 grid of per-cell opacity, so a reconstructed alpha channel can
// be inspected as text: opaque interiors should be uniformly FF, edges should
// transition over one cell, and the overall shape should read as a recognisable
// circle or rounded square with no holes punched inside the design.
//
//   swift tool/alpha_grid.swift assets/icon/printtender-round.png
import AppKit
import CoreGraphics

let path = CommandLine.arguments[1]
guard let data = FileManager.default.contents(atPath: path),
      let img = NSImage(data: data),
      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("could not load \(path)\n", stderr); exit(1)
}
let w = cg.width, h = cg.height
var px = [UInt8](repeating: 0, count: w * h * 4)
guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                          bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(2) }
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

let n = 16, cw = w / n, ch = h / n
print("--- \(path): alpha per cell, row 0 = top (FF = opaque) ---")
for row in 0 ..< n {
    var line = ""
    for col in 0 ..< n {
        var sum = 0, c = 0
        for y in row * ch ..< (row + 1) * ch {
            for x in col * cw ..< (col + 1) * cw { sum += Int(px[(y * w + x) * 4 + 3]); c += 1 }
        }
        line += String(format: "%02X ", sum / c)
    }
    print(line)
}
var opaque = 0
for i in 0 ..< w * h where px[i * 4 + 3] > 127 { opaque += 1 }
print(String(format: "opaque: %.1f%%", 100.0 * Double(opaque) / Double(w * h)))
