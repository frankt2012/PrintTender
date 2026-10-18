// Restores alpha lost when a transparent image was exported to JPEG.
//
// Such an export flattens the transparency into a rendered checkerboard (two
// alternating neutral tones). This keys that checkerboard back out: a pixel is
// a candidate if it is neutral grey and bright, and candidates are then
// flood-filled from the image border so tinted-but-light pixels *inside* the
// artwork are never reached, no matter how pale they are.
//
//   swift tool/restore_alpha.swift <in> <out>
//
// Prints the recovered coverage so it can be sanity-checked against the border
// area the design is expected to have.
import AppKit
import CoreGraphics

let inPath = CommandLine.arguments[1]
let outPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : inPath

guard let data = FileManager.default.contents(atPath: inPath),
      let img = NSImage(data: data),
      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("could not load \(inPath)\n", stderr); exit(1)
}
let w = cg.width, h = cg.height
var px = [UInt8](repeating: 0, count: w * h * 4)
guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                          bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(2) }
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

// Neutral and bright = one of the two checkerboard tones. Tinted artwork is
// excluded by the neutrality test however pale it gets.
func isChecker(_ i: Int) -> Bool {
    let r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2])
    let hi = max(r, g, b), lo = min(r, g, b)
    guard hi - lo <= 17 else { return false }
    return (r + g + b) / 3 >= 176
}

var bg = [Bool](repeating: false, count: w * h)
var stack: [Int] = []
func push(_ p: Int) {
    guard p >= 0 && p < w * h && !bg[p] && isChecker(p * 4) else { return }
    bg[p] = true; stack.append(p)
}
for x in 0 ..< w { push(x); push((h - 1) * w + x) }
for y in 0 ..< h { push(y * w); push(y * w + w - 1) }
while let p = stack.popLast() {
    let x = p % w, y = p / w
    if x > 0 { push(p - 1) }
    if x < w - 1 { push(p + 1) }
    if y > 0 { push(p - w) }
    if y < h - 1 { push(p + w) }
}

var removed = 0
for p in 0 ..< w * h where bg[p] {
    px[p * 4 + 3] = 0
    px[p * 4] = 0; px[p * 4 + 1] = 0; px[p * 4 + 2] = 0
    removed += 1
}
print("  removed \(removed) px = \(String(format: "%.1f", 100.0 * Double(removed) / Double(w * h)))% of the image")

// Re-premultiply then normalise: callers expect straight alpha in the PNG.
guard let out = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                          bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(3) }
guard let outCG = out.makeImage() else { fputs("makeImage failed\n", stderr); exit(4) }
let rep = NSBitmapImageRep(cgImage: outCG)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(5) }
try! png.write(to: URL(fileURLWithPath: outPath))
print("  wrote \(outPath)")
