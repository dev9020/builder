import Foundation

struct BearingLine: Identifiable {
    let id: String
    let name: String
    let a: V2
    let b: V2
    let material: WallMaterial
    let thickness: Double
    let isExterior: Bool
    var length: Double { (b - a).len }
    var dir: V2 { (b - a).unit }
}

/// Погонная нагрузка на верх фундамента, кН/м
struct LineLoad {
    var wall = 0.0, wallD = 0.0
    var floors = 0.0, floorsD = 0.0
    var roof = 0.0, roofD = 0.0
    var snow = 0.0
    var live = 0.0

    var gk: Double { wall + floors + roof }
    var gd: Double { wallD + floorsD + roofD }
    /// Нормативная (γf = 1) — для расчёта по деформациям и проверки p ≤ R
    var char: Double { gk + snow + live }
    /// Расчётная, основное сочетание (СП 20.13330.2016 п. 6.2): ψ = 1.0 для основной кратковременной, 0.9 — для остальных
    var design: Double { gd + max(1.4 * snow + 0.9 * 1.3 * live, 0.9 * 1.4 * snow + 1.3 * live) }
    /// Длительная часть — для осадок (пониженные значения: снег 0.5, полезная 0.35)
    var longTerm: Double { gk + 0.5 * snow + 0.35 * live }
}

struct LoadSummary {
    var walls = 0.0, floors = 0.0, roof = 0.0, snow = 0.0, live = 0.0
    var total: Double { walls + floors + roof + snow + live }
}

struct LoadResult {
    var lines: [BearingLine] = []
    var stripLoads: [LineLoad] = []
    var slabLoads: [LineLoad] = []
    var slabAreaChar = 0.0, slabAreaDesign = 0.0, slabAreaLong = 0.0
    var floorArea = 0.0, roofArea = 0.0
    var snowS = 0.0, snowMu = 1.0, roofDead = 0.0
    var wallHeight = 0.0
    var summary = LoadSummary()
    var floorTrib: [Double] = []
    var roofTrib: [Double] = []
    var fronton: [Double] = []
}

@inline(__always) func cross2(_ a: V2, _ b: V2) -> Double { a.x * b.y - a.y * b.x }

/// Скатная кровля как «прямой скелет» ортогонального контура: высота точки = tanα × расстояние
/// до карнизной стены своего ската. Карнизные стены — параллельные коньку крыла (двускатная),
/// все стены (вальмовая) или нижние стороны крыльев (односкатная). Остальные стены — фронтоны.
struct RoofModel {
    struct Edge {
        var a: V2, b: V2, n: V2
        var eave: Bool
        var bisA = V2(0, 0), bisB = V2(0, 0)
    }
    var edges: [Edge] = []
    var type: RoofType
    var tanA: Double
    /// Подъём ската над верхом стен (стропила на мауэрлате), м
    var lift: Double

    /// reference — исходный контур (той же топологии) для определения карнизных стен
    init(rings: [[V2]], wings: [Wing], type: RoofType, tanA: Double, lift: Double, reference: [[V2]]? = nil) {
        self.type = type
        self.tanA = tanA
        self.lift = lift
        guard type != .flat else { return }
        for (ri, r0) in rings.enumerated() {
            var r = r0
            var ref = reference?[ri] ?? r0
            if (ri == 0) != (Geo.signedArea(r) > 0) { r.reverse(); ref.reverse() }   // материал всегда слева
            var es: [Edge] = r.indices.map { i in
                let a = r[i], b = r[(i + 1) % r.count], d = (b - a).unit
                let eave = RoofModel.isEave(ref[i], ref[(i + 1) % ref.count], wings, type)
                return Edge(a: a, b: b, n: V2(-d.y, d.x), eave: eave)
            }
            for i in es.indices {
                let prev = es[(i - 1 + es.count) % es.count], next = es[(i + 1) % es.count]
                es[i].bisA = prev.eave ? (es[i].n + prev.n).unit : es[i].n
                es[i].bisB = next.eave ? (es[i].n + next.n).unit : es[i].n
            }
            edges += es
        }
    }

    static func of(_ p: Project, overhang: Double = 0) -> RoofModel {
        let tanA = p.roofType == .flat ? 0 : tan(p.roofAngleEff * .pi / 180)
        let tMax = p.segments.map { p.thickness($0.material) }.max() ?? 0.2
        let base = p.rings
        let rings = overhang > 0 ? base.enumerated().map { i, r in Geo.offset(r, by: i == 0 ? overhang : -overhang) } : base
        return RoofModel(rings: rings, wings: p.wings, type: p.roofType, tanA: tanA, lift: tMax / 2 * tanA + 0.1, reference: base)
    }

    static func isEave(_ a: V2, _ b: V2, _ wings: [Wing], _ type: RoofType) -> Bool {
        switch type {
        case .flat: return false
        case .hip: return true
        case .gable, .shed:
            let d = (b - a).unit
            for w in wings {
                guard w.axisX ? abs(d.x) > 0.99 : abs(d.y) > 0.99 else { continue }
                let s = w.axisX ? a.y : a.x
                let a0 = w.axisX ? min(a.x, b.x) : min(a.y, b.y)
                let a1 = w.axisX ? max(a.x, b.x) : max(a.y, b.y)
                guard min(a1, w.alongMax) - max(a0, w.alongMin) > 1e-6 else { continue }
                if abs(s - w.spanMin) < 1e-6 { return true }
                if type == .gable && abs(s - w.spanMax) < 1e-6 { return true }
            }
            return false
        }
    }

    /// Расстояние до карниза своего ската и индекс карнизной стены
    func depth(_ p: V2) -> (d: Double, edge: Int)? {
        var best = Double.infinity, bi = -1
        for (i, e) in edges.enumerated() where e.eave {
            let dist = dot2(p - e.a, e.n)
            if dist < -1e-6 || dist >= best { continue }
            if cross2(e.bisA, p - e.a) * cross2(e.bisA, e.b - e.a) < -1e-9 { continue }
            if cross2(e.bisB, p - e.b) * cross2(e.bisB, e.a - e.b) < -1e-9 { continue }
            best = dist; bi = i
        }
        if bi >= 0 { return (max(best, 0), bi) }
        // запасной вариант — ближайший карниз
        for (i, e) in edges.enumerated() where e.eave {
            let dist = Geo.distToSegment(p, e.a, e.b)
            if dist < best { best = dist; bi = i }
        }
        return bi >= 0 ? (best, bi) : nil
    }

    /// Карнизная ли стена (отрезок лежит на карнизной стороне контура)
    func onEave(_ a: V2, _ b: V2) -> Bool {
        edges.contains { $0.eave && Geo.distToSegment(a, $0.a, $0.b) < 1e-6 && Geo.distToSegment(b, $0.a, $0.b) < 1e-6 }
    }

    /// Высота фронтона над верхом стены вдоль отрезка
    func profile(_ a: V2, _ b: V2) -> [(u: Double, h: Double)] {
        guard type == .gable || type == .shed else { return [] }
        let len = (b - a).len
        guard len > 1e-6, !onEave(a, b) else { return [] }
        let dir = (b - a) / len
        // точки берём на 1 мм внутри контура, чтобы не зависеть от погрешности на границе
        let inward = edges.first { Geo.distToSegment(a, $0.a, $0.b) < 1e-6 && Geo.distToSegment(b, $0.a, $0.b) < 1e-6 }?.n ?? V2(0, 0)
        let n = max(2, Int(len / 0.1))
        return (0...n).map { i in
            let u = Double(i) / Double(n) * len
            let uu = min(max(u, 1e-3), len - 1e-3)
            return (u, tanA * (depth(a + dir * uu + inward * 1e-3)?.d ?? 0) + lift)
        }
    }

    static func area(_ prof: [(u: Double, h: Double)]) -> Double {
        guard prof.count > 1 else { return 0 }
        var s = 0.0
        for i in 1..<prof.count { s += (prof[i].u - prof[i - 1].u) * (prof[i].h + prof[i - 1].h) / 2 }
        return s
    }
}

enum LoadCalc {
    static func lines(_ p: Project) -> [BearingLine] {
        var out: [BearingLine] = []
        for (i, s) in p.segments.enumerated() {
            out.append(BearingLine(id: s.id, name: "Н\(i + 1)", a: s.a, b: s.b, material: s.material,
                                   thickness: p.thickness(s.material), isExterior: true))
        }
        for (i, pt) in p.partitions.enumerated() where pt.onFoundation && pt.length > 0.05 {
            out.append(BearingLine(id: pt.id.uuidString, name: "П\(i + 1)", a: pt.a, b: pt.b, material: pt.material,
                                   thickness: pt.thickness, isExterior: false))
        }
        return out
    }

    /// Площадь проёмов на несущей линии (все этажи), м². Наружные двери — только 1-й этаж.
    static func openingArea(_ p: Project, _ ln: BearingLine, _ ops: [Opening]) -> Double {
        var A = 0.0
        for o in ops {
            guard let host = p.hostLine(o.host) else { continue }
            var reps = Double(p.floors)
            switch o.host {
            case .partition(let id):
                if ln.id == id.uuidString { A += o.width * o.height * reps }
            case .edge:
                if o.kind.isDoor { reps = 1 }
                guard Geo.distToSegment(ln.a, host.a, host.b) < 1e-6, Geo.distToSegment(ln.b, host.a, host.b) < 1e-6 else { continue }
                let dir = (host.b - host.a).unit
                let s0 = dot2(ln.a - host.a, dir), s1 = dot2(ln.b - host.a, dir)
                let ov = min(max(s0, s1), o.pos + o.width / 2) - max(min(s0, s1), o.pos - o.width / 2)
                if ov > 0 { A += ov * o.height * reps }
            }
        }
        return A
    }

    static func nearest(_ pt: V2, _ cand: [Int], _ lines: [BearingLine]) -> Int {
        var best = cand.first ?? 0, bd = Double.greatestFiniteMagnitude
        for i in cand {
            let d = Geo.distToSegment(pt, lines[i].a, lines[i].b)
            if d < bd { bd = d; best = i }
        }
        return best
    }

    static func run(_ p: Project) -> LoadResult {
        var r = LoadResult()
        let rings = p.rings
        let lines = lines(p)
        r.lines = lines
        let area = Geo.area(rings)
        r.floorArea = area
        let H = Double(p.floors) * p.floorHeight
        r.wallHeight = H
        let pitched = p.roofType != .flat
        let alpha = p.roofAngleEff * .pi / 180
        let roof = RoofModel.of(p)
        guard !lines.isEmpty, area > 0 else { return r }

        // --- Грузовые площади (перекрытия — ближайшая опора; кровля — карнизная стена своего ската) ---
        let ext = lines.indices.filter { lines[$0].isExterior }
        let all = Array(lines.indices)
        let faceCand: [[Int]] = roof.edges.map { e in
            let c = ext.filter { Geo.distToSegment(lines[$0].a, e.a, e.b) < 1e-6 && Geo.distToSegment(lines[$0].b, e.a, e.b) < 1e-6 }
            return c.isEmpty ? ext : c
        }
        var ft = [Double](repeating: 0, count: lines.count)
        var rt = ft
        let (lo, hi) = Geo.bbox(rings)
        let step = max(0.05, (area / 25000).squareRoot())
        let cell = step * step
        var y = lo.y + step / 2
        while y < hi.y {
            var x = lo.x + step / 2
            while x < hi.x {
                let pt = V2(x, y)
                if Geo.contains(pt, rings) {
                    ft[nearest(pt, all, lines)] += cell
                    let cand = pitched ? (roof.depth(pt).map { faceCand[$0.edge] } ?? ext) : all
                    rt[nearest(pt, cand, lines)] += cell
                }
                x += step
            }
            y += step
        }
        let sf = area / max(ft.reduce(0, +), 1e-9), sr = area / max(rt.reduce(0, +), 1e-9)
        ft = ft.map { $0 * sf }
        rt = rt.map { $0 * sr }
        r.floorTrib = ft
        r.roofTrib = rt

        // --- Интенсивности, кПа ---
        let perimeter = rings.reduce(0) { $0 + Geo.perimeter($1) }
        let roofFactor = pitched ? (area + perimeter * p.overhang) / area : 1.0
        r.roofArea = area * roofFactor / (pitched ? cos(alpha) : 1)
        // Снег: СП 20.13330.2016 п. 10.1, прил. Б (μ для скатных покрытий), ce = ct = 1
        var mu = 1.0
        if pitched {
            let ang = p.roofAngleEff
            if ang >= 60 { mu = 0 } else if ang > 30 { mu = (60 - ang) / 30 }
        }
        r.snowMu = mu
        r.snowS = p.snowRegion.s0 * mu
        let roofDead: Double = pitched
            ? (p.covering.weight + 0.2 + (p.roofInsulated ? 0.25 : 0)) / cos(alpha)
            : p.flatSlab.weight
        r.roofDead = roofDead
        let roofG = 1.2

        // Ненесущие перегородки (опираются на перекрытие), вес одного этажа
        var npW = 0.0
        for pt in p.partitions where !pt.onFoundation {
            npW += pt.material.areaWeight(pt.thickness) * pt.length * p.floorHeight
        }
        let npI = npW / area

        var fDead = 0.0, fDeadD = 0.0, fLive = 0.0
        for _ in 1..<max(p.floors, 1) {
            fDead += p.floorType.dead + npI
            fDeadD += p.floorType.dead * p.floorType.gammaF + npI * 1.2
            fLive += 1.5
        }
        if pitched {           // чердачное перекрытие, полезная 0.7 кПа (СП 20 табл. 8.3)
            fDead += p.floorType.dead
            fDeadD += p.floorType.dead * p.floorType.gammaF
            fLive += 0.7
        }
        var gDead = 0.0, gDeadD = 0.0, gLive = 0.0
        if p.groundFloor != .onGround {
            let fl = p.groundFloor.dead + (p.floorBase == .joists ? p.floorExtraDead : 0)
            gDead = fl + npI
            gDeadD = fl * p.groundFloor.gammaF + npI * 1.2
            gLive = 1.5
        }
        // Плита: пол 1-го этажа опирается непосредственно на плиту
        r.slabAreaChar = 1.0 + npI + 1.5
        r.slabAreaDesign = 1.3 + npI * 1.2 + 1.5 * 1.3
        r.slabAreaLong = 1.0 + npI + 0.35 * 1.5

        // --- Погонные нагрузки ---
        var fr = [Double](repeating: 0, count: lines.count)
        var sum = LoadSummary()
        let ops = p.validOpenings
        for (i, ln) in lines.enumerated() {
            let L = max(ln.length, 1e-6)
            let w = ln.material.areaWeight(ln.thickness)
            let fac = ln.isExterior ? p.facade.weight : 0
            if ln.isExterior && pitched {
                fr[i] = RoofModel.area(roof.profile(ln.a, ln.b))
            }
            // проёмы: минус кладка, плюс заполнение (окна/двери ≈ 0.35 кПа)
            let ao = openingArea(p, ln, ops) / L
            var base = LineLoad()
            base.wall = (w + fac) * (H + fr[i] / L - ao) + 0.35 * ao
            base.wallD = (w * ln.material.gammaF + fac * 1.2) * (H + fr[i] / L - ao) + 0.35 * 1.2 * ao
            let tf = ft[i] / L, tr = rt[i] * roofFactor / L
            base.floors = fDead * tf
            base.floorsD = fDeadD * tf
            base.live = fLive * tf
            base.roof = roofDead * tr
            base.roofD = roofDead * roofG * tr
            base.snow = r.snowS * tr

            var strip = base
            strip.floors += gDead * tf
            strip.floorsD += gDeadD * tf
            strip.live += gLive * tf
            r.stripLoads.append(strip)
            r.slabLoads.append(base)

            sum.walls += strip.wall * L
            sum.floors += strip.floors * L
            sum.roof += strip.roof * L
            sum.snow += strip.snow * L
            sum.live += strip.live * L
        }
        r.fronton = fr
        r.summary = sum
        return r
    }
}
