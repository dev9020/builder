import Foundation

struct SlabResult {
    var t = 0.0, depth = 0.0, R = 0.0, pavg = 0.0, plocal = 0.0, beta = 0.0
    var Mmax = 0.0, Qmax = 0.0, Qb = 0.0, As = 0.0, cover = 0.04
    var d = 12, step = 0.2
    var s = 0.0, su = 0.10
    var rings: [[V2]] = []
    var area = 0.0, perimeter = 0.0
    var concrete = 0.0, sand = 0.0, eps = 0.0, formwork = 0.0
    var bars: [(V2, V2)] = []
    var rebar: [RebarItem] = []
    var checks: [Check] = []
    var notes: [String] = []
    var ok: Bool { !checks.isEmpty && checks.allSatisfy(\.ok) }
    var steel: Double { rebar.reduce(0) { $0 + $1.mass } }
}

enum SlabCalc {
    static func run(_ p: Project, _ L: LoadResult) -> SlabResult {
        var r = SlabResult()
        let soil = p.soil
        let lines = L.lines, loads = L.slabLoads
        guard !lines.isEmpty else { return r }
        let maxT = lines.map(\.thickness).max() ?? 0.2
        let e = maxT / 2 + 0.1
        let base = p.rings
        r.rings = base.enumerated().map { i, ring in Geo.offset(ring, by: i == 0 ? e : -e) }
        r.area = Geo.area(r.rings)
        r.perimeter = r.rings.reduce(0) { $0 + Geo.perimeter($1) }
        let (lo, hi) = Geo.bbox(r.rings)
        let Lb = max(hi.x - lo.x, hi.y - lo.y), Wb = min(hi.x - lo.x, hi.y - lo.y)
        let bEq = (r.area * Wb / Lb).squareRoot(), lEq = r.area / bEq
        let masonry = lines.contains { $0.material.isMasonry }
        r.su = masonry ? 0.10 : 0.15
        r.cover = 0.04

        let Nk = zip(lines, loads).reduce(0) { $0 + $1.1.char * $1.0.length }
        let Nl = zip(lines, loads).reduce(0) { $0 + $1.1.longTerm * $1.0.length }
        let Eb = p.concrete.Eb * 1000
        let k = soil.kSub

        var t = max(0.15, p.slabMinThickness)
        while t <= 0.6 + 1e-9 {
            r.t = t
            r.depth = max(0, t + p.slabCushion - 0.15)
            r.R = Soil.R(soil, b: bEq, d: r.depth, gwl: p.gwl)
            let G = 25 * t
            r.pavg = Nk / r.area + G + L.slabAreaChar
            let I = t * t * t / 12
            r.beta = pow(k / (4 * Eb * I), 0.25)
            let h0 = t - r.cover - 0.012
            var pl = 0.0, M = 0.0, Q = 0.0
            for (ln, q) in zip(lines, loads) {
                let edge = ln.isExterior
                let b = r.beta
                pl = max(pl, (edge ? 2 * q.char * b : q.char * b / 2) + G + L.slabAreaChar)
                M = max(M, edge ? 0.3224 * q.design / b : 0.25 * q.design / b)
                let x = h0 * b
                let v = edge ? q.design * exp(-x) * abs(cos(x) - sin(x)) : q.design / 2 * exp(-x) * cos(x)
                Q = max(Q, v)
            }
            r.plocal = pl; r.Mmax = M; r.Qmax = Q
            r.Qb = 1.5 * p.concrete.Rbt * 1000 * h0
            var found = false
            if let As = RC.As(M: M, b: 1, h0: h0, c: p.concrete, r: p.rebar) {
                r.As = max(As, 0.001 * h0)
                outer: for dd in [10, 12, 14, 16, 18, 20] {
                    for st in [0.2, 0.15] where Bar.area(dd) / st >= r.As {
                        r.d = dd; r.step = st; found = true
                        break outer
                    }
                }
            }
            let pLong = Nl / r.area + G + L.slabAreaLong
            r.s = Soil.settlement(p: pLong, d: r.depth, b: bEq, l: lEq, soil: soil).s
            if found && r.pavg <= r.R && r.plocal <= 1.2 * r.R && r.Qmax <= r.Qb && r.s <= r.su { break }
            t += 0.05
        }
        if t > 0.6 + 1e-9 { r.t = 0.6 }

        // --- Арматурные сетки (для объёмов и 3D) ---
        let c = r.cover
        var lenOneFace = 0.0
        for horizontal in [true, false] {
            let a0 = (horizontal ? lo.y : lo.x) + c, a1 = (horizontal ? hi.y : hi.x) - c
            var v = a0
            while v <= a1 + 1e-9 {
                for (s0, s1) in Geo.scan(r.rings, at: v + 1e-7, horizontal: horizontal) {
                    let u0 = s0 + c, u1 = s1 - c
                    guard u1 > u0 else { continue }
                    lenOneFace += u1 - u0
                    r.bars.append(horizontal ? (V2(u0, v), V2(u1, v)) : (V2(v, u0), V2(v, u1)))
                }
                v += r.step
            }
        }
        let lap = RC.lap(d: r.d, c: p.concrete, r: p.rebar)
        let cls = p.rebar.rawValue
        r.rebar.append(RebarItem(name: "Нижняя сетка (2 направления)", d: r.d, cls: cls, spec: "шаг \(Int(r.step * 1000))×\(Int(r.step * 1000)) мм", length: lenOneFace * (1 + lap / 11.7)))
        r.rebar.append(RebarItem(name: "Верхняя сетка (2 направления)", d: r.d, cls: cls, spec: "шаг \(Int(r.step * 1000))×\(Int(r.step * 1000)) мм", length: lenOneFace * (1 + lap / 11.7)))
        let nU = Int((r.perimeter / r.step).rounded(.up))
        r.rebar.append(RebarItem(name: "П-образные по торцам плиты", d: max(10, r.d - 2), cls: cls, spec: "\(nU) шт., шаг \(Int(r.step * 1000))", length: Double(nU) * (2 * 0.4 + r.t - 2 * c)))
        let nSup = Int((r.area * 1.5).rounded(.up))
        r.rebar.append(RebarItem(name: "Поддерживающие каркасы («лягушки»)", d: 10, cls: cls, spec: "≈1.5 шт/м², \(nSup) шт.", length: Double(nSup) * (r.t - 2 * c - 0.024 + 0.6)))

        r.concrete = r.area * r.t
        r.formwork = r.perimeter * r.t
        r.sand = (r.area + r.perimeter * 0.3) * p.slabCushion
        r.eps = r.area + r.perimeter * 1.2

        // --- Проверки ---
        r.checks.append(Check(title: "Среднее давление под плитой", value: "p = \(fmt(r.pavg, 1)) кПа ≤ R = \(fmt(r.R, 1)) кПа",
                              ok: r.pavg <= r.R, ref: "СП 22.13330.2016, ф. (5.7), п. 5.6.26"))
        r.checks.append(Check(title: "Краевое давление под стенами (модель Винклера)", value: "pmax = \(fmt(r.plocal, 1)) кПа ≤ 1.2R = \(fmt(1.2 * r.R, 1)) кПа",
                              ok: r.plocal <= 1.2 * r.R, ref: "СП 22.13330.2016, п. 5.6.26"))
        r.checks.append(Check(title: "Изгиб плиты под стенами", value: "M = \(fmt(r.Mmax, 1)) кН·м/м → As = \(fmt(r.As * 1e6, 0)) мм²/м; принято Ø\(r.d) шаг \(Int(r.step * 1000)) (\(fmt(Bar.area(r.d) / r.step * 1e6, 0)) мм²/м)",
                              ok: Bar.area(r.d) / r.step >= r.As - 1e-12 && r.As > 0, ref: "СП 63.13330.2018, п. 8.1.8–8.1.14, 10.3.6"))
        r.checks.append(Check(title: "Поперечная сила без поперечной арматуры", value: "Q = \(fmt(r.Qmax, 1)) кН/м ≤ Qb = \(fmt(r.Qb, 1)) кН/м",
                              ok: r.Qmax <= r.Qb, ref: "СП 63.13330.2018, п. 8.1.33"))
        r.checks.append(Check(title: "Осадка (центр плиты)", value: "s = \(fmt(r.s * 100, 1)) см ≤ su = \(fmt(r.su * 100, 0)) см",
                              ok: r.s <= r.su, ref: "СП 22.13330.2016, п. 5.6.31, прил. Г"))

        r.notes.append("Подушка: песок средней крупности \(Int(p.slabCushion * 1000)) мм, послойное уплотнение до Kупл ≥ 0.95; геотекстиль под подушкой.")
        if soil.heave != .none {
            r.notes.append("Пучинистый грунт: утеплённая плита (УШП) — ЭППС 100 мм под плитой и утеплённая отмостка 1.2 м по периметру (≈ \(fmt(r.eps, 0)) м² ЭППС), дренаж по периметру.")
        }
        r.notes.append("Под несущими стенами допускается устройство рёбер жёсткости; коммуникации закладываются до бетонирования.")
        r.notes.append("Коэффициент постели k = \(fmt(k, 0)) кН/м³ принят по типу грунта — уточняйте по данным изысканий.")
        return r
    }
}
