import AppKit
import CoreGraphics

/// Процедурные текстуры материалов. Размер плитки текстуры задан в метрах (реальные размеры кирпича, блоков, волн).
enum TexKind: Hashable {
    case facade(FacadeFinish)
    case roof(RoofCovering)
    case concrete, sand, grass, plaster, wood, paving, deck, gravel
}

private struct RNG {
    var s: UInt64
    mutating func next() -> Double {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return Double((s >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
    }
    mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * next() }
}

private struct RGB {
    var r: Double, g: Double, b: Double
    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    init(_ c: NSColor) {
        let c = c.usingColorSpace(.sRGB) ?? c
        r = Double(c.redComponent); g = Double(c.greenComponent); b = Double(c.blueComponent)
    }
    func scaled(_ k: Double) -> RGB { RGB(min(r * k, 1), min(g * k, 1), min(b * k, 1)) }
    func mix(_ o: RGB, _ t: Double) -> RGB { RGB(r + (o.r - r) * t, g + (o.g - g) * t, b + (o.b - b) * t) }
    var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }
}

enum Tex {
    private static var cache: [TexKind: NSImage] = [:]

    /// Размер плитки текстуры, м (по горизонтали, по вертикали / вдоль ската)
    static func tile(_ k: TexKind) -> (w: Double, h: Double) {
        switch k {
        case .facade(let f):
            switch f {
            case .siding: return (1.0, 0.60)
            case .imitationTimber: return (1.2, 0.30)
            case .fiberCement: return (2.4, 1.2)
            case .plaster: return (1.0, 1.0)
            case .facingBrick: return (0.52, 0.30)
            }
        case .roof(let c):
            switch c {
            case .metalTile, .compositeTile: return (0.366, 0.35)
            case .profiledSheet: return (0.20, 1.0)
            case .seam: return (0.50, 1.0)
            case .slate: return (0.334, 0.9)
            case .ondulin: return (0.19, 1.0)
            case .softShingle: return (1.0, 0.29)
            case .ceramicTile, .cementTile: return (0.60, 0.34)
            }
        case .concrete, .sand, .plaster: return (1, 1)
        case .grass: return (2, 2)
        case .wood: return (0.5, 1.0)
        case .paving: return (0.6, 0.6)
        case .deck: return (1.2, 0.56)
        case .gravel: return (1, 1)
        }
    }

    static func image(_ k: TexKind) -> NSImage {
        if let i = cache[k] { return i }
        let t = tile(k)
        let ppm = min(512 / t.w, 512 / t.h, 900)
        let px = max(16, Int(t.w * ppm)), py = max(16, Int(t.h * ppm))
        let img = render(px, py) { ctx, w, h in draw(k, ctx, w, h) }
        cache[k] = img
        return img
    }

    private static func render(_ px: Int, _ py: Int, _ body: (CGContext, Double, Double) -> Void) -> NSImage {
        let ctx = CGContext(data: nil, width: px, height: py, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setShouldAntialias(true)
        ctx.setFillColor(CGColor(gray: 0.6, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: px, height: py))
        body(ctx, Double(px), Double(py))
        return NSImage(cgImage: ctx.makeImage()!, size: NSSize(width: px, height: py))
    }

    // MARK: - Вспомогательные

    private static func fill(_ ctx: CGContext, _ c: RGB, _ r: CGRect) { ctx.setFillColor(c.cg); ctx.fill(r) }

    private static func noise(_ ctx: CGContext, _ w: Double, _ h: Double, _ n: Int, _ amp: Double, _ rng: inout RNG, size: ClosedRange<Double> = 1...2.5) {
        for _ in 0..<n {
            let x = rng.next() * w, y = rng.next() * h, s = rng.range(size.lowerBound, size.upperBound)
            let light = rng.next() > 0.5
            ctx.setFillColor(CGColor(gray: light ? 1 : 0, alpha: rng.range(0.2, 1) * amp))
            ctx.fill(CGRect(x: x, y: y, width: s, height: s))
        }
    }

    /// Вертикальные полосы с яркостью f(x/w) — для волн/рёбер вдоль ската
    private static func columns(_ ctx: CGContext, _ w: Double, _ h: Double, _ base: RGB, _ f: (Double) -> Double) {
        var x = 0.0
        while x < w {
            fill(ctx, base.scaled(f((x + 0.5) / w)), CGRect(x: x, y: 0, width: 1.01, height: h))
            x += 1
        }
    }

    private static func masonry(_ ctx: CGContext, _ w: Double, _ h: Double, rows: Int, perRow: Int, joint: Double,
                                unit: RGB, mortar: RGB, vary: Double, pores: Bool, _ rng: inout RNG) {
        fill(ctx, mortar, CGRect(x: 0, y: 0, width: w, height: h))
        let rh = h / Double(rows), bw = w / Double(perRow)
        for r in 0..<rows {
            let off = r % 2 == 0 ? 0 : bw / 2
            for k in -1...perRow {
                let x = Double(k) * bw + off
                let c = unit.scaled(rng.range(1 - vary, 1 + vary))
                let rect = CGRect(x: x + joint / 2, y: Double(r) * rh + joint / 2, width: bw - joint, height: rh - joint)
                fill(ctx, c, rect)
                // лёгкий объём: светлее сверху, тень снизу
                fill(ctx, c.scaled(1.06), CGRect(x: rect.minX, y: rect.maxY - max(1, rect.height * 0.12), width: rect.width, height: max(1, rect.height * 0.12)))
                fill(ctx, c.scaled(0.88), CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(1, rect.height * 0.08)))
            }
        }
        noise(ctx, w, h, Int(w * h / (pores ? 25 : 60)), pores ? 0.10 : 0.06, &rng)
    }

    // MARK: - Рисование

    private static func draw(_ k: TexKind, _ ctx: CGContext, _ w: Double, _ h: Double) {
        var rng = RNG(s: UInt64(abs(String(describing: k).hashValue % 100000) + 7))
        switch k {
        case .facade(let f):
            switch f {
            case .siding:
                // сайдинг: 3 доски по 200 мм
                let base = RGB(0.88, 0.88, 0.85), bh = h / 3
                fill(ctx, base, CGRect(x: 0, y: 0, width: w, height: h))
                for i in 0..<3 {
                    let y = Double(i) * bh
                    for j in 0..<Int(bh) {
                        let t = Double(j) / bh
                        fill(ctx, base.scaled(0.90 + 0.12 * t), CGRect(x: 0, y: y + Double(j), width: w, height: 1.5))
                    }
                    fill(ctx, base.scaled(0.62), CGRect(x: 0, y: y, width: w, height: 2))
                }
                noise(ctx, w, h, Int(w * h / 80), 0.04, &rng)
            case .imitationTimber:
                let base = RGB(0.68, 0.47, 0.27), bh = h / 2
                fill(ctx, base, CGRect(x: 0, y: 0, width: w, height: h))
                for i in 0..<2 {
                    let y0 = Double(i) * bh
                    for _ in 0..<14 {
                        let yy = y0 + rng.range(3, bh - 3), amp = rng.range(0.5, 2.5), ph = rng.range(0, 6.28)
                        ctx.setStrokeColor(base.scaled(rng.range(0.75, 0.9)).cg)
                        ctx.setLineWidth(rng.range(0.6, 1.6))
                        ctx.move(to: CGPoint(x: 0, y: yy))
                        var x = 0.0
                        while x <= w { ctx.addLine(to: CGPoint(x: x, y: yy + amp * sin(x / w * 6.28 * 2 + ph))); x += 4 }
                        ctx.strokePath()
                    }
                    fill(ctx, base.scaled(0.45), CGRect(x: 0, y: y0, width: w, height: 3))
                    fill(ctx, base.scaled(1.1), CGRect(x: 0, y: y0 + bh - 3, width: w, height: 2))
                }
            case .fiberCement:
                // панели 1200×600 с открытым швом 8 мм
                let base = RGB(0.47, 0.49, 0.52)
                fill(ctx, base.scaled(0.45), CGRect(x: 0, y: 0, width: w, height: h))
                let pw = w / 2, ph = h / 2, gap = max(2, w / 300)
                for i in 0..<2 {
                    for j in 0..<2 {
                        fill(ctx, base.scaled(rng.range(0.96, 1.04)), CGRect(x: Double(i) * pw + gap / 2, y: Double(j) * ph + gap / 2, width: pw - gap, height: ph - gap))
                    }
                }
                noise(ctx, w, h, Int(w * h / 40), 0.05, &rng)
            case .plaster:
                fill(ctx, RGB(0.95, 0.94, 0.91), CGRect(x: 0, y: 0, width: w, height: h))
                noise(ctx, w, h, Int(w * h / 4), 0.05, &rng, size: 1...2)
            case .facingBrick:
                masonry(ctx, w, h, rows: 4, perRow: 2, joint: w * 0.02, unit: RGB(0.70, 0.36, 0.24), mortar: RGB(0.80, 0.78, 0.74), vary: 0.08, pores: false, &rng)
            }

        case .roof(let c):
            let base = RGB(c.nsColor)
            switch c {
            case .metalTile, .compositeTile:
                columns(ctx, w, h, base) { 0.78 + 0.28 * cos(2 * .pi * $0 * 2) }
                // ступень: тень у нижнего края, блик выше
                for j in 0..<Int(h) {
                    let t = Double(j) / h
                    let k = t < 0.08 ? 0.55 : t < 0.16 ? 1.12 : 1.0 - 0.1 * (t - 0.16)
                    ctx.setFillColor(CGColor(gray: k < 1 ? 0 : 1, alpha: abs(1 - k) * 0.6))
                    ctx.fill(CGRect(x: 0, y: Double(j), width: w, height: 1))
                }
                if c == .compositeTile { noise(ctx, w, h, Int(w * h / 3), 0.25, &rng) }
            case .profiledSheet:
                columns(ctx, w, h, base) { x in
                    if x < 0.15 || x > 0.85 { return 0.9 }
                    if x < 0.3 { return 1.15 }
                    if x < 0.7 { return 1.0 }
                    return 0.7
                }
            case .seam:
                fill(ctx, base, CGRect(x: 0, y: 0, width: w, height: h))
                for j in 0..<Int(w) { fill(ctx, base.scaled(0.95 + 0.08 * Double(j) / w), CGRect(x: Double(j), y: 0, width: 1.01, height: h)) }
                fill(ctx, base.scaled(1.35), CGRect(x: 0, y: 0, width: 3, height: h))
                fill(ctx, base.scaled(0.6), CGRect(x: 3, y: 0, width: 4, height: h))
            case .slate:
                columns(ctx, w, h, base) { 0.82 + 0.22 * cos(2 * .pi * $0 * 2) }
                fill(ctx, base.scaled(0.55), CGRect(x: 0, y: 0, width: w, height: 4))
                noise(ctx, w, h, Int(w * h / 10), 0.08, &rng)
            case .ondulin:
                columns(ctx, w, h, base) { 0.75 + 0.35 * cos(2 * .pi * $0 * 2) }
                noise(ctx, w, h, Int(w * h / 15), 0.06, &rng)
            case .softShingle:
                fill(ctx, base.scaled(0.6), CGRect(x: 0, y: 0, width: w, height: h))
                let rows = 2, per = 3, rh = h / Double(rows), tw = w / Double(per)
                for r in 0..<rows {
                    let off = r % 2 == 0 ? 0 : tw / 2
                    for k in -1...per {
                        let cc = base.scaled(rng.range(0.85, 1.2))
                        fill(ctx, cc, CGRect(x: Double(k) * tw + off + 2, y: Double(r) * rh + 4, width: tw - 4, height: rh - 4))
                    }
                    fill(ctx, base.scaled(0.35), CGRect(x: 0, y: Double(r) * rh, width: w, height: 4))
                }
                noise(ctx, w, h, Int(w * h / 2), 0.22, &rng)
            case .ceramicTile, .cementTile:
                fill(ctx, base.scaled(0.8), CGRect(x: 0, y: 0, width: w, height: h))
                let per = 2, tw = w / Double(per)
                for k in 0..<per {
                    let cc = base.scaled(rng.range(0.9, 1.1))
                    for j in 0..<Int(tw) {
                        let x = Double(j) / tw
                        fill(ctx, cc.scaled(0.7 + 0.45 * sin(.pi * x)), CGRect(x: Double(k) * tw + Double(j), y: 0, width: 1.5, height: h))
                    }
                }
                for j in 0..<Int(h * 0.15) {
                    ctx.setFillColor(CGColor(gray: 0, alpha: 0.45 * (1 - Double(j) / (h * 0.15))))
                    ctx.fill(CGRect(x: 0, y: Double(j), width: w, height: 1))
                }
                if c == .cementTile { noise(ctx, w, h, Int(w * h / 6), 0.1, &rng) }
            }

        case .concrete:
            fill(ctx, RGB(0.66, 0.66, 0.65), CGRect(x: 0, y: 0, width: w, height: h))
            noise(ctx, w, h, Int(w * h / 4), 0.07, &rng, size: 1...4)
            for _ in 0..<60 {
                let x = rng.next() * w, y = rng.next() * h, s = rng.range(1.5, 4)
                ctx.setFillColor(CGColor(gray: 0.3, alpha: 0.35))
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: s, height: s))
            }
        case .sand:
            fill(ctx, RGB(0.86, 0.78, 0.55), CGRect(x: 0, y: 0, width: w, height: h))
            noise(ctx, w, h, Int(w * h / 2), 0.2, &rng, size: 1...2)
        case .grass:
            fill(ctx, RGB(0.36, 0.52, 0.26), CGRect(x: 0, y: 0, width: w, height: h))
            for _ in 0..<Int(w * h / 6) {
                let x = rng.next() * w, y = rng.next() * h
                let c = RGB(0.36, 0.52, 0.26).scaled(rng.range(0.7, 1.35))
                ctx.setStrokeColor(c.cg)
                ctx.setLineWidth(rng.range(0.8, 1.8))
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addLine(to: CGPoint(x: x + rng.range(-3, 3), y: y + rng.range(4, 10)))
                ctx.strokePath()
            }
        case .plaster:
            fill(ctx, RGB(0.93, 0.92, 0.89), CGRect(x: 0, y: 0, width: w, height: h))
            noise(ctx, w, h, Int(w * h / 10), 0.03, &rng)
        case .paving:
            fill(ctx, RGB(0.55, 0.55, 0.53), CGRect(x: 0, y: 0, width: w, height: h))
            let t = w / 2, j = max(2, w / 120)
            for i in 0..<2 { for k in 0..<2 {
                fill(ctx, RGB(0.72, 0.71, 0.68).scaled(rng.range(0.93, 1.05)), CGRect(x: Double(i) * t + j / 2, y: Double(k) * t + j / 2, width: t - j, height: t - j))
            } }
            noise(ctx, w, h, Int(w * h / 6), 0.06, &rng)
        case .deck:
            let base = RGB(0.62, 0.45, 0.30)
            fill(ctx, base.scaled(0.5), CGRect(x: 0, y: 0, width: w, height: h))
            let n = 4, bh = h / Double(n)
            for i in 0..<n {
                fill(ctx, base.scaled(rng.range(0.9, 1.1)), CGRect(x: 0, y: Double(i) * bh + 1.5, width: w, height: bh - 3))
                for _ in 0..<5 {
                    let yy = Double(i) * bh + rng.range(3, bh - 3)
                    fill(ctx, base.scaled(0.8), CGRect(x: 0, y: yy, width: w, height: 0.8))
                }
            }
        case .gravel:
            fill(ctx, RGB(0.55, 0.55, 0.55), CGRect(x: 0, y: 0, width: w, height: h))
            noise(ctx, w, h, Int(w * h / 1.5), 0.35, &rng, size: 2...5)
        case .wood:
            let base = RGB(0.50, 0.32, 0.18)
            fill(ctx, base, CGRect(x: 0, y: 0, width: w, height: h))
            for _ in 0..<30 {
                let xx = rng.next() * w
                ctx.setStrokeColor(base.scaled(rng.range(0.7, 1.15)).cg)
                ctx.setLineWidth(rng.range(0.6, 2))
                ctx.move(to: CGPoint(x: xx, y: 0))
                ctx.addLine(to: CGPoint(x: xx + rng.range(-4, 4), y: h))
                ctx.strokePath()
            }
        }
    }
}
