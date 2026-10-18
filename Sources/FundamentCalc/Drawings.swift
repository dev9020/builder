import AppKit
import CoreGraphics

/// Чертёжные примитивы поверх CGContext с началом координат вверху слева (y вниз).
/// Мир — метры, ось y мира направлена вверх.
struct Sk {
    let cg: CGContext
    let r: CGRect
    var sc: CGFloat = 100
    var ox: CGFloat = 0, oy: CGFloat = 0

    init(_ cg: CGContext, _ r: CGRect, lo: V2, hi: V2, pad: CGFloat = 22, right: CGFloat = 0, top: CGFloat = 0) {
        self.cg = cg; self.r = r
        let w = max(hi.x - lo.x, 1e-3), h = max(hi.y - lo.y, 1e-3)
        let aw = r.width - 2 * pad - right, ah = r.height - 2 * pad - top
        sc = min(aw / CGFloat(w), ah / CGFloat(h))
        ox = r.minX + pad + (aw - CGFloat(w) * sc) / 2 - CGFloat(lo.x) * sc
        oy = r.minY + pad + top + (ah + CGFloat(h) * sc) / 2 + CGFloat(lo.y) * sc
    }

    func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + CGFloat(x) * sc, y: oy - CGFloat(y) * sc) }
    func P(_ v: V2) -> CGPoint { P(v.x, v.y) }

    // MARK: линии и фигуры

    func line(_ a: V2, _ b: V2, _ w: CGFloat = 1, _ c: NSColor = .black, dash: [CGFloat] = []) {
        cg.saveGState()
        cg.setStrokeColor(c.cgColor); cg.setLineWidth(w); cg.setLineDash(phase: 0, lengths: dash)
        cg.move(to: P(a)); cg.addLine(to: P(b)); cg.strokePath()
        cg.restoreGState()
    }

    func poly(_ pts: [V2], fill: NSColor? = nil, stroke: NSColor? = .black, w: CGFloat = 1, close: Bool = true, dash: [CGFloat] = []) {
        guard pts.count > 1 else { return }
        cg.saveGState()
        let path = CGMutablePath()
        path.addLines(between: pts.map(P))
        if close { path.closeSubpath() }
        if let fill { cg.addPath(path); cg.setFillColor(fill.cgColor); cg.fillPath() }
        if let stroke { cg.addPath(path); cg.setStrokeColor(stroke.cgColor); cg.setLineWidth(w); cg.setLineDash(phase: 0, lengths: dash); cg.strokePath() }
        cg.restoreGState()
    }

    enum Hatch { case none, wood, timberCut, concrete, insulation, soil, sand, steel, board }

    func box(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ h: Hatch = .none, fill: NSColor? = nil, stroke: NSColor = .black, w: CGFloat = 0.8) {
        let pts = [V2(x0, y0), V2(x1, y0), V2(x1, y1), V2(x0, y1)]
        let f = fill ?? Sk.fillFor(h)
        poly(pts, fill: f, stroke: nil)
        hatch(pts, h)
        poly(pts, fill: nil, stroke: stroke, w: w)
    }

    static func fillFor(_ h: Hatch) -> NSColor? {
        switch h {
        case .wood, .board: return NSColor(srgbRed: 0.96, green: 0.86, blue: 0.66, alpha: 1)
        case .timberCut: return NSColor(srgbRed: 0.93, green: 0.80, blue: 0.58, alpha: 1)
        case .concrete: return NSColor(white: 0.84, alpha: 1)
        case .insulation: return NSColor(srgbRed: 1.0, green: 0.93, blue: 0.62, alpha: 1)
        case .soil: return NSColor(srgbRed: 0.86, green: 0.78, blue: 0.66, alpha: 1)
        case .sand: return NSColor(srgbRed: 0.98, green: 0.92, blue: 0.75, alpha: 1)
        case .steel: return NSColor(white: 0.6, alpha: 1)
        case .none: return nil
        }
    }

    func hatch(_ pts: [V2], _ h: Hatch) {
        guard h != .none else { return }
        let a = P(pts[0]), c = P(pts[2])
        let rr = CGRect(x: min(a.x, c.x), y: min(a.y, c.y), width: abs(c.x - a.x), height: abs(c.y - a.y))
        cg.saveGState()
        cg.clip(to: rr)
        cg.setLineWidth(0.35)
        switch h {
        case .timberCut:
            cg.setStrokeColor(NSColor(srgbRed: 0.45, green: 0.3, blue: 0.15, alpha: 1).cgColor)
            cg.move(to: CGPoint(x: rr.minX, y: rr.minY)); cg.addLine(to: CGPoint(x: rr.maxX, y: rr.maxY))
            cg.move(to: CGPoint(x: rr.maxX, y: rr.minY)); cg.addLine(to: CGPoint(x: rr.minX, y: rr.maxY))
            cg.strokePath()
        case .wood, .board:
            cg.setStrokeColor(NSColor(srgbRed: 0.6, green: 0.42, blue: 0.22, alpha: 0.55).cgColor)
            let horiz = rr.width >= rr.height
            var t: CGFloat = 3
            while t < (horiz ? rr.height : rr.width) {
                if horiz { cg.move(to: CGPoint(x: rr.minX, y: rr.minY + t)); cg.addLine(to: CGPoint(x: rr.maxX, y: rr.minY + t)) }
                else { cg.move(to: CGPoint(x: rr.minX + t, y: rr.minY)); cg.addLine(to: CGPoint(x: rr.minX + t, y: rr.maxY)) }
                t += 5
            }
            cg.strokePath()
        case .concrete:
            cg.setFillColor(NSColor(white: 0.45, alpha: 1).cgColor)
            var seed: UInt64 = 12345
            func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat((seed >> 33) % 10000) / 10000 }
            let n = Int(rr.width * rr.height / 60)
            for _ in 0..<min(n, 4000) {
                let x = rr.minX + rnd() * rr.width, y = rr.minY + rnd() * rr.height
                if rnd() < 0.8 { cg.fillEllipse(in: CGRect(x: x, y: y, width: 1.1, height: 1.1)) }
                else { cg.move(to: CGPoint(x: x, y: y)); cg.addLine(to: CGPoint(x: x + 3, y: y + 1)); cg.addLine(to: CGPoint(x: x + 1, y: y + 3)); cg.closePath(); cg.strokePath() }
            }
        case .insulation:
            cg.setStrokeColor(NSColor(srgbRed: 0.75, green: 0.55, blue: 0.1, alpha: 0.8).cgColor)
            let horiz = rr.width >= rr.height
            let th = horiz ? rr.height : rr.width
            let len = horiz ? rr.width : rr.height
            var t: CGFloat = 0
            let stepL = max(th * 0.5, 3)
            let path = CGMutablePath()
            var up = true
            while t < len {
                let p0 = horiz ? CGPoint(x: rr.minX + t, y: up ? rr.minY + 1 : rr.maxY - 1) : CGPoint(x: up ? rr.minX + 1 : rr.maxX - 1, y: rr.minY + t)
                if t == 0 { path.move(to: p0) } else { path.addLine(to: p0) }
                t += stepL; up.toggle()
            }
            cg.addPath(path); cg.strokePath()
        case .soil:
            cg.setStrokeColor(NSColor(srgbRed: 0.45, green: 0.35, blue: 0.25, alpha: 0.6).cgColor)
            var t: CGFloat = -rr.height
            while t < rr.width { cg.move(to: CGPoint(x: rr.minX + t, y: rr.maxY)); cg.addLine(to: CGPoint(x: rr.minX + t + rr.height, y: rr.minY)); t += 6 }
            cg.strokePath()
        case .sand:
            cg.setFillColor(NSColor(srgbRed: 0.6, green: 0.5, blue: 0.3, alpha: 0.6).cgColor)
            var y = rr.minY + 2
            var odd = false
            while y < rr.maxY { var x = rr.minX + (odd ? 4 : 1); while x < rr.maxX { cg.fillEllipse(in: CGRect(x: x, y: y, width: 0.9, height: 0.9)); x += 6 }; y += 3.5; odd.toggle() }
        case .steel, .none: break
        }
        cg.restoreGState()
    }

    func dot(_ c: V2, _ rad: CGFloat = 2.5, _ col: NSColor = .systemRed) {
        let p = P(c)
        cg.setFillColor(col.cgColor)
        cg.fillEllipse(in: CGRect(x: p.x - rad, y: p.y - rad, width: 2 * rad, height: 2 * rad))
    }

    func bar(_ a: V2, _ b: V2, d: Int, _ c: NSColor = NSColor(srgbRed: 0.8, green: 0.2, blue: 0.1, alpha: 1)) {
        line(a, b, max(1.2, CGFloat(Double(d) / 1000) * sc), c)
    }

    // MARK: текст и размеры

    static func text(_ s: String, _ p: CGPoint, size: CGFloat = 7.5, color: NSColor = .black, bold: Bool = false, ax: CGFloat = 0, ay: CGFloat = 0.5, maxW: CGFloat = 260, bg: Bool = false) {
        let font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        let st = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
        let br = st.boundingRect(with: CGSize(width: maxW, height: 1000), options: [.usesLineFragmentOrigin])
        let rect = CGRect(x: p.x - br.width * ax, y: p.y - br.height * ay, width: ceil(br.width) + 1, height: ceil(br.height))
        if bg, let ctx = NSGraphicsContext.current?.cgContext {
            ctx.setFillColor(NSColor(white: 1, alpha: 0.85).cgColor)
            ctx.fill(rect.insetBy(dx: -1.5, dy: -0.5))
        }
        st.draw(with: rect, options: [.usesLineFragmentOrigin])
    }

    func label(_ s: String, _ at: V2, size: CGFloat = 7.5, ax: CGFloat = 0, ay: CGFloat = 0.5, bold: Bool = false, color: NSColor = .black, bg: Bool = false) {
        Sk.text(s, P(at), size: size, color: color, bold: bold, ax: ax, ay: ay, bg: bg)
    }

    /// Выноска: от точки детали к подписи (позиция подписи — в мире)
    func leader(_ from: V2, _ to: V2, _ s: String, size: CGFloat = 7.5, maxW: CGFloat = 170) {
        let a = P(from), b = P(to)
        cg.saveGState()
        cg.setStrokeColor(NSColor.darkGray.cgColor); cg.setLineWidth(0.5)
        cg.move(to: a); cg.addLine(to: b); cg.strokePath()
        cg.setFillColor(NSColor.black.cgColor)
        cg.fillEllipse(in: CGRect(x: a.x - 1.3, y: a.y - 1.3, width: 2.6, height: 2.6))
        let left = b.x < a.x
        cg.move(to: b); cg.addLine(to: CGPoint(x: b.x + (left ? -8 : 8), y: b.y)); cg.strokePath()
        cg.restoreGState()
        let room = left ? b.x - 10 - r.minX - 4 : r.maxX - (b.x + 10) - 4
        Sk.text(s, CGPoint(x: b.x + (left ? -10 : 10), y: b.y), size: size, ax: left ? 1 : 0, ay: 0.5, maxW: max(60, min(maxW, room)))
    }

    /// Размерная линия между a и b, сдвинутая на off (м) по нормали
    func dim(_ a: V2, _ b: V2, off: Double, _ s: String? = nil, size: CGFloat = 7) {
        let d = (b - a).unit, n = V2(-d.y, d.x)
        let a1 = a + n * off, b1 = b + n * off
        cg.saveGState()
        cg.setStrokeColor(NSColor(white: 0.25, alpha: 1).cgColor); cg.setLineWidth(0.45)
        cg.move(to: P(a)); cg.addLine(to: P(a1 + n * (off >= 0 ? 0.02 : -0.02)))
        cg.move(to: P(b)); cg.addLine(to: P(b1 + n * (off >= 0 ? 0.02 : -0.02)))
        cg.move(to: P(a1)); cg.addLine(to: P(b1)); cg.strokePath()
        for q in [a1, b1] {
            let p = P(q)
            cg.move(to: CGPoint(x: p.x - 3, y: p.y + 3)); cg.addLine(to: CGPoint(x: p.x + 3, y: p.y - 3))
        }
        cg.setLineWidth(0.9); cg.strokePath()
        cg.restoreGState()
        let txt = s ?? "\(Int(((b - a).len * 1000).rounded()))"
        let mid = P((a1 + b1) / 2)
        let vertical = abs(d.y) > 0.7
        if vertical {
            cg.saveGState()
            cg.translateBy(x: mid.x, y: mid.y); cg.rotate(by: -.pi / 2)
            Sk.text(txt, CGPoint(x: 0, y: -2), size: size, ax: 0.5, ay: 1)
            cg.restoreGState()
        } else {
            Sk.text(txt, CGPoint(x: mid.x, y: mid.y - 1.5), size: size, ax: 0.5, ay: 1)
        }
    }
}

/// Набор чертежей проекта
enum Drawings {
    struct Ctx {
        let p: Project
        let r: CalcResults
        let b: BuildPlan
    }

    /// Нарисовать схему в прямоугольнике (контекст y-вниз). Ставит текущий NSGraphicsContext для текста.
    static func render(_ kind: FigKind, _ c: Ctx, _ cg: CGContext, _ rect: CGRect) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        cg.saveGState()
        cg.clip(to: rect)
        cg.setFillColor(NSColor.white.cgColor)
        cg.fill(rect)
        switch kind {
        case .sitePlan: sitePlan(c, cg, rect)
        case .layout: layout(c, cg, rect)
        case .stripSection: stripSection(c, cg, rect)
        case .slabSection: slabSection(c, cg, rect)
        case .pileSection, .pileCage: pileSection(c, cg, rect, cage: kind == .pileCage)
        case .rebarCorner: rebarCorner(c, cg, rect, tee: false)
        case .rebarTee: rebarCorner(c, cg, rect, tee: true)
        case .rebarLap: rebarLap(c, cg, rect)
        case .slabEdge: slabEdge(c, cg, rect)
        case .sillNode: sillNode(c, cg, rect)
        case .anchorPlan: anchorPlan(c, cg, rect)
        case .joistPlan(let i): joistPlan(c, cg, rect, i)
        case .floorPie: pie(cg, rect, title: "Пол 1-го этажа по балкам (сверху вниз)", layers: floorLayers(c))
        case .wallElevation(let i): wallElevation(c, cg, rect, i)
        case .cornerNode: cornerNode(c, cg, rect, tee: false)
        case .teeNode: cornerNode(c, cg, rect, tee: true)
        case .bracing: bracing(c, cg, rect)
        case .openingNode: openingNode(c, cg, rect)
        case .windowInstall: windowInstall(c, cg, rect)
        case .rafterPlan: rafterPlan(c, cg, rect)
        case .eaveNode: eaveNode(c, cg, rect)
        case .ridgeNode: ridgeNode(c, cg, rect)
        case .roofPie: pie(cg, rect, title: "Кровля по скату (сверху вниз)", layers: roofLayers(c))
        case .wallPie: pie(cg, rect, title: "Наружная стена (снаружи внутрь)", layers: wallLayers(c))
        case .wallSection: wallSection(c, cg, rect)
        case .wallPlan: wallPlan(c, cg, rect)
        case .sheetLayout(let i, let layer): sheetLayout(c, cg, rect, i, layer)
        case .fasteners: fasteners(c, cg, rect)
        case .sillSteps: sillSteps(c, cg, rect)
        case .rigidity: rigidity(c, cg, rect)
        case .floorSection: floorSection(c, cg, rect)
        case .heatingLoop: heatingLoop(c, cg, rect)
        case .furniturePlan: furniturePlan(c, cg, rect)
        case .plumbingPlan: plumbingPlan(c, cg, rect)
        case .siteNetworks: siteNetworks(c, cg, rect)
        case .sewerProfile: sewerProfile(c, cg, rect)
        }
        cg.restoreGState()
        cg.setStrokeColor(NSColor(white: 0.75, alpha: 1).cgColor)
        cg.setLineWidth(0.5)
        cg.stroke(rect)
        NSGraphicsContext.restoreGraphicsState()
    }

    static let red = NSColor(srgbRed: 0.8, green: 0.15, blue: 0.1, alpha: 1)
    static let blue = NSColor(srgbRed: 0.1, green: 0.35, blue: 0.75, alpha: 1)
    static let green = NSColor(srgbRed: 0.15, green: 0.55, blue: 0.2, alpha: 1)
    static let orange = NSColor(srgbRed: 0.95, green: 0.55, blue: 0.1, alpha: 1)

    static func mm(_ m: Double) -> String { "\(Int((m * 1000).rounded()))" }

    // MARK: - Участок

    static func sitePlan(_ c: Ctx, _ cg: CGContext, _ rect: CGRect) {
        let rings = c.p.rings
        let (lo, hi) = Geo.bbox(rings)
        let side = 3.0, front = 6.0, back = 10.0
        let pl = V2(lo.x - side - 3, lo.y - front), ph = V2(hi.x + side + 3, hi.y + back)
        let s = Sk(cg, rect, lo: pl - V2(1, 3), hi: ph + V2(1, 1), pad: 18)
        // улица
        s.box(pl.x - 1, pl.y - 3, ph.x + 1, pl.y - 0.4, fill: NSColor(white: 0.9, alpha: 1), stroke: .clear)
        s.label("Улица / проезд", V2((pl.x + ph.x) / 2, pl.y - 1.7), size: 8, ax: 0.5)
        s.line(V2(pl.x - 1, pl.y), V2(ph.x + 1, pl.y), 1.4, red, dash: [8, 3])
        s.label("красная линия", V2(ph.x - 0.2, pl.y + 0.4), size: 7, ax: 1, ay: 1, color: red)
        s.poly([pl, V2(ph.x, pl.y), ph, V2(pl.x, ph.y)], fill: NSColor(srgbRed: 0.9, green: 0.96, blue: 0.88, alpha: 1), stroke: green, w: 1.2, dash: [5, 3])
        s.label("Граница участка", V2(pl.x + 0.3, ph.y - 0.4), size: 7, ay: 0, color: green)
        // зона застройки
        let bz = [V2(pl.x + 3, pl.y + 5), V2(ph.x - 3, pl.y + 5), V2(ph.x - 3, ph.y - 3), V2(pl.x + 3, ph.y - 3)]
        s.poly(bz, fill: nil, stroke: orange, w: 0.8, dash: [3, 2])
        s.label("зона допустимого размещения (ПЗЗ)", V2(pl.x + 3.2, pl.y + 5.2), size: 6.5, ay: 1, color: orange)
        for r in rings { s.poly(r, fill: NSColor(white: 0.55, alpha: 1), stroke: .black, w: 1.2) }
        s.label("Дом \(fmt(hi.x - lo.x, 1))×\(fmt(hi.y - lo.y, 1)) м", (lo + hi) / 2, size: 8, ax: 0.5, bold: true, color: .white)
        s.dim(V2(pl.x, lo.y + 0.5), V2(lo.x, lo.y + 0.5), off: 0, "≥ 3000")
        s.dim(V2(hi.x, lo.y + 0.5), V2(ph.x, lo.y + 0.5), off: 0, "≥ 3000")
        s.dim(V2(lo.x + 1, pl.y), V2(lo.x + 1, lo.y), off: 0, "≥ 5000")
        // соседний дом — противопожарный разрыв
        Sk.text("До дома на соседнем участке — ≥ 15 м (СП 4.13130.2013, табл. 1); меньше — только по согласию соседа и с мерами огнезащиты.", CGPoint(x: rect.minX + 8, y: rect.maxY - 6), size: 6.5, ay: 1, maxW: rect.width - 16)
        // площадки
        s.box(pl.x + 0.6, hi.y + 2, pl.x + 4.6, hi.y + 5, fill: NSColor(srgbRed: 0.95, green: 0.9, blue: 0.8, alpha: 1), stroke: .brown)
        s.label("склад пиломатериала\nпод навесом", V2(pl.x + 2.6, hi.y + 3.5), size: 6.5, ax: 0.5)
        s.box(ph.x - 4.5, hi.y + 5.5, ph.x - 1, hi.y + 7.8, fill: NSColor(srgbRed: 0.85, green: 0.9, blue: 0.97, alpha: 1), stroke: blue)
        s.label("бытовка", V2(ph.x - 2.75, hi.y + 6.65), size: 6.5, ax: 0.5)
        s.label("въезд миксера ≥ 3.5 м", V2(lo.x - 1, pl.y + 1.2), size: 6.5, ax: 0.5, color: blue)
        s.line(V2(lo.x - 1, pl.y - 2.5), V2(lo.x - 1, pl.y + 0.8), 2.2, blue)
    }

    static func layout(_ c: Ctx, _ cg: CGContext, _ rect: CGRect) {
        let sc = c.b.works.scheme
        guard !sc.obnoska.isEmpty else { return }
        let (lo, hi) = Geo.bbox([sc.obnoska])
        let s = Sk(cg, rect, lo: lo, hi: hi, pad: 22, top: 12)
        s.poly([sc.site.lo, V2(sc.site.hi.x, sc.site.lo.y), sc.site.hi, V2(sc.site.lo.x, sc.site.hi.y)], fill: NSColor(srgbRed: 0.95, green: 0.9, blue: 0.82, alpha: 1), stroke: .brown, w: 0.6, dash: [4, 3])
        for (a, b, w) in sc.footprint { s.line(a, b, CGFloat(w) * s.sc, NSColor(white: 0.7, alpha: 1)) }
        for ring in sc.slab { s.poly(ring, fill: NSColor(white: 0.75, alpha: 1), stroke: nil) }
        for pl in sc.piles { s.dot(pl, 2.5, .black) }
        for (a, b) in sc.strings { s.line(a, b, 0.6, red, dash: [5, 3]) }
        s.poly(sc.obnoska, fill: nil, stroke: orange, w: 2)
        for post in sc.posts { s.box(post.x - 0.06, post.y - 0.06, post.x + 0.06, post.y + 0.06, fill: .brown, stroke: .brown) }
        for bc in sc.beacons { s.dot(bc, 1.4, blue) }
        let (fl, fh) = Geo.bbox(c.p.rings)
        s.dim(V2(fl.x, lo.y + 0.4), V2(fh.x, lo.y + 0.4), off: 0, "оси " + mm(fh.x - fl.x))
        s.dim(V2(lo.x + 0.4, fl.y), V2(lo.x + 0.4, fh.y), off: 0, "оси " + mm(fh.y - fl.y))
        Sk.text("■ обноска (доска 25×150 на столбиках 50×50 через 1.5 м)   — шнуры по граням   • маяки/метки верха", CGPoint(x: rect.minX + 8, y: rect.minY + 10), size: 7, ay: 0.5)
    }

    // MARK: - Сечения фундамента

    static func stripSection(_ c: Ctx, _ cg: CGContext, _ rect: CGRect) {
        let r = c.r.strip
        guard let sec = r.ext else { return }
        let H = sec.H, b = sec.b, d = r.depth
        let cush = r.cushion
        let s = Sk(cg, rect, lo: V2(-b / 2 - 0.45, -d - cush - 0.1), hi: V2(b / 2 + 0.75, H - d + 0.35), pad: 16, right: 60)
        // грунт
        s.box(-b / 2 - 0.45, -d - cush - 0.1, -b / 2 - 0.3, 0, .soil)
        s.box(b / 2 + 0.3, -d - cush - 0.1, b / 2 + 0.45, 0, .soil)
        s.box(-b / 2 - 0.3, -d - cush, b / 2 + 0.3, -d, .sand)
        s.label("песчаная подушка \(mm(cush))", V2(-b / 2 - 0.25, -d - cush / 2), size: 6.5)
        let y0 = -d, top = H - d
        if sec.isT {
            s.box(-b / 2, y0, b / 2, y0 + sec.soleH, .concrete)
            s.box(-sec.stemW / 2, y0 + sec.soleH, sec.stemW / 2, top, .concrete)
        } else {
            s.box(-b / 2, y0, b / 2, top, .concrete)
        }
        s.line(V2(-b / 2 - 0.45, 0), V2(b / 2 + 0.45, 0), 1, green, dash: [5, 3])
        s.label("±0.000 — уровень земли", V2(b / 2 + 0.05, 0.03), size: 6.5, ay: 1, color: green)
        // гидроизоляция по верху и боковая
        s.line(V2(-sec.stemW / 2, top + 0.008), V2(sec.stemW / 2, top + 0.008), 2.2, .black)
        s.line(V2(sec.stemW / 2 + 0.008, top), V2(sec.stemW / 2 + 0.008, y0 + (sec.isT ? sec.soleH : 0)), 1.6, NSColor.darkGray)
        // хомут и стержни
        let cv = sec.cover
        s.poly([V2(-sec.stemW / 2 + cv, y0 + cv), V2(sec.stemW / 2 - cv, y0 + cv), V2(sec.stemW / 2 - cv, top - cv), V2(-sec.stemW / 2 + cv, top - cv)], fill: nil, stroke: orange, w: 1.3)
        func dots(_ n: Int, _ dd: Int, _ w: Double, _ y: Double) {
            for i in 0..<n {
                let x = n == 1 ? 0 : -w / 2 + cv + Double(i) * (w - 2 * cv) / Double(n - 1)
                s.dot(V2(x, y), max(2.2, CGFloat(Double(dd) / 2000) * s.sc), red)
            }
        }
        dots(sec.topN, sec.topD, sec.stemW, top - cv)
        dots(sec.botN, sec.botD, sec.b, y0 + cv)
        if sec.sideRows > 0 { for k in 1...sec.sideRows { dots(2, sec.sideD, sec.stemW, y0 + cv + (H - 2 * cv) * Double(k) / Double(sec.sideRows + 1)) } }
        if sec.isT && sec.soleD > 0 { s.line(V2(-b / 2 + cv, y0 + cv - 0.012), V2(b / 2 - cv, y0 + cv - 0.012), 1.2, red) }
        // фиксаторы
        for x in [-sec.stemW / 2 + cv + 0.03, sec.stemW / 2 - cv - 0.03] {
            s.poly([V2(x - 0.02, y0), V2(x, y0 + cv), V2(x + 0.02, y0)], fill: blue, stroke: nil)
        }
        s.dim(V2(-b / 2, y0), V2(b / 2, y0), off: -0.12, mm(b))
        s.dim(V2(-b / 2, y0), V2(-b / 2, top), off: 0.1, "H = " + mm(H))
        s.dim(V2(sec.stemW / 2, 0), V2(sec.stemW / 2, top), off: -0.06 - sec.stemW, "цоколь " + mm(top))
        let rx = b / 2 + 0.33
        s.leader(V2(0, top - cv), V2(rx, top - 0.02), "верх: \(sec.topN)Ø\(sec.topD) \(c.p.rebar.rawValue)")
        s.leader(V2(b / 2 - cv - 0.01, y0 + cv), V2(rx, y0 + 0.12), "низ: \(sec.botN)Ø\(sec.botD) \(c.p.rebar.rawValue)")
        s.leader(V2(sec.stemW / 2 - cv, (y0 + top) / 2), V2(rx, (y0 + top) / 2 + 0.1), "хомут Ø\(sec.clampD) А240 шаг \(mm(sec.clampStep))")
        s.leader(V2(-sec.stemW / 2 + cv + 0.03, y0 + cv / 2), V2(rx, y0 - 0.12), "фиксатор «стульчик» \(mm(cv)) мм")
        s.leader(V2(0, top + 0.008), V2(rx, top + 0.2), "гидроизоляция 2 слоя (под обвязку)")
    }

    static func slabSection(_ c: Ctx, _ cg: CGContext, _ rect: CGRect) {
        let r = c.r.slab
        let t = r.t, w = 1.6
        let g = -SlabCalc.aboveGround
        let s = Sk(cg, rect, lo: V2(-0.4, -t - c.p.slabCushion - 0.15), hi: V2(w + 0.4, 0.45), pad: 16, right: 70)
        s.box(-0.3, -t - c.p.slabCushion, w, -t, .sand)
        if c.p.soil.heave != .none { s.box(-0.3, -t - 0.1, w, -t, .insulation) }
        s.box(0, -t + (c.p.soil.heave != .none ? 0 : 0), w, 0, .concrete)
        s.line(V2(-0.4, g), V2(w + 0.4, g), 1, green, dash: [5, 3])
        s.dim(V2(w + 0.25, g), V2(w + 0.25, 0), off: 0.05, mm(SlabCalc.aboveGround))
        let cv = r.cover
        var x = cv
        while x < w - 0.01 { s.dot(V2(x, -t + cv + 0.01), 2, red); s.dot(V2(x, -cv - 0.01), 2, red); x += r.step }
        s.line(V2(cv, -t + cv), V2(w, -t + cv), 1.2, red)
        s.line(V2(cv, -cv), V2(w, -cv), 1.2, red)
        s.poly([V2(w, -cv), V2(cv, -cv), V2(cv, -t + cv), V2(w, -t + cv)], fill: nil, stroke: orange, w: 1.2, close: false)
        // стена
        s.box(0.02, 0, 0.02 + c.b.frame.studExt.wm, 0.4, .wood)
        s.dim(V2(0, -t), V2(0, 0), off: 0.15, "t = " + mm(t))
        s.leader(V2(0.6, -cv), V2(w + 0.1, 0.25), "верхняя сетка Ø\(r.d) шаг \(mm(r.step))")
        s.leader(V2(0.9, -t + cv), V2(w + 0.1, -t - 0.05), "нижняя сетка Ø\(r.d) шаг \(mm(r.step))")
        s.leader(V2(cv, -t / 2), V2(w + 0.1, -t / 2), "П-образный стержень по торцу")
        s.leader(V2(0.5, -t - c.p.slabCushion / 2), V2(w + 0.1, -t - c.p.slabCushion / 2 - 0.05), "подушка \(mm(c.p.slabCushion)) Купл ≥ 0.95")
    }

    static func pileSection(_ c: Ctx, _ cg: CGContext, _ rect: CGRect, cage: Bool) {
        let r = c.r.piles
        let L = min(r.L, 3.5), bg = r.bg, hg = r.hg
        let s = Sk(cg, rect, lo: V2(-bg / 2 - 0.5, -L - 0.2), hi: V2(bg / 2 + 0.5, hg + 0.3), pad: 14, right: 90)
        s.box(-bg / 2 - 0.5, -L - 0.2, bg / 2 + 0.5, 0, .soil)
        s.box(-r.d / 2, -L, r.d / 2, 0.15, r.type == .screw ? .steel : .concrete)
        if r.type == .boredEnlarged { s.poly((0..<16).map { i in let a = Double(i) / 16 * 2 * .pi; return V2(cos(a) * r.D / 2, -L + 0.15 + sin(a) * r.D / 4) }, fill: Sk.fillFor(.concrete), stroke: .black) }
        s.box(-bg / 2, 0.15, bg / 2, 0.15 + hg, .concrete)
        s.box(-bg / 2, 0.0, bg / 2, 0.15, fill: .white, stroke: .gray)
        s.label("зазор 100–150 мм (пенополистирол)", V2(bg / 2 + 0.05, 0.07), size: 6)
        let cv = r.cover
        if r.type != .screw {
            for x in [-r.d / 2 + 0.05, r.d / 2 - 0.05] { s.bar(V2(x, -L + 0.05), V2(x, 0.15 + hg - cv), d: r.cageD) }
            var y = -L + 0.1
            while y < 0.15 { s.line(V2(-r.d / 2 + 0.05, y), V2(r.d / 2 - 0.05, y), 0.8, orange); y += 0.4 }
        }
        for x in [-bg / 2 + cv, bg / 2 - cv] {
            s.dot(V2(x, 0.15 + cv), 2.5, red); s.dot(V2(x, 0.15 + hg - cv), 2.5, red)
        }
        s.poly([V2(-bg / 2 + cv, 0.15 + cv), V2(bg / 2 - cv, 0.15 + cv), V2(bg / 2 - cv, 0.15 + hg - cv), V2(-bg / 2 + cv, 0.15 + hg - cv)], fill: nil, stroke: orange, w: 1.2)
        s.line(V2(-bg / 2 - 0.5, 0), V2(bg / 2 + 0.5, 0), 1, green, dash: [5, 3])
        let rx = bg / 2 + 0.3
        s.leader(V2(r.d / 2 - 0.05, -L / 2), V2(rx, -L / 2), r.type == .screw ? "винтовая свая Ø\(mm(r.d)), бетон в стволе" : "каркас \(r.cageN)Ø\(r.cageD), кольца Ø6 шаг 400")
        s.leader(V2(r.d / 2 - 0.05, 0.15 + hg / 2), V2(rx, 0.15 + hg + 0.15), "выпуски в ростверк ≥ 30d")
        s.leader(V2(bg / 2 - cv, 0.15 + cv), V2(rx, 0.15 + 0.2), "ростверк \(mm(bg))×\(mm(hg)): \(r.botN)Ø\(r.botD) низ, \(r.topN)Ø\(r.topD) верх, хомут Ø\(r.stirD) шаг \(mm(r.stirStep))")
        s.dim(V2(-bg / 2, -L), V2(-bg / 2, 0), off: 0.25, "L = " + mm(r.L))
        _ = cage
    }

    /// План угла (или Т-примыкания) ленты с Г-/П-образными стержнями
    static func rebarCorner(_ c: Ctx, _ cg: CGContext, _ rect: CGRect, tee: Bool) {
        let isPile = c.p.selectedFoundation == .piles
        let w = isPile ? c.r.piles.bg : (c.r.strip.ext?.stemW ?? 0.4)
        let cv = isPile ? c.r.piles.cover : (c.r.strip.ext?.cover ?? 0.04)
        let dd = isPile ? c.r.piles.topD : (c.r.strip.ext?.topD ?? 12)
        let lap = max(isPile ? RC.lap(d: dd, c: c.p.concrete, r: c.p.rebar) : c.r.strip.lap, 0.3)
        let step = isPile ? c.r.piles.stirStep : (c.r.strip.ext?.clampStep ?? 0.3)
        let L = max(1.6, lap + 0.8)
        let lo = V2(tee ? -L : -w / 2, -L), hi = V2(L, w / 2)
        let s = Sk(cg, rect, lo: lo - V2(0.05, 0.05), hi: hi + V2(0.05, 0.25), pad: 16, right: 0, top: 0)
        // бетон
        s.box(tee ? -L : -w / 2, -w / 2, L, w / 2, fill: NSColor(white: 0.92, alpha: 1), stroke: .gray)
        s.box(-w / 2, -L, w / 2, -w / 2, fill: NSColor(white: 0.92, alpha: 1), stroke: .gray)
        let i0 = -w / 2 + cv, i1 = w / 2 - cv
        let barC = NSColor(white: 0.25, alpha: 1)
        // продольные стержни основной ленты (горизонтальные)
        if tee {
            s.bar(V2(-L, i1), V2(L, i1), d: dd, barC)
            s.bar(V2(-L, i0), V2(L, i0), d: dd, barC)
        } else {
            s.bar(V2(i0 + 0.04, i1), V2(L, i1), d: dd, barC)     // наружный ряд обрывается у угла
            s.bar(V2(i1 + 0.04, i0), V2(L, i0), d: dd, barC)
        }
        // стержни примыкающей ленты (вертикальные)
        if tee {
            s.bar(V2(i0, -L), V2(i0, i0 - 0.04), d: dd, barC)
            s.bar(V2(i1, -L), V2(i1, i0 - 0.04), d: dd, barC)
        } else {
            s.bar(V2(i0, -L), V2(i0, i1 - 0.04), d: dd, barC)
            s.bar(V2(i1, -L), V2(i1, i0 - 0.04), d: dd, barC)
        }
        // Г-образные стержни
        if tee {
            s.bar(V2(i0 + 0.012, -lap + i0), V2(i0 + 0.012, i1 - 0.012), d: dd, red); s.bar(V2(i0 + 0.012, i1 - 0.012), V2(-lap, i1 - 0.012), d: dd, red)
            s.bar(V2(i1 - 0.012, -lap + i0), V2(i1 - 0.012, i1 - 0.012), d: dd, red); s.bar(V2(i1 - 0.012, i1 - 0.012), V2(lap, i1 - 0.012), d: dd, red)
        } else {
            s.bar(V2(lap, i1 - 0.012), V2(i0 + 0.012, i1 - 0.012), d: dd, red); s.bar(V2(i0 + 0.012, i1 - 0.012), V2(i0 + 0.012, -lap), d: dd, red)
            s.bar(V2(lap, i0 + 0.012), V2(i1 - 0.012, i0 + 0.012), d: dd, red); s.bar(V2(i1 - 0.012, i0 + 0.012), V2(i1 - 0.012, -lap), d: dd, red)
        }
        // хомуты
        var u = w / 2 + 0.05
        while u < L { s.line(V2(u, i0), V2(u, i1), 1, orange); u += step }
        u = -w / 2 - 0.05
        while u > -L { s.line(V2(i0, u), V2(i1, u), 1, orange); if tee { s.line(V2(u, i0), V2(u, i1), 1, orange) }; u -= step }
        s.dim(V2(w / 2, w / 2 + 0.02), V2(lap, w / 2 + 0.02), off: 0.1, "≥ \(mm(lap))")
        s.dim(V2(-w / 2 - 0.02, -w / 2), V2(-w / 2 - 0.02, -lap), off: 0.1, "≥ \(mm(lap))")
        Sk.text(tee ? "Т-образное примыкание: стержни примыкающей ленты\nзаводятся Г-образными элементами в основную ленту\nна длину анкеровки в обе стороны."
                    : "Угол: прямые стержни не пересекаются «крестом» —\nкаждый ряд соединяется Г-образным стержнем того же Ø\nс полками на длину анкеровки/нахлёста.",
                CGPoint(x: rect.minX + 10, y: rect.maxY - 10), size: 7, ay: 1, maxW: 260)
        let tx = tee ? w / 2 + 0.15 : L * 0.45
        s.leader(V2(lap * 0.6, i1 - 0.012), V2(tx, -L * 0.35), "Г-образный стержень Ø\(dd) \(c.p.rebar.rawValue)", size: 7)
        s.leader(V2(L * 0.85, i0), V2(tx, -L * 0.6), "продольные стержни Ø\(dd)", size: 7)
        s.leader(V2(w / 2 + 0.05 + step, (i0 + i1) / 2), V2(tx, -L * 0.85), "хомуты шаг \(mm(step)), вязка в каждом пересечении", size: 7)
    }

    static func rebarLap(_ c: Ctx, _ cg: CGContext, _ rect: CGRect) {
        let lap = c.p.selectedFoundation == .strip ? c.r.strip.lap : RC.lap(d: c.r.slab.d, c: c.p.concrete, r: c.p.rebar)
        let dd = c.p.selectedFoundation == .strip ? (c.r.strip.ext?.botD ?? 12) : c.r.slab.d
        let s = Sk(cg, rect, lo: V2(-0.3, -0.12), hi: V2(lap + 0.3, 0.12), pad: 18)
        s.bar(V2(-0.3, 0.012), V2(lap, 0.012), d: dd, NSColor(white: 0.25, alpha: 1))
        s.bar(V2(0, -0.012), V2(lap + 0.3, -0.012), d: dd, red)
        for x in [0.03, lap / 2, lap - 0.03] {
            s.poly([V2(x - 0.015, 0.03), V2(x + 0.015, -0.03)], fill: nil, stroke: blue, w: 1.6, close: false)
            s.poly([V2(x + 0.015, 0.03), V2(x - 0.015, -0.03)], fill: nil, stroke: blue, w: 1.6, close: false)
        }
        s.dim(V2(0, 0.03), V2(lap, 0.03), off: 0.04, "нахлёст l = \(mm(lap)) мм (Ø\(dd) \(c.p.rebar.rawValue), \(c.p.concrete.rawValue))")
        s.label("вязка в 3 точках проволокой Ø1.2; стыки соседних стержней — вразбежку на 1.3l", V2(lap / 2, -0.07), size: 7, ax: 0.5, ay: 0)
    }

    static func slabEdge(_ c: Ctx, _ cg: CGContext, _ rect: CGRect) { slabSection(c, cg, rect) }

    // MARK: - Обвязка

    static func sillNode(_ c: Ctx, _ cg: CGContext, _ rect: CGRect) {
        let F = c.b.frame
        let slab = c.p.selectedFoundation == .slab
        let D = F.studExt.wm
        let stemW = slab ? 0.6 : (c.p.selectedFoundation == .strip ? (c.r.strip.ext?.stemW ?? 0.4) : c.r.piles.bg)
        let sill = slab ? 0.0 : F.sillSec.tm
        let jh = F.floors.first?.check.sec.wm ?? 0.2
        let wood = !slab && c.p.groundFloor == .wood
        let x0 = -stemW / 2               // наружная грань фундамента (снаружи — слева)
        let s = Sk(cg, rect, lo: V2(x0 - 0.35, -0.45), hi: V2(x0 + max(stemW, 0.9) + 0.1, sill + (wood ? jh + 0.03 : 0) + 0.5), pad: 14, right: 190)
        // фундамент
        s.box(x0, -0.45, x0 + stemW, 0, .concrete)
        if slab { s.label("плита", V2(x0 + 0.05, -0.2), size: 7) }
        s.box(x0 - 0.35, -0.45, x0, -0.3, .soil)
        // гидроизоляция
        s.box(x0 - 0.02, 0, x0 + D + 0.05, 0.008, fill: .black, stroke: .black)
        // обвязка
        var z = 0.008
        if !slab {
            s.box(x0, z + 0.004, x0 + F.sillSec.wm, z + sill, .timberCut)
            z += sill
        }
        // анкер
        let ax = x0 + (slab ? D : F.sillSec.wm) / 2
        s.line(V2(ax, -0.15), V2(ax, z + 0.03), 2.2, NSColor(white: 0.35, alpha: 1))
        s.box(ax - 0.022, z, ax + 0.022, z + 0.006, fill: .darkGray)
        s.box(ax - 0.012, z + 0.006, ax + 0.012, z + 0.02, fill: .black)
        s.dim(V2(ax + 0.02, -0.15), V2(ax + 0.02, 0), off: -0.05, "150")
        var floorTop = z
        if wood {
            s.box(x0, z, x0 + 0.05, z + jh, .wood)
            s.box(x0 + 0.05, z, x0 + max(stemW, 0.9), z + jh, .board)
            floorTop = z + jh
            s.box(x0, floorTop, x0 + max(stemW, 0.9), floorTop + 0.022, .board)
            floorTop += 0.022
        }
        // стена
        s.box(x0, floorTop, x0 + D, floorTop + 0.05, .timberCut)
        s.box(x0, floorTop + 0.05, x0 + D, floorTop + 0.42, .wood)
        s.box(x0 - 0.009, floorTop - (wood ? jh + 0.02 : 0), x0, floorTop + 0.42, .board)
        s.box(x0 + D, floorTop + 0.05, x0 + D + 0.0125, floorTop + 0.42, fill: NSColor(white: 0.95, alpha: 1))
        let lx = x0 + max(stemW, 0.9) + 0.05
        s.leader(V2(x0 + D / 2, floorTop + 0.3), V2(lx, floorTop + 0.38), "Стойка каркаса \(F.studExt.label) шаг \(mm(c.p.studStep))")
        s.leader(V2(x0 + D / 2, floorTop + 0.025), V2(lx, floorTop + 0.22), "Нижняя обвязка стены \(F.studExt.label)")
        s.leader(V2(x0 - 0.005, floorTop + 0.15), V2(lx, floorTop + 0.48), "ОСП-3 9 мм снаружи (заходит на обвязочную доску)")
        if wood {
            s.leader(V2(x0 + 0.5, floorTop - 0.01), V2(lx, floorTop + 0.07), "Настил ОСП-3 22 мм шпунт")
            s.leader(V2(x0 + 0.3, z + jh / 2), V2(lx, z + jh * 0.55), "Балка пола \(F.floors.first?.check.title ?? "") шаг \(mm(F.floors.first?.check.step ?? 0.6)), опора ≥ 100 мм")
            s.leader(V2(x0 + 0.025, z + jh * 0.3), V2(lx, z + jh * 0.2), "Обвязочная доска \(F.floors.first?.check.sec.label ?? "") по контуру")
        }
        if !slab { s.leader(V2(x0 + F.sillSec.wm * 0.75, 0.008 + sill / 2), V2(lx, sill * 0.4), "\(c.p.sillType == .timber ? "Обвязочный брус" : "Лежень") \(F.sillSec.label), антисептированный") }
        s.leader(V2(ax, z + 0.012), V2(lx, sill + 0.015 - (wood ? 0 : 0.0) - 0.04), "Гайка М12 + шайба увелич. DIN 9021")
        s.leader(V2(x0 + D + 0.03, 0.004), V2(lx, -0.06), "Гидроизоляция ТПП/ХПП 2 слоя + лента ППЭ 8 мм")
        s.leader(V2(ax, -0.1), V2(lx, -0.2), "Анкер: шпилька М12 кл. 5.8, хим. анкер, заделка 150, шаг ≤ 2000, ≤ 300 от концов")
        s.leader(V2(x0 + 0.1, -0.35), V2(lx, -0.36), slab ? "Плита фундамента" : "Лента фундамента (верх в горизонт ±10 мм)")
    }

    static func anchorPlan(_ c: Ctx, _ cg: CGContext, _ rect: CGRect) {
        let F = c.b.frame
        let (lo, hi) = Geo.bbox(c.p.rings)
        let s = Sk(cg, rect, lo: lo - V2(0.8, 0.8), hi: hi + V2(0.8, 0.8), pad: 16)
        for (a, b) in F.sillLines { s.line(a, b, max(3, CGFloat(F.sillSec.wm) * s.sc), NSColor(srgbRed: 0.85, green: 0.7, blue: 0.45, alpha: 1)) }
        for a in F.anchors { s.dot(a, 2.6, red) }
        if let (a, b) = F.sillLines.first {
            let d = (b - a).unit
            s.dim(a, a + d * 0.3, off: 0.45, "300")
            let pts = F.anchors.filter { Geo.distToSegment($0, a, b) < 0.01 }.sorted { dot2($0 - a, d) < dot2($1 - a, d) }
            if pts.count > 2 { s.dim(pts[1], pts[2], off: 0.45, mm((pts[2] - pts[1]).len)) }
        }
        s.label("анкеров: \(F.anchors.count) шт.  ● анкер М12   ▬ обвязка \(F.sillSec.label)", V2(lo.x - 0.7, hi.y + 0.6), size: 7.5)
    }

    // MARK: - Перекрытия

    static func joistPlan(_ c: Ctx, _ cg: CGContext, _ rect: CGRect, _ i: Int) {
        let F = c.b.frame
        guard i < F.floors.count || F.attic != nil else { return }
        let j = i < F.floors.count ? F.floors[i] : F.attic!
        let (lo, hi) = Geo.bbox(c.p.rings)
        let s = Sk(cg, rect, lo: lo - V2(0.8, 0.8), hi: hi + V2(0.8, 1.0), pad: 14)
        for r in c.p.rings { s.poly(r, fill: NSColor(white: 0.97, alpha: 1), stroke: .black, w: 1) }
        for (a, b) in j.supports { s.line(a, b, 5, NSColor(white: 0.55, alpha: 1)) }
        for (a, b) in j.lines { s.line(a, b, max(1, CGFloat(j.check.sec.tm * Double(j.check.count)) * s.sc), NSColor(srgbRed: 0.75, green: 0.55, blue: 0.3, alpha: 1)) }
        for (a, b) in j.beams {
            s.line(a, b, 5, red, dash: [8, 4])
            s.label("прогон", (a + b) / 2, size: 7, ax: 0.5, ay: 1.2, color: red, bg: true)
        }
        s.label("\(j.title): \(j.check.title) шаг \(mm(j.check.step)), макс. пролёт \(fmt(j.maxSpan)) м, \(j.lines.count) балок. Серым — опоры (стены/обвязка).", V2(lo.x - 0.7, hi.y + 0.7), size: 7.5)
        if let l = j.lines.first { s.dim(l.0, l.1, off: -0.4, mm((l.1 - l.0).len)) }
        if j.lines.count > 1 { s.dim(j.lines[0].0, j.lines[1].0, off: 0.3, mm((j.lines[1].0 - j.lines[0].0).len)) }
    }

    // MARK: - Стены

    static func color(_ k: MemberKind) -> NSColor { let c = k.rgb; return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1) }

    static func wallElevation(_ c: Ctx, _ cg: CGContext, _ rect: CGRect, _ i: Int) {
        guard i < c.b.frame.walls.count else { return }
        let w = c.b.frame.walls[i]
        let s = Sk(cg, rect, lo: V2(-0.3, -0.45), hi: V2(w.length + 0.3, w.height + 0.25), pad: 12)
        for o in w.openings { s.box(o.u0, o.z0, o.u1, o.z1, fill: NSColor(srgbRed: 0.88, green: 0.94, blue: 1, alpha: 1), stroke: blue, w: 0.6) }
        for rc in w.rects {
            s.box(rc.u0, rc.z0, rc.u1, rc.z1, fill: color(rc.kind), stroke: NSColor(white: 0.3, alpha: 1), w: 0.4)
            if rc.kind == .header { s.label("перемычка 2×(50×\(mm(rc.z1 - rc.z0)))", V2((rc.u0 + rc.u1) / 2, (rc.z0 + rc.z1) / 2), size: 5.5, ax: 0.5) }
        }
        for b in w.braces { s.line(V2(b.u0, b.z0), V2(b.u1, b.z1), 2.5, color(.brace)) }
        // места временных укосин (ставятся с внутренней стороны при подъёме стены)
        for t in w.temps {
            s.poly([V2(t - 0.07, -0.02), V2(t + 0.07, -0.02), V2(t, 0.1)], fill: color(.tempBrace), stroke: nil)
        }
        if !w.temps.isEmpty { s.label("▲ — временные укосины 25×100 при подъёме (\(w.temps.count) шт.)", V2(w.length, w.height + 0.12), size: 6.5, ax: 1, color: color(.tempBrace)) }
        for o in w.openings {
            s.label(o.label, V2((o.u0 + o.u1) / 2, (o.z0 + o.z1) / 2), size: 6, ax: 0.5, color: blue, bg: true)
            s.dim(V2(o.u0, o.z0), V2(o.u1, o.z0), off: -0.12, mm(o.u1 - o.u0))
        }
        s.dim(V2(0, 0), V2(w.length, 0), off: -0.33, "\(w.name): \(mm(w.length))")
        s.dim(V2(w.length, 0), V2(w.length, w.height), off: -0.15, mm(w.height))
        // шаг стоек
        let studs = w.rects.filter { $0.kind == .stud }.map { ($0.u0 + $0.u1) / 2 }.sorted()
        if studs.count > 1 { s.dim(V2(studs[0], w.height), V2(studs[1], w.height), off: 0.1, mm(studs[1] - studs[0])) }
    }

    static func cornerNode(_ c: Ctx, _ cg: CGContext, _ rect: CGRect, tee: Bool) {
        let F = c.b.frame
        let D = F.studExt.wm
        let t = 0.05
        let Dp = tee ? (c.p.partitions.first?.onFoundation ?? true ? F.studInt.wm : F.studPart.wm) : D
        let L = 1.0
        let s = Sk(cg, rect, lo: V2(-0.25, tee ? -0.25 : -0.9), hi: V2(L + 0.1, tee ? D + 0.8 : D + 0.25), pad: 12, right: 190)
        // проходная стена (горизонтальная): от x=0 (наружная грань) вправо; y: 0 — снаружи, D — внутри
        let x0 = tee ? -0.2 : 0.0
        s.box(x0, -0.009, L, 0, .board)                       // ОСП снаружи
        s.box(x0, D, L, D + 0.0125, fill: NSColor(white: 0.95, alpha: 1))   // ГКЛ
        s.box(x0, 0, L, D, .insulation)
        let studXs: [Double] = tee ? [0.35 - Dp / 2 - t, 0.35 + Dp / 2, 0.9] : [0, D, 0.6]
        for x in studXs { s.box(x, 0, x + t, D, .timberCut) }
        // примыкающая стена (вертикальная, вниз от внутренней грани)
        let ax = tee ? 0.35 - Dp / 2 : 0
        let aw = tee ? Dp : D
        s.box(ax, D + (tee ? 0.0125 : 0), ax + aw, D + (tee ? 0.0125 : 0) - 0.0, fill: .clear)
        let top = tee ? D + 0.0125 : D
        s.box(ax, -0.9, ax + aw, top - (tee ? 0 : 0) - (tee ? 0 : 0), fill: nil, stroke: .clear)
        if tee {
            s.box(ax, D - 0.6 - 0.9 + 0.6, ax + aw, D, fill: .clear, stroke: .clear)
            s.box(ax, -0.9 + D, ax + t, D + 0.0125 + 0.0, fill: nil, stroke: .clear)
        }
        // стойки примыкающей стены
        let yTop = tee ? D + 0.0125 : D
        let yEnd = tee ? D + 0.0125 + 0.0 : D
        _ = yEnd
        if tee {
            s.box(ax, yTop, ax + aw, yTop + 0.0, fill: nil, stroke: .clear)
            s.box(ax, yTop, ax + aw, yTop + 0.05, .timberCut)      // торцевая стойка перегородки (вид сверху — разрез)
        }
        let L2 = 0.9
        let y0 = tee ? yTop : D
        // перегородка/стена идёт «вверх» в сторону помещения — рисуем в сторону +y
        let ext = tee ? 0.0 : -D
        _ = ext
        let wallLo = tee ? y0 : -L2 + D
        if tee {
            s.box(ax, y0 + 0.05, ax + aw, y0 + 0.75, .insulation)
            s.box(ax - 0.0125, y0, ax, y0 + 0.75, fill: NSColor(white: 0.95, alpha: 1))
            s.box(ax + aw, y0, ax + aw + 0.0125, y0 + 0.75, fill: NSColor(white: 0.95, alpha: 1))
            s.box(ax, y0 + 0.6, ax + aw, y0 + 0.65, .timberCut)
            s.leader(V2(ax + aw / 2, y0 + 0.025), V2(L + 0.05, D + 0.45), "Торцевая стойка перегородки → саморезы 5×90 шаг 400 в доп. стойки")
            s.leader(V2(0.35 - Dp / 2 - t / 2, D / 2), V2(L + 0.05, D * 0.75), "Доп. стойки в наружной стене по краям перегородки")
            s.leader(V2(0.6, D / 2), V2(L + 0.05, D * 0.2), "Утеплитель \(mm(c.b.woolWall))")
            s.leader(V2(0.6, -0.005), V2(L + 0.05, -0.15), "ОСП-3 9 мм + мембрана + фасад")
            s.leader(V2(ax + aw + 0.006, y0 + 0.55), V2(L + 0.05, y0 + 0.72), "ГКЛ 12.5 мм с двух сторон")
        } else {
            // примыкающая стена вниз (по -y), её наружная грань x=0
            s.box(0, wallLo, D, 0, fill: nil, stroke: .clear)
            s.box(-0.009, -L2, 0, D, .board)
            s.box(0, -L2, D, 0, .insulation)
            s.box(0, -0.05, D, 0, .timberCut)
            s.box(0, -L2 + 0.25, D, -L2 + 0.3, .timberCut)
            s.box(D, -L2, D + 0.0125, D, fill: NSColor(white: 0.95, alpha: 1))
            s.leader(V2(t / 2, D / 2), V2(L + 0.05, D + 0.12), "Торцевая стойка проходной стены")
            s.leader(V2(D + t / 2, D / 2), V2(L + 0.05, D * 0.5), "Доп. стойка на толщину стены (опора ГКЛ угла)")
            s.leader(V2(D / 2, -0.025), V2(L + 0.05, -0.12), "Крайняя стойка примыкающей стены, стяжка саморезами 5×90 шаг 300")
            s.leader(V2(D / 2, -0.5), V2(L + 0.05, -0.45), "Утеплитель закладывается в угол ДО сборки")
            s.leader(V2(-0.005, -0.6), V2(L + 0.05, -0.75), "ОСП-3 9 мм внахлёст на угол")
        }
        s.dim(V2(x0 + (tee ? 0.2 : 0), 0), V2(x0 + (tee ? 0.2 : 0), D), off: 0.12, mm(D))
    }

    static func bracing(_ c: Ctx, _ cg: CGContext, _ rect: CGRect) {
        let F = c.b.frame
        let h = F.wallHeights.first ?? 2.6
        let L = 3.6
        let s = Sk(cg, rect, lo: V2(-0.2, -0.3), hi: V2(L + 2.3, h + 0.3), pad: 12)
        // фасад стены
        s.box(0, 0, L, 0.05, fill: color(.bottomPlate))
        s.box(0, h - 0.1, L, h, fill: color(.topPlate))
        var x = 0.0
        while x <= L - 0.05 { s.box(x, 0.05, x + 0.05, h - 0.1, fill: color(.stud), stroke: .gray, w: 0.3); x += c.p.studStep }
        if c.p.sheathing.hasBraces {
            s.line(V2(0.1, 0.05), V2(0.1 + (h - 0.15) * 0.75, h - 0.1), 3, color(.brace))
            s.leader(V2(0.1 + (h - 0.15) * 0.37, h / 2), V2(1.6, h + 0.15), "Раскос 25×100 врезной, 45–60°, по 2 гвоздя 4×100 в каждую стойку")
        }
        s.box(-0.15, -0.3, L + 2.3, 0, .board)
        s.label("платформа перекрытия", V2(L + 1.1, -0.15), size: 7, ax: 0.5)
        // вид сбоку справа: стена + укосина
        let sx = L + 0.6
        s.box(sx, 0, sx + F.studExt.wm, h, .wood)
        s.line(V2(sx + F.studExt.wm, h * 0.65), V2(sx + F.studExt.wm + h * 0.6, 0), 3, color(.tempBrace))
        s.box(sx + F.studExt.wm + h * 0.6 - 0.05, 0, sx + F.studExt.wm + h * 0.6 + 0.05, 0.08, fill: .brown)
        s.leader(V2(sx + F.studExt.wm + h * 0.3, h * 0.33), V2(sx + 0.3, h + 0.15), "Временная укосина 25×100 через 2.4 м,\nснимается после обшивки и перекрытия")
        s.label("вид сбоку", V2(sx, -0.22), size: 7)
    }

    static func openingNode(_ c: Ctx, _ cg: CGContext, _ rect: CGRect) {
        let row = c.b.openings.first { !$0.opening.kind.isDoor && !$0.wall.hasPrefix("П") } ?? c.b.openings.first
        let blk = row?.block ?? StdBlock.catalog[5]
        let o = row?.opening
        let w = o?.width ?? blk.roW, hgt = o?.height ?? blk.roH, sill = o?.sill ?? 0.85
        let H = c.b.frame.wallHeights.first ?? 2.6
        let hh = row?.header?.sec.wm ?? 0.2
        let x0 = 0.4, x1 = x0 + w
        let L = x1 + 0.4
        let s = Sk(cg, rect, lo: V2(-0.25, -0.35), hi: V2(L + 0.1, H + 0.15), pad: 12, right: 190)
        s.box(0, 0, L, 0.05, fill: color(.bottomPlate))
        s.box(0, H - 0.1, L, H - 0.05, fill: color(.topPlate))
        s.box(0, H - 0.05, L, H, fill: color(.capPlate))
        let zs = 0.05 + sill, zt = zs + hgt
        s.box(x0, zs, x1, zt, fill: NSColor(srgbRed: 0.88, green: 0.94, blue: 1, alpha: 1), stroke: blue)
        s.box(x0 - 0.1, 0.05, x0 - 0.05, H - 0.1, fill: color(.king)); s.box(x1 + 0.05, 0.05, x1 + 0.1, H - 0.1, fill: color(.king))
        s.box(x0 - 0.05, 0.05, x0, zt, fill: color(.jack)); s.box(x1, 0.05, x1 + 0.05, zt, fill: color(.jack))
        s.box(x0 - 0.05, zt, x1 + 0.05, zt + hh, fill: color(.header))
        s.box(x0, zs - 0.05, x1, zs, fill: color(.sillPiece))
        var u = 0.6
        while u < L { if u > x0 && u < x1 { s.box(u - 0.025, 0.05, u + 0.025, zs - 0.05, fill: color(.cripple)); if zt + hh < H - 0.12 { s.box(u - 0.025, zt + hh, u + 0.025, H - 0.1, fill: color(.cripple)) } }; u += c.p.studStep }
        s.dim(V2(x0, zs), V2(x1, zs), off: -0.18, "черновой проём " + mm(w))
        s.dim(V2(x1, zs), V2(x1, zt), off: -0.28, mm(hgt))
        s.dim(V2(x0 - 0.1, 0), V2(x0 - 0.1, zs), off: 0.12, mm(sill + 0.05))
        let lx = L + 0.05
        s.leader(V2((x0 + x1) / 2, zt + hh / 2), V2(lx, H * 0.93), "Перемычка 2×(50×\(mm(hh))) на ребро + утеплитель между досками")
        s.leader(V2(x0 - 0.075, H * 0.75), V2(lx, H * 0.8), "Полная стойка (у проёма)")
        s.leader(V2(x1 + 0.025, zt * 0.6), V2(lx, H * 0.67), "Опорная стойка перемычки")
        s.leader(V2((x0 + x1) / 2, (zs + zt) / 2), V2(lx, H * 0.53), "Блок \(blk.mm) мм + зазоры 20 (бока, верх) / 30 (низ)")
        s.leader(V2((x0 + x1) / 2, zs - 0.025), V2(lx, H * 0.3), "Подоконный ригель \(c.b.frame.studExt.label)\(w > 1.5 ? " (двойной)" : "")")
        s.leader(V2(x0 + 0.2, (0.05 + zs) / 2), V2(lx, H * 0.13), "Укороченные стойки по шагу \(mm(c.p.studStep))")
    }

    static func windowInstall(_ c: Ctx, _ cg: CGContext, _ rect: CGRect) {
        let D = c.b.frame.studExt.wm
        let s = Sk(cg, rect, lo: V2(-0.18, -0.2), hi: V2(D + 0.12, 0.35), pad: 12, right: 165)
        // разрез стены под окном и над подоконным ригелем: снаружи слева
        s.box(0, -0.2, D, -0.05, .insulation)
        s.box(0, -0.05, D, 0, .timberCut)
        s.box(-0.009, -0.2, 0, 0.0, .board)
        s.box(-0.04, -0.2, -0.02, 0.0, .wood)            // фасад
        s.box(D, -0.2, D + 0.0125, 0.0, fill: NSColor(white: 0.95, alpha: 1))
        // рама
        let fx = D * 0.25
        s.box(fx, 0.03, fx + 0.07, 0.3, fill: NSColor(white: 0.97, alpha: 1), stroke: .black, w: 1)
        s.box(fx + 0.01, 0.0, fx + 0.07, 0.03, fill: NSColor(white: 0.85, alpha: 1))   // подставочный профиль
        s.box(fx + 0.02, 0.09, fx + 0.05, 0.3, fill: NSColor(srgbRed: 0.75, green: 0.88, blue: 0.98, alpha: 1), stroke: .gray)
        // пена
        s.box(fx, 0.0, fx + 0.07, 0.0 + 0.0, fill: .clear)
        // отлив
        s.poly([V2(fx + 0.005, 0.01), V2(-0.08, -0.02), V2(-0.08, -0.04)], fill: nil, stroke: .darkGray, w: 1.5, close: false)
        // подоконник
        s.box(fx + 0.07, 0.0, D + 0.06, 0.02, fill: NSColor(white: 0.93, alpha: 1))
        s.line(V2(fx, 0.002), V2(fx - 0.01, 0.002), 3, NSColor.orange)
        s.line(V2(fx + 0.07, -0.003), V2(fx + 0.09, -0.003), 3, blue)
        let lx = D + 0.1
        s.leader(V2(fx - 0.005, 0.002), V2(lx, 0.32), "Наружный слой: ПСУЛ / диффузионная лента")
        s.leader(V2(fx + 0.035, 0.015), V2(lx, 0.26), "Центральный: монтажная пена (≥ 90 % глубины)")
        s.leader(V2(fx + 0.08, -0.003), V2(lx, 0.2), "Внутренний: пароизоляционная лента")
        s.leader(V2(fx + 0.04, 0.015), V2(lx, 0.14), "Подставочный профиль 30 мм")
        s.leader(V2(-0.05, -0.025), V2(lx, 0.08), "Отлив, уклон ≥ 10°, заводится под раму")
        s.leader(V2(D / 2, -0.025), V2(lx, 0.02), "Подоконный ригель")
        s.leader(V2(D * 0.6, 0.01), V2(lx, -0.04), "Подоконник с зазором 5–10 мм")
        s.leader(V2(-0.005, -0.12), V2(lx, -0.1), "ОСП + мембрана, заведённая в откос")
        s.label("снаружи", V2(-0.17, 0.3), size: 7, color: .gray)
        s.label("внутри", V2(D + 0.02, 0.3), size: 7, color: .gray)
        s.label("Крепление рамы: анкерные пластины, от углов 150–180 мм, шаг ≤ 700 мм (ГОСТ 30971-2012)", V2(-0.17, -0.18), size: 6.5, ay: 0)
    }

    // MARK: - Кровля

    static func rafterPlan(_ c: Ctx, _ cg: CGContext, _ rect: CGRect) {
        let F = c.b.frame
        let o = c.p.overhang
        let rings = c.p.rings.enumerated().map { i, r in Geo.offset(r, by: i == 0 ? o : -o) }
        let (lo, hi) = Geo.bbox(rings)
        let s = Sk(cg, rect, lo: lo - V2(0.4, 0.4), hi: hi + V2(0.4, 0.9), pad: 12)
        for r in rings { s.poly(r, fill: NSColor(white: 0.97, alpha: 1), stroke: .gray, w: 0.8, dash: [4, 2]) }
        for r in c.p.rings { s.poly(r, fill: nil, stroke: .black, w: 1.4) }
        for (a, b) in F.rafterLines { s.line(a, b, max(1, CGFloat(0.05) * s.sc), color(.rafter)) }
        for m in F.members where m.kind == .hip { s.line(V2(m.a.x, m.a.y), V2(m.b.x, m.b.y), 2, color(.ridge)) }
        for (a, b) in F.ridgeLines { s.line(a, b, 3, color(.ridge)) }
        for m in F.members where m.kind == .collar || m.kind == .tie { s.line(V2(m.a.x, m.a.y), V2(m.b.x, m.b.y), 0.6, blue, dash: [2, 2]) }
        if let rf = F.rafter {
            s.label("Стропила \(rf.title) шаг \(mm(rf.step)), проекция пролёта \(fmt(F.rafterRun)) м, свес \(mm(o)); тёмные — конёк и диагональные ноги; пунктир — ригели/затяжки", V2(lo.x - 0.3, hi.y + 0.55), size: 7)
        }
        if F.rafterLines.count > 1 { s.dim(F.rafterLines[1].0, F.rafterLines[2 < F.rafterLines.count ? 2 : 1].0, off: -0.3) }
    }

    static func eaveNode(_ c: Ctx, _ cg: CGContext, _ rect: CGRect) {
        let F = c.b.frame
        guard let rf = F.rafter else { return }
        let D = F.studExt.wm
        let a = c.p.roofAngleEff * .pi / 180
        let hR = rf.sec.wm
        let o = c.p.overhang
        let ja = F.attic?.check.sec.wm ?? 0.2
        let s = Sk(cg, rect, lo: V2(-o - 0.15, -0.55), hi: V2(D + 1.0, 1.0), pad: 10, right: 215)
        // стена (снаружи — слева, x=0 наружная грань)
        s.box(0, -0.55, D, -0.1, .insulation)
        s.box(0, -0.55, 0.05, -0.1, fill: color(.stud))
        s.box(0, -0.1, D, -0.05, .timberCut); s.box(0, -0.05, D, 0, .timberCut)
        s.box(-0.009, -0.55, 0, 0, .board)
        // затяжка/балка
        s.poly([V2(0, 0), V2(D + 1.0, 0), V2(D + 1.0, ja), V2(ja / tan(a), ja)], fill: Sk.fillFor(.board), stroke: .black, w: 0.8)
        // стропило: нижняя грань проходит через (0, 0) с уклоном a
        func yb(_ x: Double) -> Double { x * tan(a) }
        let xs = -o, xe = D + 1.0
        let n = V2(-sin(a), cos(a)) * (hR)
        let p0 = V2(xs, yb(xs)), p1 = V2(xe, yb(xe))
        s.poly([p0, p1, p1 + n, p0 + n], fill: Sk.fillFor(.wood), stroke: .black, w: 0.8)
        // запил
        s.poly([V2(0, 0), V2(D, 0), V2(D, yb(D))], fill: .white, stroke: .black, w: 0.5)
        // контробрешётка, обрешётка, покрытие
        let up1 = n + V2(-sin(a), cos(a)) * 0.05
        s.poly([p0 + n, p1 + n, p1 + up1, p0 + up1], fill: color(.counterBatten), stroke: .black, w: 0.5)
        s.line(p0 + n, p1 + n, 1.2, blue, dash: [3, 2])
        var t = 0.05
        let dirS = V2(cos(a), sin(a))
        while t < (xe - xs) / cos(a) - 0.1 {
            let q = p0 + dirS * t + up1
            s.poly([q, q + dirS * 0.1, q + dirS * 0.1 + V2(-sin(a), cos(a)) * 0.025, q + V2(-sin(a), cos(a)) * 0.025], fill: color(.batten), stroke: .black, w: 0.4)
            t += F.battenStep
        }
        let top = up1 + V2(-sin(a), cos(a)) * 0.035
        s.line(p0 + top, p1 + top, 2.2, NSColor(srgbRed: 0.5, green: 0.15, blue: 0.13, alpha: 1))
        // уголок
        s.poly([V2(D * 0.3, 0.0), V2(D * 0.3, 0.06), V2(D * 0.3 + 0.06, 0.06)], fill: nil, stroke: .darkGray, w: 2, close: false)
        // подшива свеса — перфорированный софит: вход воздуха в вентзазор кровли
        s.line(V2(xs, yb(xs)), V2(0, yb(xs)), 1.2, .brown, dash: [6, 2])
        let air = NSColor(srgbRed: 0.1, green: 0.55, blue: 0.85, alpha: 1)
        let gapMid = n + V2(-sin(a), cos(a)) * 0.025
        s.poly([V2(xs * 0.6, yb(xs) - 0.05), V2(xs * 0.6, yb(xs) + 0.02), p0 + gapMid + dirS * 0.05, p0 + gapMid + dirS * 0.9], fill: nil, stroke: air, w: 1.2, close: false, dash: [4, 2])
        let tip = p0 + gapMid + dirS * 0.9
        s.poly([tip, tip - dirS * 0.06 + V2(-sin(a), cos(a)) * 0.025, tip - dirS * 0.06 - V2(-sin(a), cos(a)) * 0.025], fill: air, stroke: air, w: 0.5)
        if c.p.roofInsulated {
            s.line(V2(0.01, 0.02), V2(0.01, hR * 0.95), 1.6, NSColor(srgbRed: 0.1, green: 0.6, blue: 0.65, alpha: 1))
            s.leader(V2(0.01, hR * 0.5), V2(D + 1.05, 0.83), "Ветробарьер у карниза (мембрана между стропилами)")
        }
        let lx = D + 1.05
        s.leader(tip, V2(lx, 0.97), "Воздух: софит → вентзазор → вентилируемый конёк")
        s.leader(V2(D * 0.6, hR * 0.6 + yb(D * 0.6)), V2(lx, 0.7), "Стропило \(rf.title) шаг \(mm(rf.step))")
        s.leader(V2(0.5, ja / 2), V2(lx, 0.12), "Балка перекрытия / затяжка \(F.attic?.check.title ?? "")")
        s.leader(V2(D * 0.5, yb(D * 0.5) / 2), V2(lx, -0.02), "Запил ≤ 1/3 h стропила")
        s.leader(V2(D * 0.3 + 0.03, 0.06), V2(lx, -0.12), "Уголок 90×90×65 ×2 + ветровая скоба к стойке")
        s.leader(V2(D / 2, -0.05), V2(lx, -0.26), "Верхняя обвязка 2×\(F.studExt.label)")
        s.leader(V2(0.6, 0.6 * tan(a) + hR + 0.03), V2(lx, 0.55), "Контробрешётка \(F.counterSec.label) / вентзазор")
        s.leader(V2(0.9, 0.9 * tan(a) + hR + 0.01), V2(lx, 0.4), "Мембрана супердиффузионная")
        s.leader(V2(1.1, 1.1 * tan(a) + hR + 0.08), V2(lx, 0.27), "Обрешётка \(F.battenSec.label) шаг \(mm(F.battenStep)) + покрытие")
        s.leader(V2(-o / 2, yb(xs)), V2(lx, -0.42), "Подшива свеса \(mm(o)): ПЕРФОРИРОВАННЫЙ софит по брускам 50×50 (вход воздуха)")
    }

    static func ridgeNode(_ c: Ctx, _ cg: CGContext, _ rect: CGRect) {
        let F = c.b.frame
        guard let rf = F.rafter else { return }
        let a = c.p.roofAngleEff * .pi / 180
        let hR = rf.sec.wm
        let L = 1.1
        let s = Sk(cg, rect, lo: V2(-L, -L * tan(a) - 0.1), hi: V2(L, hR / cos(a) + 0.15), pad: 10, right: 200)
        for sgn in [-1.0, 1.0] {
            let p0 = V2(sgn * L, -L * tan(a)), p1 = V2(0, 0)
            let n = V2(-sgn * sin(a) * -1, cos(a)) * hR
            let nn = V2(sgn * sin(a), cos(a)) * hR
            _ = n
            s.poly([p0, p1, p1 + V2(0, hR / cos(a)), p0 + nn], fill: Sk.fillFor(.wood), stroke: .black, w: 0.8)
        }
        s.box(-0.025, -0.1, 0.025, hR / cos(a), .timberCut)
        s.poly([V2(-0.3, -0.3 * tan(a) + 0.02), V2(0.3, -0.3 * tan(a) + 0.02), V2(0.3, -0.3 * tan(a) + 0.17), V2(0, 0.17), V2(-0.3, -0.3 * tan(a) + 0.17)], fill: NSColor(white: 0.9, alpha: 0.6), stroke: blue, w: 1)
        let cz = -L * tan(a) * 0.55
        s.box(-L * 0.55, cz, L * 0.55, cz + 0.15, fill: color(.collar))
        let lx = L + 0.05
        s.leader(V2(0, hR * 0.5), V2(lx, hR / cos(a) + 0.05), "Коньковая доска 50×\(rf.sec.w + 50)")
        s.leader(V2(0.2, 0.05), V2(lx, 0.0), "Накладки 25×150 L=600 с 2 сторон, 6 гвоздей 4×100")
        s.leader(V2(L * 0.4, cz + 0.07), V2(lx, cz + 0.07), "Ригель (схватка) 50×150 на 1/3 высоты, болт М12")
        s.leader(V2(L * 0.7, -L * 0.7 * tan(a) + hR * 0.5), V2(lx, -L * tan(a) * 0.9), "Стропило \(rf.title)")
    }

    // MARK: - Пироги

    struct Layer { let name: String; let t: Double; let h: Sk.Hatch; var fill: NSColor? = nil }

    static func pie(_ cg: CGContext, _ rect: CGRect, title: String, layers: [Layer]) {
        let total = layers.reduce(0) { $0 + max($1.t, 0.006) }
        let s = Sk(cg, rect, lo: V2(0, 0), hi: V2(0.5, total), pad: 16, right: 250, top: 10)
        Sk.text(title, CGPoint(x: rect.minX + 10, y: rect.minY + 10), size: 8, bold: true, ay: 0.5)
        var y = total
        for (i, l) in layers.enumerated() {
            let t = max(l.t, 0.006)
            s.box(0, y - t, 0.5, y, l.h, fill: l.fill)
            let ly = rect.minY + 26 + (rect.height - 40) * CGFloat(i) / CGFloat(max(layers.count, 1))
            let a = s.P(0.5, y - t / 2)
            cg.saveGState(); cg.setStrokeColor(NSColor.darkGray.cgColor); cg.setLineWidth(0.5)
            cg.move(to: a); cg.addLine(to: CGPoint(x: a.x + 20, y: ly)); cg.addLine(to: CGPoint(x: a.x + 28, y: ly)); cg.strokePath(); cg.restoreGState()
            Sk.text("\(i + 1). \(l.name)" + (l.t >= 0.006 ? " — \(mm(l.t)) мм" : ""), CGPoint(x: a.x + 31, y: ly), size: 7, maxW: rect.maxX - a.x - 36)
            y -= t
        }
    }

    static func floorLayers(_ c: Ctx) -> [Layer] {
        let j = c.b.frame.floors.first?.check
        return [
            Layer(name: "Чистовой пол (ламинат/доска/плитка по СМЛ)", t: 0.012, h: .board),
            Layer(name: "Настил ОСП-3 шпунт на клей + саморезы", t: 0.022, h: .board),
            Layer(name: "Пароизоляция, швы проклеены", t: 0, h: .none, fill: .systemBlue),
            Layer(name: "Утеплитель минвата между балками \(j.map { "\($0.title)" } ?? "")", t: c.b.woolFloor, h: .insulation),
            Layer(name: "Ветро-влагозащитная мембрана", t: 0, h: .none, fill: .systemTeal),
            Layer(name: "Черновой подшив ОСП 9 / доска 25×100 на черепных брусках 50×50", t: 0.025, h: .board),
            Layer(name: "Проветриваемое подполье (продухи ~1/400 площади)", t: 0.1, h: .none, fill: NSColor(white: 0.97, alpha: 1)),
        ]
    }

    static func roofLayers(_ c: Ctx) -> [Layer] {
        let F = c.b.frame
        var l = [
            Layer(name: c.p.covering.title, t: 0.01, h: .none, fill: NSColor(srgbRed: 0.55, green: 0.18, blue: 0.15, alpha: 1)),
            Layer(name: "Обрешётка \(F.battenSec.label) шаг \(mm(F.battenStep))", t: F.battenSec.tm, h: .board),
            Layer(name: "Контробрешётка \(F.counterSec.label) (вентзазор)", t: F.counterSec.tm, h: .none, fill: NSColor(white: 0.97, alpha: 1)),
            Layer(name: "Супердиффузионная мембрана", t: 0, h: .none, fill: .systemTeal),
        ]
        if c.p.covering == .softShingle {
            l.insert(Layer(name: "Подкладочный ковёр", t: 0.003, h: .none, fill: .darkGray), at: 1)
            l.insert(Layer(name: "ОСП-3 12 мм сплошной настил", t: 0.012, h: .board), at: 2)
        }
        if c.p.roofInsulated {
            l += [Layer(name: "Утеплитель между стропилами \(F.rafter?.title ?? "")", t: min(c.b.woolRoof, F.rafter?.sec.wm ?? 0.2), h: .insulation)]
            if c.b.woolRoof > (F.rafter?.sec.wm ?? 0.2) { l.append(Layer(name: "Доп. утеплитель поперёк (бруски 50×50)", t: c.b.woolRoof - (F.rafter?.sec.wm ?? 0.2), h: .insulation)) }
            l += [Layer(name: "Пароизоляция, швы проклеены", t: 0, h: .none, fill: .systemBlue),
                  Layer(name: "Обрешётка 25×50 (инсталляционный зазор)", t: 0.025, h: .none, fill: NSColor(white: 0.97, alpha: 1)),
                  Layer(name: "ГКЛ 12.5 мм", t: 0.0125, h: .none, fill: NSColor(white: 0.93, alpha: 1))]
        } else {
            l += [Layer(name: "Стропило \(F.rafter?.title ?? "") — холодный чердак", t: F.rafter?.sec.wm ?? 0.2, h: .none, fill: NSColor(white: 0.98, alpha: 1))]
        }
        return l
    }

    static func wallLayers(_ c: Ctx) -> [Layer] {
        let F = c.b.frame
        let extra = c.b.woolWall - F.studExt.wm
        var l = [
            Layer(name: c.p.facade.title, t: c.p.facade == .facingBrick ? 0.12 : 0.02, h: c.p.facade == .facingBrick ? .concrete : .board),
            Layer(name: "Вентзазор (контррейка 25×50)", t: c.p.facade == .facingBrick ? 0.04 : 0.025, h: .none, fill: NSColor(white: 0.98, alpha: 1)),
            Layer(name: "Ветро-влагозащитная мембрана", t: 0, h: .none, fill: .systemTeal),
        ]
        if c.p.sheathing.hasOSB { l.append(Layer(name: "ОСП-3 9 мм", t: 0.009, h: .board)) }
        l.append(Layer(name: "Каркас \(F.studExt.label) шаг \(mm(c.p.studStep)) + минвата", t: F.studExt.wm, h: .insulation))
        if extra > 0.01 { l.append(Layer(name: "Доп. утеплитель по брускам 50×50", t: extra, h: .insulation)) }
        l += [Layer(name: "Пароизоляция, швы проклеены", t: 0, h: .none, fill: .systemBlue),
              Layer(name: "Обрешётка 25×50 (инсталляционный зазор)", t: 0.025, h: .none, fill: NSColor(white: 0.98, alpha: 1)),
              Layer(name: "ГКЛ 12.5 мм", t: 0.0125, h: .none, fill: NSColor(white: 0.93, alpha: 1))]
        return l
    }
}
