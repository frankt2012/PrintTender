// Measures a source icon so the adaptive-icon settings in pubspec.yaml can be
// chosen from data rather than by eye.
//
//   swift tool/icon_probe.swift assets/icon/printtender-round.png
//
// Reports the edge colour and how flat it is, plus the extent of the design.
// For an image carrying real alpha the extent of the *opaque* region is what
// matters, because that is the part a launcher cannot mask away — the script
// derives the minimum foreground inset that keeps it inside Android's 66dp safe
// zone directly from that measurement.
//
// Needs only the macOS toolchain — no ImageMagick or Pillow.
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

typealias RGB = (Int, Int, Int)
func at(_ x: Int, _ y: Int) -> RGB {
    let i = (y * w + x) * 4
    return (Int(px[i]), Int(px[i + 1]), Int(px[i + 2]))
}
func alphaAt(_ x: Int, _ y: Int) -> Int { Int(px[(y * w + x) * 4 + 3]) }
func dist(_ a: RGB, _ b: RGB) -> Double {
    let dr = Double(a.0 - b.0), dg = Double(a.1 - b.1), db = Double(a.2 - b.2)
    return (dr * dr + dg * dg + db * db).squareRoot()
}
func hex(_ c: RGB) -> String { String(format: "#%02X%02X%02X", c.0, c.1, c.2) }

var opaque = 0
for i in 0 ..< w * h where px[i * 4 + 3] > 127 { opaque += 1 }
let coverage = 100.0 * Double(opaque) / Double(w * h)
let hasRealAlpha = coverage > 2 && coverage < 98

print("image            : \(w)x\(h), \(String(format: "%.1f", coverage))% opaque\(hasRealAlpha ? " — real transparency" : "")")

// Extent of what the launcher will actually show.
var minX = w, maxX = 0, minY = h, maxY = 0
if hasRealAlpha {
    for y in 0 ..< h { for x in 0 ..< w where alphaAt(x, y) > 127 {
        if x < minX { minX = x }; if x > maxX { maxX = x }
        if y < minY { minY = y }; if y > maxY { maxY = y } } }
} else {
    // Opaque image: fall back to the colour of the outer ring, then find
    // everything that differs from it noticeably.
    var ring: [RGB] = []
    let inset = 6
    for x in stride(from: 0, to: w, by: 2) { ring.append(at(x, inset)); ring.append(at(x, h - 1 - inset)) }
    for y in stride(from: 0, to: h, by: 2) { ring.append(at(inset, y)); ring.append(at(w - 1 - inset, y)) }
    let mr = ring.map { $0.0 }.sorted(), mg = ring.map { $0.1 }.sorted(), mb = ring.map { $0.2 }.sorted()
    let bg = (mr[mr.count / 2], mg[mg.count / 2], mb[mb.count / 2])
    let dev = ring.map { dist($0, bg) }
    print("edge colour      : \(hex(bg))")
    print(String(format: "edge uniformity  : mean %.1f, worst %.1f   (0 = flat field, >60 = artwork)",
                 dev.reduce(0, +) / Double(dev.count), dev.max() ?? 0))
    for y in stride(from: 0, to: h, by: 2) { for x in stride(from: 0, to: w, by: 2) where dist(at(x, y), bg) > 42 {
        if x < minX { minX = x }; if x > maxX { maxX = x }
        if y < minY { minY = y }; if y > maxY { maxY = y } } }
}

guard maxX > minX else { print("content          : one flat colour"); exit(0) }
let spanW = Double(maxX - minX) / Double(w)
let spanH = Double(maxY - minY) / Double(h)
print(String(format: "content spans    : %.1f%% of width, %.1f%% of height, centred at (%.1f%%, %.1f%%)",
             spanW * 100, spanH * 100,
             100.0 * Double(minX + maxX) / 2 / Double(w),
             100.0 * Double(minY + maxY) / 2 / Double(h)))

// Android guarantees a 66dp circle at the centre of the 108dp adaptive canvas;
// a launcher mask may show more but never less. Solve for the smallest inset
// that keeps the opaque content inside it.
let fraction = max(spanW, spanH)
if fraction > 0 && fraction < 1 {
    let needed = 50.0 * (1.0 - 66.0 / (fraction * 108.0))
    if needed > 0 {
        print(String(format: "suggested inset  : %.0f%% or more (content would be %.1fdp wide at the default 16%%)",
                     ceil(needed), fraction * (1.0 - 0.32) * 108))
    } else {
        print("suggested inset  : none — content already fits the 66dp safe zone at any inset")
    }
}
