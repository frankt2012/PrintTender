// Measures a source icon so the adaptive-icon settings in pubspec.yaml can be
// chosen from data rather than by eye: the field colour, how flat the edges are,
// and how much of the square the artwork actually occupies.
//
//   swift tool/icon_probe.swift assets/icon/printtender-icon.png
//
// Needs only the macOS toolchain — no ImageMagick or Pillow.
import AppKit
import CoreGraphics

let path = CommandLine.arguments[1]
guard let data = FileManager.default.contents(atPath: path),
      let img = NSImage(data: data),
      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("could not load image\n", stderr); exit(1)
}

let w = cg.width, h = cg.height
var px = [UInt8](repeating: 0, count: w * h * 4)
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                          bytesPerRow: w * 4, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fputs("could not build context\n", stderr); exit(2)
}
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

typealias RGB = (Int, Int, Int)
func at(_ x: Int, _ y: Int) -> RGB {
    let i = (y * w + x) * 4
    return (Int(px[i]), Int(px[i + 1]), Int(px[i + 2]))
}
func dist(_ a: RGB, _ b: RGB) -> Double {
    let dr = Double(a.0 - b.0), dg = Double(a.1 - b.1), db = Double(a.2 - b.2)
    return (dr * dr + dg * dg + db * db).squareRoot()
}
func hex(_ c: RGB) -> String { String(format: "#%02X%02X%02X", c.0, c.1, c.2) }
func patchMean(_ x0: Int, _ y0: Int, _ size: Int) -> RGB {
    var rs = 0, gs = 0, bs = 0, n = 0
    for y in y0 ..< min(y0 + size, h) {
        for x in x0 ..< min(x0 + size, w) {
            let c = at(x, y); rs += c.0; gs += c.1; bs += c.2; n += 1
        }
    }
    return n == 0 ? (0, 0, 0) : (rs / n, gs / n, bs / n)
}
func worstInPatch(_ x0: Int, _ y0: Int, _ size: Int) -> Double {
    let m = patchMean(x0, y0, size)
    var worst = 0.0
    for y in stride(from: 0, to: size, by: 3) {
        for x in stride(from: 0, to: size, by: 3) {
            worst = max(worst, dist(at(x0 + x, y0 + y), m))
        }
    }
    return worst
}

// Background colour = median of the outermost ring of pixels.
var ring: [RGB] = []
let inset = 6
for x in stride(from: 0, to: w, by: 2) { ring.append(at(x, inset)); ring.append(at(x, h - 1 - inset)) }
for y in stride(from: 0, to: h, by: 2) { ring.append(at(inset, y)); ring.append(at(w - 1 - inset, y)) }
let mr = ring.map { $0.0 }.sorted(), mg = ring.map { $0.1 }.sorted(), mb = ring.map { $0.2 }.sorted()
let bg = (mr[mr.count / 2], mg[mg.count / 2], mb[mb.count / 2])

print("image            : \(w)x\(h)")
print("edge colour      : \(hex(bg))")
let dev = ring.map { dist($0, bg) }
print(String(format: "edge uniformity  : mean %.1f, worst %.1f   (0 = flat field, >60 = artwork)",
             dev.reduce(0, +) / Double(dev.count), dev.max() ?? 0))

let corner = 48
print("corners          :")
for (name, x0, y0) in [("top-left     ", 0, 0), ("top-right    ", w - corner, 0),
                       ("bottom-left  ", 0, h - corner), ("bottom-right ", w - corner, h - corner)] {
    let m = patchMean(x0, y0, corner)
    print("  \(name) \(hex(m))   max deviation \(String(format: "%.0f", worstInPatch(x0, y0, corner)))")
}

var minX = w, maxX = 0, minY = h, maxY = 0
let thresh = 42.0
for y in stride(from: 0, to: h, by: 2) {
    for x in stride(from: 0, to: w, by: 2) {
        if dist(at(x, y), bg) > thresh {
            if x < minX { minX = x }; if x > maxX { maxX = x }
            if y < minY { minY = y }; if y > maxY { maxY = y }
        }
    }
}
if maxX > minX {
    print(String(format: "content spans    : %.0f%% of width, %.0f%% of height",
                 100.0 * Double(maxX - minX) / Double(w), 100.0 * Double(maxY - minY) / Double(h)))
    print(String(format: "                 : centred at (%.0f%%, %.0f%%) from top-left",
                 100.0 * Double(minX + maxX) / 2 / Double(w),
                 100.0 * Double(minY + maxY) / 2 / Double(h)))
} else {
    print("content spans    : whole image is one flat colour")
}
