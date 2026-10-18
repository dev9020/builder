import AppKit
import CoreGraphics

/// Планы: мебель, сантехнические точки и разводка, наружные сети
extension Drawings {
    static let sewerCol = NSColor(srgbRed: 0.55, green: 0.33, blue: 0.15, alpha: 1)
    static let coldCol = NSColor(srgbRed: 0.1, green: 0.4, blue: 0.85, alpha: 1)
    static let hotCol = NSColor(srgbRed: 0.85, green: 0.15, blue: 0.1, alpha: 1)

    static func roomFill(_ t: RoomType) -> NSColor {
        switch t {
        case .bath, .wc: return NSColor(srgbRed: 0.85, green: 0.93, blue: 0.98, alpha: 1)
        case .kitchenLiving, .kitchen, .living: return NSColor(srgbRed: 0.99, green: 0.96, blue: 0.88, alpha: 1)
        case .bedroom, .office: return NSColor(srgbRed: 0.94, green: 0.97, blue: 0.92, alpha: 1)
        case .boiler, .storage: return NSColor(srgbRed: 0.93, green: 0.92, blue: 0.95, alpha: 1)
        default: return NSColor(white: 0.97, alpha: 1)
        }
    }

    /// Стены, проёмы и комнаты — основа планов
    static func planBase(_ c: Ctx, _ s: Sk, fills: Bool, labels: Bool, faint: Bool = false) {
        let p = c.p, L = c.b.layout
        let g = L.grid
        if fills {
            for r in L.rooms {
                let col = roomFill(r.type)
                // заливка комнат по строкам растра
                var rows: [Int: [Int]] = [:]
                for (i, j) in r.cells { rows[j, default: []].append(i) }
                for (j, xs) in rows {
                    let sorted = xs.sorted()
                    var a = sorted[0], prev = sorted[0]
                    for x in sorted.dropFirst() + [Int.max] {
                        if x != prev + 1 {
                            let lo = g.lo + V2(Double(a) * g.res, Double(j) * g.res)
                            s.box(lo.x, lo.y, lo.x + Double(prev - a + 1) * g.res, lo.y + g.res, fill: col, stroke: .clear, w: 0)
                            a = x
                        }
                        prev = x
                    }
                }
            }
        }
        let wc = faint ? NSColor(white: 0.55, alpha: 1) : NSColor(white: 0.2, alpha: 1)
        let D = p.studDepth + 0.05
        for e in p.edges { s.line(e.a, e.b, CGFloat(D) * s.sc, wc) }
        for pt in p.partitions where pt.length > 0.3 { s.line(pt.a, pt.b, max(2, CGFloat(pt.thickness) * s.sc), wc) }
        for o in p.validOpenings {
            guard let cc = p.openingCenter(o), let l = p.hostLine(o.host) else { continue }
            let d = (l.b - l.a).unit
            let a = cc - d * (o.width / 2), b = cc + d * (o.width / 2)
            var t = D
            if case .partition = o.host { t = 0.17 }
            s.line(a, b, CGFloat(t) * s.sc + 1, .white)
            if o.kind.isDoor || o.sill < 0.05 && o.kind != .panoramic {
                s.line(a, b, 0.6, wc)
            } else {
                let n = V2(-d.y, d.x) * (t * 0.25)
                s.line(a + n, b + n, 0.8, blue); s.line(a - n, b - n, 0.8, blue)
            }
        }
        if labels {
            for r in L.rooms {
                s.label("\(r.name)\n\(fmt(r.area, 1)) м²", r.seed, size: 7, ax: 0.5, bold: false, color: NSColor(white: 0.3, alpha: 1), bg: true)
            }
        }
    }

    static func drawFurniture(_ f: Furniture, _ s: Sk, faint: Bool = false) {
        let a = faint ? 0.35 : 1.0
        let line = NSColor(white: 0.25, alpha: a)
        func fill(_ c: NSColor) -> NSColor { c.withAlphaComponent(faint ? 0.3 : 0.9) }
        let lo = f.lo, hi = f.hi
        let ctr = (lo + hi) / 2
        switch f.kind {
        case .toilet:
            let w = (hi - lo)
            let tank = f.wall + f.normal * 0.1
            let along = V2(-f.normal.y, f.normal.x)
            s.poly([tank - along * 0.2 - f.normal * 0.09, tank + along * 0.2 - f.normal * 0.09, tank + along * 0.2 + f.normal * 0.09, tank - along * 0.2 + f.normal * 0.09], fill: fill(.white), stroke: line, w: 0.6)
            let bowl = f.wall + f.normal * 0.45
            s.poly((0..<20).map { k in let t = Double(k) / 20 * 2 * .pi; return bowl + along * (cos(t) * 0.18) + f.normal * (sin(t) * 0.25) }, fill: fill(.white), stroke: line, w: 0.6)
            _ = w
        case .sink:
            s.box(lo.x, lo.y, hi.x, hi.y, fill: fill(.white), stroke: line, w: 0.6)
            s.poly((0..<20).map { k in let t = Double(k) / 20 * 2 * .pi; return ctr + V2(cos(t), sin(t)) * (min(hi.x - lo.x, hi.y - lo.y) * 0.32) }, fill: nil, stroke: line, w: 0.5)
        case .shower:
            s.box(lo.x, lo.y, hi.x, hi.y, fill: fill(NSColor(srgbRed: 0.88, green: 0.95, blue: 1, alpha: 1)), stroke: line, w: 0.6)
            s.line(lo, hi, 0.4, line); s.line(V2(lo.x, hi.y), V2(hi.x, lo.y), 0.4, line)
        case .bathtub:
            s.box(lo.x, lo.y, hi.x, hi.y, fill: fill(.white), stroke: line, w: 0.6)
            s.box(lo.x + 0.07, lo.y + 0.07, hi.x - 0.07, hi.y - 0.07, fill: fill(NSColor(srgbRed: 0.88, green: 0.95, blue: 1, alpha: 1)), stroke: line, w: 0.4)
        case .bed:
            s.box(lo.x, lo.y, hi.x, hi.y, fill: fill(NSColor(srgbRed: 0.93, green: 0.9, blue: 0.98, alpha: 1)), stroke: line, w: 0.6)
            let along = V2(-f.normal.y, f.normal.x)
            let head = f.wall + f.normal * 0.2
            let bw = max(abs(dot2(hi - lo, along)) - 0.9, 0.8)
            for sgn in [-1.0, 1.0] where bw > 1.1 {
                let c0 = head + along * (sgn * bw / 4)
                s.poly([c0 - along * 0.28 - f.normal * 0.12, c0 + along * 0.28 - f.normal * 0.12, c0 + along * 0.28 + f.normal * 0.12, c0 - along * 0.28 + f.normal * 0.12], fill: fill(.white), stroke: line, w: 0.4)
            }
        case .kitchen:
            s.box(lo.x, lo.y, hi.x, hi.y, fill: fill(NSColor(srgbRed: 0.92, green: 0.88, blue: 0.8, alpha: 1)), stroke: line, w: 0.6)
        default:
            let col: NSColor
            switch f.kind {
            case .wardrobe, .shelf: col = NSColor(srgbRed: 0.9, green: 0.84, blue: 0.74, alpha: 1)
            case .sofa: col = NSColor(srgbRed: 0.8, green: 0.86, blue: 0.93, alpha: 1)
            case .table, .desk, .bench: col = NSColor(srgbRed: 0.95, green: 0.9, blue: 0.8, alpha: 1)
            case .boiler, .heater, .tank, .collector, .filter, .washer, .fridge: col = NSColor(white: 0.88, alpha: 1)
            default: col = .white
            }
            if [.heater, .tank].contains(f.kind) {
                s.poly((0..<24).map { k in let t = Double(k) / 24 * 2 * .pi; return ctr + V2(cos(t), sin(t)) * (min(hi.x - lo.x, hi.y - lo.y) / 2) }, fill: fill(col), stroke: line, w: 0.6)
            } else {
                s.box(lo.x, lo.y, hi.x, hi.y, fill: fill(col), stroke: line, w: 0.6)
            }
        }
    }

    static func furniturePlan(_ c: Ctx, _ cg: CGContext, _ rect: CGRect) {
        let (lo, hi) = Geo.bbox(c.p.rings)
        let s = Sk(cg, rect, lo: lo - V2(0.5, 0.6), hi: hi + V2(0.5, 0.5), pad: 10)
        planBase(c, s, fills: true, labels: false)
        for f in c.b.layout.furniture { drawFurniture(f, s) }
        for f in c.b.layout.furniture where [.bed, .wardrobe, .sofa, .table, .kitchen, .fridge, .bathtub, .shower, .desk, .washer].contains(f.kind) {
            let size = min(f.hi.x - f.lo.x, f.hi.y - f.lo.y)
            if size > 0.35 { s.label(f.name.components(separatedBy: " + ").first ?? f.name, (f.lo + f.hi) / 2, size: 5.5, ax: 0.5, color: NSColor(white: 0.25, alpha: 1)) }
        }
        for r in c.b.layout.rooms {
            func free(_ v: V2) -> Bool { c.b.layout.furniture.filter { $0.room == r.id }.allSatisfy { !($0.lo.x < v.x + 0.8 && $0.hi.x > v.x - 0.8 && $0.lo.y < v.y + 0.2 && $0.hi.y > v.y - 0.2) } }
            let cands = [r.seed, V2(r.seed.x, r.hi.y - 0.3), V2(r.seed.x, r.lo.y + 0.3), V2(r.seed.x, (r.seed.y + r.hi.y) / 2), V2(r.seed.x, (r.seed.y + r.lo.y) / 2)]
            let at = cands.first(where: free) ?? r.seed
            s.label("\(r.type.short) \(fmt(r.area, 1)) м²", at, size: 7, ax: 0.5, bold: true, color: NSColor(white: 0.2, alpha: 1), bg: true)
        }
        s.dim(V2(lo.x, lo.y - 0.3), V2(hi.x, lo.y - 0.3), off: 0, "\(mm(hi.x - lo.x)) по осям", size: 7)
    }

    static func plumbingPlan(_ c: Ctx, _ cg: CGContext, _ rect: CGRect) {
        let L = c.b.layout
        let (lo, hi) = Geo.bbox(c.p.rings)
        let s = Sk(cg, rect, lo: lo - V2(1.2, 1.3), hi: hi + V2(1.2, 1.3), pad: 10, top: 14)
        planBase(c, s, fills: true, labels: false, faint: true)
        for f in L.furniture where [.toilet, .sink, .shower, .bathtub, .washer, .kitchen, .heater, .boiler, .collector, .tank, .filter].contains(f.kind) { drawFurniture(f, s, faint: true) }
        for pp in L.pipes where pp.kind == .sewer { s.poly(pp.pts, fill: nil, stroke: sewerCol, w: pp.d >= 110 ? 3.2 : 1.8, close: false) }
        for pp in L.pipes where pp.kind != .sewer { s.poly(pp.pts, fill: nil, stroke: pp.kind == .cold ? coldCol : hotCol, w: pp.d >= 25 ? 2 : 1, close: false) }
        for pt in L.points {
            let col: NSColor = pt.kind == .cold ? coldCol : pt.kind == .hot ? hotCol : sewerCol
            s.dot(pt.pos, pt.kind == .sewer110 ? 4 : 2.8, col)
            if pt.kind == .cold || pt.kind == .sewer110 { s.label("\(pt.number)", pt.pos + V2(0.08, 0.08), size: 6, color: col, bg: true) }
        }
        s.box(L.collector.x - 0.2, L.collector.y - 0.12, L.collector.x + 0.2, L.collector.y + 0.12, fill: NSColor(white: 0.85, alpha: 1), stroke: .black, w: 0.8)
        s.label("коллектор ХВ/ГВ", L.collector + V2(0, 0.2), size: 6.5, ax: 0.5, ay: 1, bold: true, bg: true)
        // ввод и выпуск
        let D = c.p.studDepth
        func arrow(_ at: V2, _ out: Bool, _ txt: String, _ col: NSColor) {
            let (blo, bhi) = Geo.bbox(c.p.rings)
            let n: V2 = abs(at.y - blo.y) < 0.05 ? V2(0, -1) : abs(at.y - bhi.y) < 0.05 ? V2(0, 1) : abs(at.x - blo.x) < 0.05 ? V2(-1, 0) : V2(1, 0)
            let a = at - n * (D / 2 + 0.3), b = at + n * 0.9
            s.line(a, b, 2.5, col)
            s.label(txt, b + n * 0.15, size: 6.5, ax: 0.5, ay: n.y > 0 ? 1 : 0, bold: true, color: col, bg: true)
            _ = out
        }
        arrow(L.entry, false, "ввод воды от скважины\nстена \(L.entryWall), \(fmt(L.entryOffset, 2)) м", coldCol)
        arrow(L.outlet, true, "выпуск Ø110 в септик\nстена \(L.outletWall), \(fmt(L.outletOffset, 2)) м, −\(fmt(L.outletDepth, 2)) м", sewerCol)
        Sk.text("ХВ — синие (PE-Xa 16, лучами от коллектора, \(fmt(L.coldLen, 0)) м), ГВ — красные (\(fmt(L.hotLen, 0)) м), канализация — коричневые: Ø110 уклон 2 % (\(fmt(L.sewerLen(110), 1)) м), Ø50 уклон 3 % (\(fmt(L.sewerLen(50), 1)) м). Номера — точки из таблицы.",
                CGPoint(x: rect.minX + 8, y: rect.minY + 8), size: 7, color: .darkGray, maxW: rect.width - 16)
    }

    static func siteNetworks(_ c: Ctx, _ cg: CGContext, _ rect: CGRect) {
        let L = c.b.layout, p = c.p
        let s = Sk(cg, rect, lo: L.plotLo - V2(1, 3), hi: L.plotHi + V2(1, 1), pad: 10, top: 22)
        s.box(L.plotLo.x - 1, L.plotLo.y - 3, L.plotHi.x + 1, L.plotLo.y - 0.3, fill: NSColor(white: 0.88, alpha: 1), stroke: .clear)
        s.label("улица / проезд", V2((L.plotLo.x + L.plotHi.x) / 2, L.plotLo.y - 1.6), size: 7, ax: 0.5)
        s.poly([L.plotLo, V2(L.plotHi.x, L.plotLo.y), L.plotHi, V2(L.plotLo.x, L.plotHi.y)], fill: NSColor(srgbRed: 0.91, green: 0.96, blue: 0.88, alpha: 1), stroke: green, w: 1.2, dash: [5, 3])
        for r in p.rings { s.poly(r, fill: NSColor(white: 0.75, alpha: 1), stroke: .black, w: 1) }
        let (lo, hi) = Geo.bbox(p.rings)
        s.label("Дом", (lo + hi) / 2, size: 8, ax: 0.5, bold: true)
        // трассы
        let septicIn = L.septic + V2(0, L.septic.y < L.outlet.y ? p.septic.size.y / 2 : -p.septic.size.y / 2)
        s.poly([L.outlet, V2(septicIn.x, L.outlet.y), septicIn], fill: nil, stroke: sewerCol, w: 2.4, close: false)
        let e1 = L.entry + L.entryOut * 1.5
        let mid = abs(L.entryOut.y) > 0.5 ? V2(L.well.x, e1.y) : V2(e1.x, L.well.y)
        s.poly([L.entry, e1, mid, L.well], fill: nil, stroke: coldCol, w: 2, close: false, dash: [6, 3])
        // скважина и септик
        s.poly((0..<24).map { k in let t = Double(k) / 24 * 2 * .pi; return L.well + V2(cos(t), sin(t)) * 0.6 }, fill: NSColor(srgbRed: 0.8, green: 0.9, blue: 1, alpha: 1), stroke: coldCol, w: 1.2)
        s.label("скважина + кессон", L.well + V2(0, 0.8), size: 7, ax: 0.5, ay: 1, bold: true, color: coldCol, bg: true)
        let sz = p.septic.size
        s.box(L.septic.x - sz.x / 2, L.septic.y - sz.y / 2, L.septic.x + sz.x / 2, L.septic.y + sz.y / 2, fill: NSColor(srgbRed: 0.93, green: 0.86, blue: 0.78, alpha: 1), stroke: sewerCol, w: 1.2)
        s.label(p.septic.short, L.septic + V2(0, -sz.y / 2 - 0.3), size: 7, ax: 0.5, ay: 0, bold: true, color: sewerCol, bg: true)
        // расстояния
        s.line(L.well, L.septic, 0.6, red, dash: [3, 3])
        s.label("\(fmt(L.wellToSeptic, 1)) м (≥ \(Int(p.septic.wellDistance)))", (L.well + L.septic) / 2, size: 7, ax: 0.5, bold: true, color: red, bg: true)
        s.dim(V2(L.septic.x + sz.x / 2 + 0.3, L.septic.y + sz.y / 2), V2(L.septic.x + sz.x / 2 + 0.3, lo.y - p.studDepth / 2), off: 0, "\(fmt(L.houseToSeptic, 1)) м", size: 6.5)
        s.label("≥ 5 м до дома", V2(L.septic.x + sz.x / 2 + 0.6, (L.septic.y + lo.y) / 2), size: 6.5, color: sewerCol, bg: true)
        s.label("водопровод ПНД 32: \(fmt(L.waterLen, 0)) м, глубина \(fmt(L.waterDepth, 1)) м\(L.waterHeated ? " + греющий кабель" : "")", V2(L.well.x, (e1.y + L.well.y) / 2), size: 6.5, ax: L.well.x > (lo.x + hi.x) / 2 ? 1 : 0, color: coldCol, bg: true)
        s.label("канализация Ø110: \(fmt(L.sewerLen, 0)) м, i = 0.02, вход \(fmt(L.septicInlet, 2)) м", V2((L.outlet.x + septicIn.x) / 2, L.outlet.y - 1.2), size: 6.5, ax: 0.5, color: sewerCol, bg: true)
        s.dim(V2(L.plotLo.x, L.plotLo.y - 0.2), V2(L.plotHi.x, L.plotLo.y - 0.2), off: 0, "\(fmt(L.plotHi.x - L.plotLo.x, 1)) м", size: 7)
        s.dim(V2(L.plotHi.x + 0.3, L.plotLo.y), V2(L.plotHi.x + 0.3, L.plotHi.y), off: 0, "\(fmt(L.plotHi.y - L.plotLo.y, 1)) м", size: 7)
        let area = (L.plotHi.x - L.plotLo.x) * (L.plotHi.y - L.plotLo.y) / 100
        Sk.text("Минимальный участок по этой схеме ≈ \(fmt(L.plotHi.x - L.plotLo.x, 0))×\(fmt(L.plotHi.y - L.plotLo.y, 0)) м (\(fmt(area, 1)) сотки). На меньшем — накопительная ёмкость (≥ 20 м до скважины) или скважина на артезианский горизонт по проекту.",
                CGPoint(x: rect.minX + 8, y: rect.minY + 6), size: 7, color: .darkGray, ay: 0, maxW: rect.width - 16)
    }

    static func sewerProfile(_ c: Ctx, _ cg: CGContext, _ rect: CGRect) {
        let L = c.b.layout, p = c.p
        let inside = max(1.5, L.maxDrop / 0.02)
        let total = inside + L.sewerLen
        let zFix = L.ffl - L.startDepth                    // низ трубы у прибора (от земли)
        let zOut = -L.outletDepth, zIn = -L.septicInlet
        let ky = 3.0                                       // по высоте ×3
        func P(_ x: Double, _ z: Double) -> V2 { V2(x, z * ky) }
        let s = Sk(cg, rect, lo: V2(-0.8, (min(zIn, -L.dfn) - 0.8) * ky), hi: V2(total + 2.5, (L.ffl + 0.6) * ky), pad: 10, top: 12)
        Sk.text("Продольный профиль (по высоте ×3). Отметки — от уровня земли, м.", CGPoint(x: rect.minX + 8, y: rect.minY + 8), size: 7, color: .darkGray)
        // грунт
        s.poly([P(-0.8, 0), P(total + 2.5, 0), P(total + 2.5, min(zIn, -L.dfn) - 0.8), P(-0.8, min(zIn, -L.dfn) - 0.8)], fill: NSColor(srgbRed: 0.93, green: 0.89, blue: 0.82, alpha: 1), stroke: nil)
        s.line(P(-0.8, 0), P(total + 2.5, 0), 1, green)
        s.line(P(-0.8, -L.dfn), P(total + 2.5, -L.dfn), 0.8, blue, dash: [5, 3])
        s.label("промерзание −\(fmt(L.dfn, 2))", P(-0.7, -L.dfn) + V2(0, 0.05), size: 6.5, ay: 1, color: blue, bg: true)
        // дом: пол и фундамент
        s.box(-0.8, L.ffl * ky - 0.08, inside, L.ffl * ky, fill: NSColor(white: 0.7, alpha: 1))
        s.label("чистый пол +\(fmt(L.ffl, 2))", P(0, L.ffl) + V2(0, 0.25), size: 6.5, ay: 1)
        s.box(inside - 0.25, -1.0 * ky, inside, L.ffl * ky, fill: NSColor(white: 0.82, alpha: 1), stroke: .gray)
        s.label("фундамент", P(inside + 0.1, L.ffl * 0.6), size: 6, color: .darkGray)
        // труба
        s.poly([P(0, L.ffl), P(0, zFix), P(inside, zOut), P(total, zIn)], fill: nil, stroke: sewerCol, w: 3, close: false)
        let sz = p.septic.size
        s.box(total, (zIn - 1.6) * ky, total + max(sz.x, 1.2), 0.3 * ky, fill: NSColor(srgbRed: 0.93, green: 0.86, blue: 0.78, alpha: 1), stroke: sewerCol)
        s.label(p.septic.short, P(total + 0.1, 0.15), size: 6.5, color: sewerCol)
        s.dot(P(0, zFix), 3, sewerCol)
        s.label("унитаз: низ трубы \(fmt(zFix, 2))", P(0.1, zFix) + V2(0, 0.25), size: 6.5, ay: 1, bg: true)
        s.label("выпуск −\(fmt(L.outletDepth, 2))", P(inside + 0.1, zOut) + V2(0, 0.3), size: 6.5, ay: 1, bg: true)
        s.label("вход в септик −\(fmt(L.septicInlet, 2))", P(total - 0.15, zIn) + V2(0, 0.35), size: 6.5, ax: 1, ay: 1, bg: true)
        s.label("в доме: Ø110 i = 0.02 (≈ \(fmt(inside, 1)) м)", P(inside / 2, (zFix + zOut) / 2) - V2(0, 0.25), size: 6.5, ax: 0.5, ay: 0, color: sewerCol, bg: true)
        s.label("снаружи: Ø110 i = 0.02, \(fmt(L.sewerLen, 1)) м\(L.sewerInsulate ? ", утеплить ЭППС" : "")", P(inside + L.sewerLen / 2, (zOut + zIn) / 2) - V2(0, 0.55), size: 6.5, ax: 0.5, ay: 0, color: sewerCol, bg: true)
    }
}
