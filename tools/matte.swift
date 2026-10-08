// Cuts Claudia out of film frames with Vision subject lift (the Photos "lift subject" model).
// usage: matte <inDir> <outDir> <x> <y> <w> <h> [frame:x,y,w,h ...]
// Each frame:x,y,w,h is a box (crop pixels, top-left origin) where a cursor or dialog fused with her in that frame.
// Inside it, white, cream, black and grey pixels are erased; her coloured coat and skin stay.
// Crops every PNG in inDir to the rect (top-left origin, pixels), keeps the largest lifted subject,
// then trims all frames to one shared box so the sprite never jumps. Feet sit on the box's bottom edge.
// Writes <outDir>/height: her median figure height in pixels, so the app can show every move at one size.
import AppKit
import Vision
import CoreImage

let a = CommandLine.arguments
guard a.count >= 7, let x = Int(a[3]), let y = Int(a[4]), let w = Int(a[5]), let h = Int(a[6]) else {
    print("usage: matte <inDir> <outDir> <x> <y> <w> <h> [frame:x,y,w,h ...]"); exit(1)
}
var erase: [String: [CGRect]] = [:]   // "0004.png" → boxes, top-left origin
for e in a.dropFirst(7) {
    let p = e.split(separator: ":"), v = p[1].split(separator: ",").compactMap { Int($0) }
    erase["\(p[0]).png", default: []].append(CGRect(x: v[0], y: v[1], width: v[2], height: v[3]))
}
let inDir = URL(fileURLWithPath: a[1]), outDir = URL(fileURLWithPath: a[2])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let ctx = CIContext()
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
let files = try FileManager.default.contentsOfDirectory(at: inDir, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "png" }.sorted { $0.lastPathComponent < $1.lastPathComponent }

// sum of a float32 one-channel mask
func area(_ b: CVPixelBuffer) -> Float {
    CVPixelBufferLockBaseAddress(b, .readOnly); defer { CVPixelBufferUnlockBaseAddress(b, .readOnly) }
    let w = CVPixelBufferGetWidth(b), h = CVPixelBufferGetHeight(b), row = CVPixelBufferGetBytesPerRow(b)
    let p = CVPixelBufferGetBaseAddress(b)!
    var s: Float = 0
    for y in 0..<h { let r = (p + y * row).assumingMemoryBound(to: Float.self); for x in 0..<w { s += r[x] } }
    return s
}

// bounding box of alpha > 10 in CIImage coordinates (bottom-left origin)
func alphaBox(_ img: CIImage) -> CGRect {
    let W = Int(img.extent.width), H = Int(img.extent.height)
    var px = [UInt8](repeating: 0, count: W * H * 4)
    ctx.render(img, toBitmap: &px, rowBytes: W * 4, bounds: img.extent, format: .RGBA8, colorSpace: srgb)
    var x0 = W, y0 = H, x1 = -1, y1 = -1
    for yy in 0..<H { for xx in 0..<W where px[(yy * W + xx) * 4 + 3] > 10 {
        x0 = min(x0, xx); x1 = max(x1, xx); y0 = min(y0, yy); y1 = max(y1, yy)
    } }
    if x1 < 0 { return .null }
    return CGRect(x: x0, y: H - 1 - y1, width: x1 - x0 + 1, height: y1 - y0 + 1) // bitmap rows run top-down
}

// An XP balloon fused with her, or cutting across her, shows its flat cream (252,252,223) inside her mask
// or within 4 px of her edge. Clouds and her white clothes have shading, so they rarely hit it exactly.
func touchesBalloon(_ crop: CIImage, _ m: CVPixelBuffer) -> Bool {
    let W = Int(crop.extent.width), H = Int(crop.extent.height)
    var px = [UInt8](repeating: 0, count: W * H * 4)
    ctx.render(crop, toBitmap: &px, rowBytes: W * 4, bounds: crop.extent, format: .RGBA8, colorSpace: srgb)
    CVPixelBufferLockBaseAddress(m, .readOnly); defer { CVPixelBufferUnlockBaseAddress(m, .readOnly) }
    let mw = CVPixelBufferGetWidth(m), mh = CVPixelBufferGetHeight(m), row = CVPixelBufferGetBytesPerRow(m)
    let base = CVPixelBufferGetBaseAddress(m)!
    func her(_ x: Int, _ y: Int) -> Bool {   // mask is top-down like the bitmap, maybe at another size
        let mx = x * mw / W, my = y * mh / H
        return (base + my * row).assumingMemoryBound(to: Float.self)[mx] > 0.5
    }
    var inside = 0, edge = 0
    for y in 0..<H { for x in 0..<W {
        let i = (y * W + x) * 4, r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2])
        guard abs(r - 252) <= 4, abs(g - 252) <= 4, abs(b - 223) <= 6 else { continue }
        if her(x, y) { inside += 1; continue }
        let r4 = 4
        outer: for dy in -r4...r4 { for dx in -r4...r4 {
            let xx = x + dx, yy = y + dy
            if xx >= 0, yy >= 0, xx < W, yy < H, her(xx, yy) { edge += 1; break outer }
        } }
    } }
    if ProcessInfo.processInfo.environment["DEBUG"] != nil { print("  cream inside \(inside) edge \(edge)") }
    return inside > 20 || edge > 10
}

// Inside the boxes, erase the light, black and grey pixels of cursors and dialogs, plus a 1 px rim.
func eraseUI(_ img: CIImage, _ crop: CIImage, _ boxes: [CGRect]) -> CIImage {
    let W = Int(crop.extent.width), H = Int(crop.extent.height)
    var px = [UInt8](repeating: 0, count: W * H * 4)
    ctx.render(crop, toBitmap: &px, rowBytes: W * 4, bounds: crop.extent, format: .RGBA8, colorSpace: srgb)
    var keep = [UInt8](repeating: 255, count: W * H)
    for b in boxes { for yy in max(0, Int(b.minY))..<min(H, Int(b.maxY)) { for xx in max(0, Int(b.minX))..<min(W, Int(b.maxX)) {
        let i = (yy * W + xx) * 4, lo = min(px[i], px[i + 1], px[i + 2]), hi = max(px[i], px[i + 1], px[i + 2])
        guard lo > 200 || hi < 35 || hi - lo < 16 else { continue }   // light, black, or grey text edges
        for dy in -1...1 { for dx in -1...1 where (0..<W).contains(xx + dx) && (0..<H).contains(yy + dy) {
            keep[(yy + dy) * W + xx + dx] = 0
        } }
    } } }
    let gray = CGImage(width: W, height: H, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: W,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                       provider: CGDataProvider(data: Data(keep) as CFData)!, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)!
    return img.applyingFilter("CIBlendWithMask", parameters: [
        kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: CIImage(cgImage: gray)]).cropped(to: crop.extent)
}

var outs: [(String, CIImage)] = []
var box = CGRect.null
var heights: [CGFloat] = []
for f in files {
    guard let full = CIImage(contentsOf: f) else { continue }
    let rect = CGRect(x: x, y: Int(full.extent.height) - y - h, width: w, height: h)
    let crop = full.cropped(to: rect).transformed(by: .init(translationX: -rect.minX, y: -rect.minY))
    let handler = VNImageRequestHandler(cgImage: ctx.createCGImage(crop, from: crop.extent)!)
    let req = VNGenerateForegroundInstanceMaskRequest()
    try handler.perform([req])
    guard let r = req.results?.first else { print("no subject", f.lastPathComponent); continue }
    // largest instance only: drops cursors, balloons and window edges
    let masks = r.allInstances.compactMap { try? r.generateScaledMaskForImage(forInstances: [$0], from: handler) }
    guard let m = masks.max(by: { area($0) < area($1) }) else { continue }
    if touchesBalloon(crop, m) { print("balloon", f.lastPathComponent); continue }
    // choke 1 px and feather, so no rim of sky or grass stays on her edge
    let mask = CIImage(cvPixelBuffer: m).clampedToExtent()
        .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: 1])
        .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.6])
    var out = crop.applyingFilter("CIBlendWithMask", parameters: [
        kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: mask])
        .cropped(to: crop.extent)
    if let boxes = erase[f.lastPathComponent] { out = eraseUI(out, crop, boxes) }
    let b = alphaBox(out)
    box = box.union(b); heights.append(b.height)
    outs.append((f.lastPathComponent, out))
}

box = box.insetBy(dx: -4, dy: 0).intersection(CGRect(x: 0, y: 0, width: w, height: h)).integral
for (name, img) in outs {
    let t = img.cropped(to: box).transformed(by: .init(translationX: -box.minX, y: -box.minY))
    try ctx.writePNGRepresentation(of: t, to: outDir.appendingPathComponent(name), format: .RGBA8, colorSpace: srgb)
}
try "\(Int(heights.sorted()[heights.count / 2]))".write(to: outDir.appendingPathComponent("height"), atomically: true, encoding: .utf8)
print("matted \(outs.count) frames, box \(Int(box.width))×\(Int(box.height)) at crop (\(Int(box.minX)), \(h - Int(box.maxY))) → \(outDir.lastPathComponent)")
