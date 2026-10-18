import Foundation
import simd

/// На что опирается прогон в данной точке
enum GirderSupport: String {
    case wall = "наружная стена"
    case girder = "другой прогон"
    case partition = "несущая стена"
    case hanger = "подвеска к коньку"
    case post = "стойка"
}

/// Прогон (ригель) перекрытия: пакет досок на ребро, собранный из хлыстов ≤ 6 м со стыками над опорами
struct Girder {
    var a: V2, b: V2
    var supports: [(u: Double, kind: GirderSupport)] = []
    var check: Timber.BeamCheck
    var above = false              // над балками (подвесной, балки подвешены к нему), иначе — под балками
    var length: Double { (b - a).len }
    var maxGap: Double { zip(supports, supports.dropFirst()).map { $1.u - $0.u }.max() ?? length }
    func point(_ u: Double) -> V2 { a + (b - a).unit * u }
    var posts: [V2] { supports.filter { $0.kind == .post }.map { point($0.u) } }
    var hangers: [V2] { supports.filter { $0.kind == .hanger }.map { point($0.u) } }
    var title: String { "\(check.count)×(\(check.sec.label))" }
    /// Куски пакета: каждый ≤ 6 м, стык — только над опорой
    var pieces: [(Double, Double)] { FrameGen.pieces(supports.map(\.u), length: length) }
}

extension FrameGen {
    static let stock = 6.0
    /// Предпочтительный пролёт балки без промежуточной опоры, м
    static let maxFree = 4.8

    /// Разбивка элемента длиной length на куски ≤ 6 м со стыками только в точках опор
    static func pieces(_ supports: [Double], length: Double) -> [(Double, Double)] {
        let cuts = supports.filter { $0 > 0.05 && $0 < length - 0.05 }.sorted()
        var out: [(Double, Double)] = []
        var s = 0.0
        while length - s > 1e-6 {
            if length - s <= stock + 1e-6 { out.append((s, length)); break }
            let next = cuts.last { $0 > s + 0.3 && $0 <= s + stock } ?? min(s + stock, length)
            out.append((s, next)); s = next
        }
        return out
    }

    /// Прогон по отрезку a→b: опоры на концах и в пересечениях, где пролёт велик — стойки
    /// (по возможности — в местах перегородок, чтобы стойка ушла в стену)
    static func girder(_ a: V2, _ b: V2, ends: (GirderSupport, GirderSupport), inner: [(Double, GirderSupport)], postSpots: [Double],
                       qd: Double, qn: Double, trib: Double, above: Bool) -> Girder {
        let L = (b - a).len
        var sup: [(u: Double, kind: GirderSupport)] = [(0, ends.0), (L, ends.1)] + inner.filter { $0.0 > 0.2 && $0.0 < L - 0.2 }.map { (u: $0.0, kind: $0.1) }
        func norm() { sup.sort { $0.u < $1.u }; sup = sup.reduce(into: []) { acc, s in if let l = acc.last, s.u - l.u < 0.3 { if s.kind != .post { acc[acc.count - 1] = s } } else { acc.append(s) } } }
        norm()
        let sizes = [Lumber(50, 200), Lumber(50, 250)]
        var chk = Timber.pickBeam(span: 1, qd: qd, qn: qn, steps: [trib], sizes: sizes, counts: [2, 3, 4])
        for _ in 0..<40 {
            let gaps = zip(sup, sup.dropFirst()).map { ($0.u, $1.u) }
            guard let g = gaps.max(by: { $0.1 - $0.0 < $1.1 - $1.0 }) else { break }
            chk = Timber.pickBeam(span: max(g.1 - g.0, 0.5), qd: qd, qn: qn, steps: [trib], sizes: sizes, counts: [2, 3, 4])
            if chk.ok && g.1 - g.0 <= 4.0 { break }
            // стойка — в середине самого длинного пролёта, или у перегородки рядом
            let mid = (g.0 + g.1) / 2
            let spot = postSpots.filter { $0 > g.0 + 0.6 && $0 < g.1 - 0.6 && abs($0 - mid) < (g.1 - g.0) * 0.3 }.min { abs($0 - mid) < abs($1 - mid) }
            sup.append((spot ?? mid, .post)); norm()
        }
        return Girder(a: a, b: b, supports: sup, check: chk, above: above)
    }

    /// Чердачное перекрытие (мансарда) под скатной кровлей — по крыльям:
    /// балки идут поперёк крыла рядом со стропилами (работают затяжками, распора на стены нет);
    /// при пролёте > 4.8 м — подвесной прогон по оси крыла над балками: концы — на стены (или на прогон соседнего крыла),
    /// по длине — подвески («бабки») к коньковым парам стропил, где конька нет — стойки
    static func atticJoists(_ p: Project, rings: [[V2]], supports allLines: [BearingLine], zBottom: Double, step: Double,
                            qd: Double, qn: Double, title: String, sizes: [Lumber], D: Double) -> JoistLayout {
        let model = RoofModel.of(p)
        let wings = p.wings
        let gridOff = p.modular ? -D / 2 : 0
        struct Region { var w: Wing; var lo: Double; var hi: Double; var cutLo: Bool; var cutHi: Bool }
        var regions: [Region] = []
        for (wi, w) in wings.enumerated() {
            var r = Region(w: w, lo: w.alongMin, hi: w.alongMax, cutLo: false, cutHi: false)
            for e in wings[0..<wi] {
                let eSpan0 = w.axisX ? e.y0 : e.x0, eSpan1 = w.axisX ? e.y1 : e.x1
                let eAl0 = w.axisX ? e.x0 : e.y0, eAl1 = w.axisX ? e.x1 : e.y1
                guard eSpan0 <= w.spanMin + 1e-6, eSpan1 >= w.spanMax - 1e-6 else { continue }
                if eAl0 <= r.lo + 1e-6 && eAl1 > r.lo { r.lo = eAl1; r.cutLo = true }
                if eAl1 >= r.hi - 1e-6 && eAl0 < r.hi { r.hi = eAl0; r.cutHi = true }
            }
            if r.hi - r.lo > 0.3 { regions.append(r) }
        }
        var jl = JoistLayout(title: title, alongX: false, check: Timber.pickBeam(span: 1, qd: qd, qn: qn, steps: [step], sizes: sizes))
        jl.zBottom = zBottom; jl.qd = qd; jl.qn = qn
        jl.supports = allLines.map { ($0.a, $0.b) }
        let partLines = allLines.filter { !$0.isExterior }
        // прогоны — сначала у всех крыльев (концы прогонов соседних крыльев опираются друг на друга)
        var girderSpecs: [(a: V2, b: V2, ends: (GirderSupport, GirderSupport), w: Wing)] = []
        for r in regions {
            let w = r.w
            let span = w.spanMax - w.spanMin
            let n = span > 2 * maxFree ? 2 : span > maxFree ? 1 : 0
            for k in 0..<n {
                let c = w.spanMin + span * Double(k + 1) / Double(n + 1)
                guard let iv = Geo.scan(rings, at: c, horizontal: w.axisX).first(where: { $0.0 < (r.lo + r.hi) / 2 && $0.1 > (r.lo + r.hi) / 2 }) else { continue }
                var lo = max(iv.0, r.lo), hi = min(iv.1, r.hi)
                var e0: GirderSupport = abs(lo - iv.0) < 1e-6 ? .wall : .girder
                var e1: GirderSupport = abs(hi - iv.1) < 1e-6 ? .wall : .girder
                // конец в зоне соседнего крыла — продлить до его прогона (или до стены)
                func otherGirder(_ from: Double, _ dirSign: Double) -> Double? {
                    girderSpecs.compactMap { g -> Double? in
                        let pos = w.axisX ? g.a.x : g.a.y            // поперечный прогон: его координата вдоль нашей оси
                        let horiz = abs(g.a.y - g.b.y) < 1e-6
                        guard horiz != w.axisX else { return nil }
                        let s0 = w.axisX ? min(g.a.y, g.b.y) : min(g.a.x, g.b.x), s1 = w.axisX ? max(g.a.y, g.b.y) : max(g.a.x, g.b.x)
                        guard c >= s0 - 0.05 && c <= s1 + 0.05, (pos - from) * dirSign > 0.1 else { return nil }
                        return pos
                    }.min { abs($0 - from) < abs($1 - from) }
                }
                if e0 == .girder { if let g = otherGirder(lo, -1), g >= iv.0 { lo = g } else { lo = iv.0; e0 = .wall } }
                if e1 == .girder { if let g = otherGirder(hi, 1), g <= iv.1 { hi = g } else { hi = iv.1; e1 = .wall } }
                let a = w.axisX ? V2(lo, c) : V2(c, lo), b = w.axisX ? V2(hi, c) : V2(c, hi)
                girderSpecs.append((a, b, (e0, e1), w))
            }
        }
        // балки
        var lineSup: [[Double]] = []
        var maxSpan = 0.0
        for r in regions {
            let w = r.w
            var cs: [Double] = []
            if !r.cutLo { cs.append(r.lo + 0.025) }
            var k = ((r.lo - gridOff) / step).rounded(.down)
            while k * step + gridOff + 0.05 < r.hi {
                let c = k * step + gridOff + 0.05
                if c > r.lo + 0.08 && c < r.hi - 0.08 && !cs.contains(where: { abs($0 - c) < 0.1 }) { cs.append(c) }
                k += 1
            }
            if !r.cutHi && !cs.contains(where: { abs($0 - (r.hi - 0.025)) < 0.1 }) { cs.append(r.hi - 0.025) }
            for c in cs {
                for (s0, s1) in Geo.scan(rings, at: c, horizontal: !w.axisX) where s1 > w.spanMin + 0.1 && s0 < w.spanMax - 0.1 {
                    let a0 = max(s0, w.spanMin), a1 = min(s1, w.spanMax)
                    var sup = [a0, a1]
                    for ln in partLines {
                        let d = ln.dir
                        guard w.axisX ? abs(d.y) < 0.1 : abs(d.x) < 0.1 else { continue }   // стена вдоль оси крыла
                        let pos = w.axisX ? ln.a.y : ln.a.x
                        let r0 = w.axisX ? min(ln.a.x, ln.b.x) : min(ln.a.y, ln.b.y), r1 = w.axisX ? max(ln.a.x, ln.b.x) : max(ln.a.y, ln.b.y)
                        if pos > a0 + 0.05 && pos < a1 - 0.05 && c >= r0 - 0.01 && c <= r1 + 0.01 { sup.append(pos) }
                    }
                    for g in girderSpecs where g.w.axisX == w.axisX {
                        let pos = w.axisX ? g.a.y : g.a.x
                        let r0 = w.axisX ? min(g.a.x, g.b.x) : min(g.a.y, g.b.y), r1 = w.axisX ? max(g.a.x, g.b.x) : max(g.a.y, g.b.y)
                        if pos > a0 + 0.05 && pos < a1 - 0.05 && c >= r0 - 0.01 && c <= r1 + 0.01 { sup.append(pos) }
                    }
                    sup.sort()
                    for i in 1..<sup.count { maxSpan = max(maxSpan, sup[i] - sup[i - 1]) }
                    jl.lines.append(w.axisX ? (V2(c, a0), V2(c, a1)) : (V2(a0, c), V2(a1, c)))
                    lineSup.append(sup.map { $0 - a0 })
                }
            }
        }
        jl.lineSupports = lineSup
        jl.maxSpan = maxSpan
        jl.check = Timber.pickBeam(span: max(maxSpan, 0.5), qd: qd, qn: qn, steps: [step], sizes: sizes)
        // прогоны: подвески к коньку — там, где над прогоном конёк (через пару стропил), стойки — где конька нет
        let trib = 1.25 * maxSpan
        for g in girderSpecs {
            let L = (g.b - g.a).len, d = (g.b - g.a) / L
            let half = g.w.span / 2
            let along0 = g.w.axisX ? g.a.x : g.a.y
            var inner: [(Double, GirderSupport)] = []
            var k = ((along0 - gridOff) / (2 * step)).rounded(.up)
            while k * 2 * step + gridOff - along0 < L - 0.2 {
                let u = k * 2 * step + gridOff - along0
                let v = g.a + d * u
                // конёк над прогоном: высота ската в этой точке — максимум поперёк крыла (по обе стороны ниже)
                let n = V2(-d.y, d.x) * 0.3
                if u > 0.2, p.roofType == .gable || p.roofType == .hip, let dd = model.depth(v), dd.d >= half - 0.06,
                   let l = model.depth(v + n), let rr = model.depth(v - n), l.d < dd.d - 0.05, rr.d < dd.d - 0.05 {
                    inner.append((u, .hanger))
                }
                k += 1
            }
            for ln in partLines {
                let t = Geo.segmentIntersection(g.a, g.b, ln.a, ln.b)
                if let t { inner.append((t * L, .partition)) }
            }
            // места для стоек — пересечения с любыми перегородками (стойка уйдёт в стену)
            let spots = p.partitions.compactMap { pt in Geo.segmentIntersection(g.a, g.b, pt.a, pt.b).map { $0 * L } }
            jl.girders.append(girder(g.a, g.b, ends: g.ends, inner: inner, postSpots: spots, qd: qd, qn: qn, trib: trib, above: true))
        }
        jl.beams = jl.girders.map { ($0.a, $0.b) }
        return jl
    }

    /// Прогоны обычного перекрытия (под балками): опоры — стены, несущие перегородки и стойки до основания
    static func floorGirders(_ jl: inout JoistLayout, _ p: Project, supports allLines: [BearingLine]) {
        let trib = 1.25 * max(jl.maxSpan, 1)
        jl.girders = jl.beams.map { a, b in
            let L = (b - a).len
            let inner: [(Double, GirderSupport)] = allLines.compactMap { ln in
                Geo.segmentIntersection(a, b, ln.a, ln.b).map { ($0 * L, ln.isExterior ? .wall : .partition) }
            }
            let spots = p.partitions.compactMap { pt in Geo.segmentIntersection(a, b, pt.a, pt.b).map { $0 * L } }
            return girder(a, b, ends: (.wall, .wall), inner: inner, postSpots: spots, qd: jl.qd, qn: jl.qn, trib: trib, above: false)
        }
    }

    /// Прогоны в каркас: пакеты по кускам ≤ 6 м, стойки до нижнего основания
    static func addGirders(_ F: inout Framing, _ j: JoistLayout, stage: Stage3D, postBase: Double, seq: Int = 0) {
        let jh = j.check.sec.wm
        for g in j.girders {
            // пакет — отдельные доски 50×h (так они и покупаются), сшитые между собой
            let sec = g.check.sec
            let n = g.check.count
            let gh = sec.wm
            let z0 = g.above ? j.zBottom + jh : j.zBottom - gh
            let d = (g.b - g.a).unit, side = V2(-d.y, d.x)
            for (u0, u1) in g.pieces {
                for c in 0..<n {
                    let off = side * (Double(c) - Double(n - 1) / 2) * sec.tm
                    var m = onEdge(g.a + d * u0 + off, g.a + d * u1 + off, z0: z0, sec: sec, kind: .girder, stage: stage)
                    m.seq = seq
                    F.members.append(m)
                }
            }
            for v in g.posts {
                let top = g.above ? j.zBottom + jh : z0
                var m = Member(kind: .post, sec: Lumber(100, 150), a: v3(v, postBase), b: v3(v, top), up: V3(d.x, d.y, 0), stage: stage)
                m.seq = seq
                F.members.append(m)
            }
        }
    }
}
