import SceneKit
import AppKit
import simd

/// Шаг этапа «Пол»: сколько слоёв основания уже сделано и видны ли трубы тёплого пола
struct ScreedStep {
    var title: String
    var note: String
    var layers: Int
    var pipes: Bool
}

extension Steps3D {
    static func screedSteps(_ p: Project) -> [ScreedStep] {
        var out: [ScreedStep] = []
        for (k, l) in screedLayers(p).enumerated() {
            if p.floorHeating == .water && l.name.contains("трубы") {
                out.append(ScreedStep(title: "Тёплый пол: трубы", note: "Петли PE-Xa 16 шаг 150–200 мм от коллектора, по краю комнат чаще; крепление к утеплителю скобами/на сетку; опрессовка 6 бар — до заливки и под давлением во время неё", layers: k, pipes: true))
            }
            let short = l.name.components(separatedBy: CharacterSet(charactersIn: ",(")).first?.trimmingCharacters(in: .whitespaces) ?? l.name
            let lower = short.dropFirst().first.map { $0.isLowercase } ?? true
            out.append(ScreedStep(title: "Пол: " + (lower ? short.prefix(1).lowercased() + short.dropFirst() : short), note: l.name, layers: k + 1, pipes: out.last?.pipes ?? false))
        }
        return out
    }
}

extension SceneBuilder {
    typealias Hole = (u0: Double, u1: Double, z0: Double, z1: Double)

    /// Вертикальный слой вдоль A + dir·u (u = 0…L): от zb до верха top(u), с вырезами проёмов; UV — в метрах
    static func vSheet(_ A: V2, _ dir: V2, _ L: Double, zb: Double, top: [(u: Double, z: Double)], holes: [Hole], _ m: SCNMaterial) -> SCNNode? {
        guard L > 0.02, let t0 = top.first else { return nil }
        func topAt(_ u: Double) -> Double {
            guard let i = top.firstIndex(where: { $0.u >= u }) else { return top.last!.z }
            if i == 0 { return t0.z }
            let a = top[i - 1], b = top[i]
            return a.z + (b.z - a.z) * (u - a.u) / max(b.u - a.u, 1e-9)
        }
        var us = [0.0, L] + holes.flatMap { [$0.u0, $0.u1] } + top.map(\.u)
        us = us.filter { $0 >= 0 && $0 <= L }.sorted()
        us = us.reduce(into: [Double]()) { acc, x in if acc.isEmpty || x - acc.last! > 1e-4 { acc.append(x) } }
        let n = V2(-dir.y, dir.x)
        var verts: [SCNVector3] = [], norms: [SCNVector3] = [], uvs: [CGPoint] = [], idx: [Int32] = []
        func quad(_ ua: Double, _ ub: Double, _ za0: Double, _ zb0: Double, _ za1: Double, _ zb1: Double) {
            let base = Int32(verts.count)
            for (u, z) in [(ua, za0), (ub, zb0), (ub, zb1), (ua, za1)] {
                verts.append(v3(A + dir * u, z)); norms.append(SCNVector3(CGFloat(n.x), 0, CGFloat(-n.y))); uvs.append(CGPoint(x: u, y: -z))
            }
            idx += [base, base + 1, base + 2, base, base + 2, base + 3]
        }
        for i in 0..<(us.count - 1) {
            let ua = us[i], ub = us[i + 1], mid = (ua + ub) / 2
            let za = topAt(ua), zbT = topAt(ub)
            var cur = zb
            for h in holes.filter({ $0.u0 < mid && $0.u1 > mid }).sorted(by: { $0.z0 < $1.z0 }) {
                let z1 = min(h.z0, min(za, zbT))
                if z1 > cur + 1e-4 { quad(ua, ub, cur, cur, z1, z1) }
                cur = max(cur, h.z1)
            }
            if max(za, zbT) > cur + 1e-4 { quad(ua, ub, cur, cur, max(za, cur), max(zbT, cur)) }
        }
        guard !verts.isEmpty else { return nil }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: norms), SCNGeometrySource(textureCoordinates: uvs)],
                            elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        g.materials = [m]
        return SCNNode(geometry: g)
    }

    /// Проёмы наружных стен в плане: отрезок по оси стены и высоты
    static func worldHoles(_ F: Framing) -> [(a: V2, b: V2, z0: Double, z1: Double)] {
        F.walls.filter(\.exterior).flatMap { w in
            w.openings.map { o in (w.a + w.dir * o.u0, w.a + w.dir * o.u1, w.z0 + o.z0, w.z0 + o.z1) }
        }
    }

    /// Обход наружного контура, сдвинутого на off наружу (off < 0 — внутрь): для каждой стороны —
    /// начало, направление, длина, верх (с фронтоном) и проёмы
    static func outerEdges(_ p: Project, _ F: Framing, off: Double, zt: Double, gables: Bool,
                           _ body: (_ A: V2, _ dir: V2, _ L: Double, _ top: [(u: Double, z: Double)], _ holes: [Hole]) -> Void) {
        let model = RoofModel.of(p)
        let hR = F.rafter?.sec.wm ?? 0.2
        let cosA = 1 / (1 + model.tanA * model.tanA).squareRoot()
        let wh = worldHoles(F)
        for (ri, ring) in p.rings.enumerated() where ring.count > 2 {
            let R = Geo.offset(ring, by: (ri == 0 ? 1 : -1) * off)
            for i in ring.indices {
                let o0 = ring[i], o1 = ring[(i + 1) % ring.count]
                let A = R[i], B = R[(i + 1) % ring.count]
                let L = (B - A).len
                guard L > 0.05 else { continue }
                let dir = (B - A) / L
                var top: [(u: Double, z: Double)] = [(0, zt), (L, zt)]
                if gables && p.roofType != .flat {
                    let prof = model.profile(o0, o1)
                    if !prof.isEmpty {
                        let shift = dot2(o0 - A, dir)
                        top = prof.map { (u: $0.u + shift, z: F.rafterBase + $0.h - model.lift + F.studExt.wm / 2 * model.tanA + hR / cosA) }
                        if top[0].u > 0 { top.insert((0, top[0].z), at: 0) }
                        if top.last!.u < L { top.append((L, top.last!.z)) }
                    }
                }
                let holes: [Hole] = wh.filter { Geo.distToSegment($0.a, o0, o1) < 0.05 && Geo.distToSegment($0.b, o0, o1) < 0.05 }.map { h in
                    let u0 = dot2(h.a - A, dir), u1 = dot2(h.b - A, dir)
                    return (min(u0, u1), max(u0, u1), h.z0, h.z1)
                }
                body(A, dir, L, top, holes)
            }
        }
    }

    /// Сплошной слой по наружному контуру (ОСП фронтонов, мембрана, фасад, слои изнутри)
    static func ringSheets(_ p: Project, _ F: Framing, off: Double, zb: Double, zt: Double, gables: Bool, _ m: SCNMaterial, _ root: SCNNode) {
        let g = SCNNode()
        outerEdges(p, F, off: off, zt: zt, gables: gables) { A, dir, L, top, holes in
            if let n = vSheet(A, dir, L, zb: zb, top: top, holes: holes, m) { g.addChildNode(n) }
        }
        root.addChildNode(g.flattenedClone())
    }

    /// Вертикальные рейки по контуру (контррейки фасада) с обходом проёмов
    static func ringBattens(_ p: Project, _ F: Framing, off: Double, zb: Double, step: Double, _ m: SCNMaterial, _ root: SCNNode) {
        let g = SCNNode()
        outerEdges(p, F, off: off, zt: F.wallTop, gables: true) { A, dir, L, top, holes in
            let n = V2(-dir.y, dir.x)
            var u = 0.025
            while u < L - 0.02 {
                let zTop = top.last(where: { $0.u <= u })?.z ?? F.wallTop
                var cur = zb
                for h in holes.filter({ $0.u0 - 0.03 < u && $0.u1 + 0.03 > u }).sorted(by: { $0.z0 < $1.z0 }) {
                    if h.z0 > cur + 0.05 { g.addChildNode(beam(A + dir * u - n * 0.0001, A + dir * u, width: 0.05, bottom: cur, top: h.z0, extend: 0.0125, m)) }
                    cur = max(cur, h.z1)
                }
                if zTop > cur + 0.05 { g.addChildNode(beam(A + dir * (u - 0.025), A + dir * (u + 0.025), width: 0.025, bottom: cur, top: zTop - 0.05, extend: 0, m)) }
                u += step
            }
        }
        root.addChildNode(g.flattenedClone())
    }

    /// Контур внутренней грани наружных стен
    static func innerRings(_ p: Project, _ F: Framing, inset: Double) -> [[V2]] {
        p.rings.enumerated().map { i, r in Geo.offset(r, by: (i == 0 ? -1 : 1) * inset) }
    }

    /// Поверхность ската по модели кровли: z(v) задаётся снаружи (верх стропил, контробрешётки и т. п.)
    static func roofMesh(_ model: RoofModel, rings: [[V2]], z: (V2) -> Double, _ m: SCNMaterial) -> SCNNode {
        let cosA = 1 / (1 + model.tanA * model.tanA).squareRoot()
        let (lo, hi) = Geo.bbox(rings)
        let g = max(0.1, (Geo.area(rings) / 9000).squareRoot())
        func axis(_ a: Double, _ b: Double, _ extra: [Double]) -> [Double] {
            var v = Array(stride(from: a, through: b, by: g)) + extra + [b]
            v.sort()
            return v.reduce(into: [Double]()) { acc, x in if acc.isEmpty || x - acc.last! > 1e-4 { acc.append(x) } }
        }
        let xs = axis(lo.x, hi.x, rings.flatMap { $0.map(\.x) })
        let ys = axis(lo.y, hi.y, rings.flatMap { $0.map(\.y) })
        var hcache = [[Double]](repeating: [Double](repeating: 0, count: ys.count), count: xs.count)
        for i in xs.indices { for j in ys.indices { hcache[i][j] = z(V2(xs[i], ys[j])) } }
        var verts: [SCNVector3] = [], norms: [SCNVector3] = [], uvs: [CGPoint] = [], idx: [Int32] = []
        func tri(_ q: [V2], _ hz: [Double]) {
            let cen = (q[0] + q[1] + q[2]) / 3
            guard let face = model.depth(cen) else { return }
            let e = model.edges[face.edge]
            let ed = (e.b - e.a).unit
            let a3 = f3(q[0], hz[0]), b3 = f3(q[1], hz[1]), c3 = f3(q[2], hz[2])
            var n = simd_normalize(simd_cross(b3 - a3, c3 - a3))
            if n.y < 0 { n = -n }
            for (v, h) in zip(q, hz) {
                verts.append(SCNVector3(f3(v, h)))
                norms.append(SCNVector3(n))
                uvs.append(CGPoint(x: dot2(v - e.a, ed), y: dot2(v - e.a, e.n) / cosA))
                idx.append(Int32(idx.count))
            }
        }
        for i in 0..<(xs.count - 1) {
            for j in 0..<(ys.count - 1) {
                let c = V2((xs[i] + xs[i + 1]) / 2, (ys[j] + ys[j + 1]) / 2)
                guard Geo.contains(c, rings) else { continue }
                let v00 = V2(xs[i], ys[j]), v10 = V2(xs[i + 1], ys[j]), v11 = V2(xs[i + 1], ys[j + 1]), v01 = V2(xs[i], ys[j + 1])
                let h00 = hcache[i][j], h10 = hcache[i + 1][j], h11 = hcache[i + 1][j + 1], h01 = hcache[i][j + 1]
                let hc = z(c)
                if abs((h00 + h11) / 2 - hc) <= abs((h10 + h01) / 2 - hc) {
                    tri([v00, v10, v11], [h00, h10, h11]); tri([v00, v11, v01], [h00, h11, h01])
                } else {
                    tri([v00, v10, v01], [h00, h10, h01]); tri([v10, v11, v01], [h10, h11, h01])
                }
            }
        }
        let geo = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: norms), SCNGeometrySource(textureCoordinates: uvs)],
                              elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        geo.materials = [m]
        return SCNNode(geometry: geo)
    }

    static func roofCoverMat(_ p: Project, opacity: Double = 1) -> SCNMaterial {
        let t = Tex.tile(.roof(p.covering))
        let m = mat(.white, opacity)
        m.diffuse.contents = Tex.image(.roof(p.covering))
        m.diffuse.wrapS = .repeat; m.diffuse.wrapT = .repeat; m.diffuse.mipFilter = .linear
        m.diffuse.contentsTransform = SCNMatrix4MakeScale(CGFloat(1 / t.w), CGFloat(1 / t.h), 1)
        m.specular.contents = NSColor(white: 0.35, alpha: 1)
        return m
    }

    /// Ветровые и карнизные доски по краю ската
    static func fascia(_ rings: [[V2]], z: (V2) -> Double, depth: Double = 0.2, _ m: SCNMaterial) -> SCNNode {
        var tris: [(simd_float3, simd_float3, simd_float3)] = []
        for r in rings {
            for i in r.indices {
                let a = r[i], b = r[(i + 1) % r.count]
                let n = max(1, Int((b - a).len / 0.25))
                for k in 0..<n {
                    let p0 = a + (b - a) * (Double(k) / Double(n)), p1 = a + (b - a) * (Double(k + 1) / Double(n))
                    let t0 = z(p0) + 0.03, t1 = z(p1) + 0.03
                    tris += quad(f3(p0, t0 - depth), f3(p1, t1 - depth), f3(p1, t1), f3(p0, t0))
                }
            }
        }
        return mesh(tris, m)
    }

    // MARK: - Оболочка дома по этапам

    /// ОСП, мембраны, окна, фасад, утеплитель, пароизоляция, стяжка, внутренняя обшивка и кровельное покрытие —
    /// всё, что появляется после каркаса; shown — стены, которые уже стоят (на этапе подъёма)
    static func envelope(_ p: Project, _ F: Framing, _ stage: Stage3D, _ sub: Int, shown: Set<Int>, _ root: SCNNode) {
        guard stage >= .walls else { return }
        let D = F.studExt.wm
        let osbT = p.sheathing.hasOSB ? 0.009 : 0
        let interior = stage.isInterior
        let cur = { (st: Stage3D, k: Int) in stage > st || (stage == st && sub >= k) }

        // --- ОСП снаружи: на каждой поднятой наружной стене, по высоте — от низа обвязки/обвязочной доски перекрытия
        if p.sheathing.hasOSB && stage < .facade {
            let osb = mat(rgb(0.80, 0.68, 0.45), stage < .wrap ? 0.55 : 1)
            let g = SCNNode()
            for (i, w) in F.walls.enumerated() where w.exterior && shown.contains(i) {
                let zb = w.storey == 0 ? F.foundTop : F.levels[w.storey - 1] + F.wallHeights[w.storey - 1]
                let holes: [Hole] = w.openings.map { ($0.u0, $0.u1, w.z0 + $0.z0, w.z0 + $0.z1) }
                if let n = vSheet(w.a - w.inward * (D / 2 + 0.0045), w.dir, w.length, zb: zb, top: [(0, w.z0 + w.height), (w.length, w.z0 + w.height)], holes: holes, osb) {
                    g.addChildNode(n)
                }
            }
            root.addChildNode(g.flattenedClone())
            if cur(.roof, RoofSeq.gable) { ringSheets(p, F, off: D / 2 + 0.0045, zb: F.wallTop, zt: F.wallTop, gables: true, osb, root) }
        }

        // --- кровельное покрытие
        if stage >= .cover {
            if p.roofType == .flat {
                buildRoof(p, wallTop: F.wallTop + (F.attic?.check.sec.wm ?? 0.2), root)
            } else if let rf = F.rafter {
                let o = p.overhang
                let model = RoofModel.of(p, overhang: o)
                let rings = p.rings.enumerated().map { i, r in Geo.offset(r, by: i == 0 ? o : -o) }
                let cosA = 1 / (1 + model.tanA * model.tanA).squareRoot()
                let lift = (rf.sec.wm + F.counterSec.wm + F.battenSec.tm) / cosA + 0.01
                let z = { (v: V2) in F.rafterBase + ((model.depth(v)?.d ?? 0) - (o - D / 2)) * model.tanA + lift }
                let op = interior ? 0.15 : 1
                root.addChildNode(roofMesh(model, rings: rings, z: z, roofCoverMat(p, opacity: op)))
                // лобовая доска закрывает торцы стропил и обрешётки
                root.addChildNode(fascia(rings, z: z, depth: lift + 0.06, mat(RGBColor.darken(p.covering.nsColor, 0.6), op)))
            }
        }
        // мембрана по стропилам (этап обрешётки)
        if stage == .battens, let rf = F.rafter {
            let o = p.overhang
            let model = RoofModel.of(p, overhang: o)
            let rings = p.rings.enumerated().map { i, r in Geo.offset(r, by: i == 0 ? o - 0.05 : -(o - 0.05)) }
            let cosA = 1 / (1 + model.tanA * model.tanA).squareRoot()
            let z = { (v: V2) in F.rafterBase + ((model.depth(v)?.d ?? 0) - (o - D / 2)) * model.tanA + rf.sec.wm / cosA + 0.003 }
            root.addChildNode(roofMesh(model, rings: rings, z: z, mat(rgb(0.93, 0.95, 0.97), sub >= 2 ? 1 : 0.9)))
        }

        // --- окна и наружные двери
        if stage >= .windows {
            for w in F.walls where w.exterior {
                for (k, o) in w.openings.enumerated() where k < w.kinds.count {
                    let off = w.inward * (-(D / 2) + 0.07)
                    let a = w.a + w.dir * (o.u0 + 0.015) + off, b = w.a + w.dir * (o.u1 - 0.015) + off
                    opening(root, a, b, bottom: w.z0 + o.z0 + (w.kinds[k].isDoor ? 0 : 0.03), top: w.z0 + o.z1 - 0.015, wallT: D, kind: w.kinds[k], exterior: true)
                }
            }
        }

        // --- наружные слои: ветрозащита и фасад
        let outOp = interior ? 0.2 : 1
        if stage >= .wrap && stage < .facade || (stage == .facade && !interior) {
            if p.facade == .plaster {
                // лента по стыкам ОСП: вертикально через 1250 и по горизонтальному стыку
                let tape = mat(rgb(0.92, 0.93, 0.95))
                let g = SCNNode()
                outerEdges(p, F, off: D / 2 + osbT + 0.001, zt: F.wallTop, gables: false) { A, dir, L, _, _ in
                    var u = 0.0
                    while u <= L + 1e-6 { g.addChildNode(beam(A + dir * (u - 0.075), A + dir * (u + 0.075), width: 0.002, bottom: F.foundTop, top: F.wallTop, extend: 0, tape)); u += 1.25 }
                    g.addChildNode(beam(A, A + dir * L, width: 0.002, bottom: F.levelBase + 0.55, top: F.levelBase + 0.7, extend: 0, tape))
                }
                root.addChildNode(g.flattenedClone())
            } else {
                ringSheets(p, F, off: D / 2 + osbT + 0.001, zb: F.foundTop, zt: F.wallTop, gables: true, mat(rgb(0.93, 0.94, 0.96)), root)
            }
            // цокольный отлив
            let flash = mat(RGBColor.darken(p.covering.nsColor, 0.8))
            let g = SCNNode()
            outerEdges(p, F, off: D / 2 + osbT + 0.03, zt: F.wallTop, gables: false) { A, dir, L, _, _ in
                g.addChildNode(beam(A, A + dir * L, width: 0.06, bottom: F.foundTop - 0.01, top: F.foundTop + 0.005, extend: 0.03, flash))
            }
            root.addChildNode(g.flattenedClone())
        }
        if stage >= .facade {
            let fac = texMat(.facade(p.facade), uLen: 1, vLen: 1, opacity: outOp)
            switch p.facade {
            case .plaster:
                if cur(.facade, 1) {
                    ringSheets(p, F, off: D / 2 + osbT + 0.11, zb: F.foundTop, zt: F.wallTop, gables: true, fac, root)
                } else {
                    ringSheets(p, F, off: D / 2 + osbT + 0.1, zb: F.foundTop, zt: F.wallTop, gables: true, mat(rgb(0.86, 0.87, 0.62)), root)
                }
            case .facingBrick:
                let zt = cur(.facade, 1) ? F.wallTop : F.foundTop + (F.wallTop - F.foundTop) / 2
                ringSheets(p, F, off: D / 2 + osbT + 0.16, zb: F.foundTop - 0.3, zt: zt, gables: cur(.facade, 1), fac, root)
            default:
                if !interior { ringBattens(p, F, off: D / 2 + osbT + 0.0135, zb: F.foundTop, step: p.studStep, mat(rgb(0.70, 0.55, 0.36)), root) }
                if cur(.facade, 1) { ringSheets(p, F, off: D / 2 + osbT + 0.045, zb: F.foundTop + 0.02, zt: F.wallTop, gables: true, fac, root) }
            }
        }

        // --- изнутри: утеплитель, пароизоляция, обшивка
        let storeys = F.wallHeights.indices
        let wool = mat(rgb(0.96, 0.84, 0.42))
        let woolRoof = Thermal.woolThickness(Thermal.rRoof(p.climate.gsop))
        let inner = innerRings(p, F, inset: D / 2)
        let rf = F.rafter
        let o = p.overhang
        let model = RoofModel.of(p, overhang: o)
        let cosA = 1 / (1 + model.tanA * model.tanA).squareRoot()
        func underRafters(_ dz: Double) -> (V2) -> Double {
            { v in F.rafterBase + ((model.depth(v)?.d ?? 0) - (o - D / 2)) * model.tanA + dz }
        }
        func partitions(_ off: (WallFrame) -> Double, _ m: SCNMaterial) {
            let g = SCNNode()
            for w in F.walls where !w.exterior {
                let holes: [Hole] = w.openings.map { ($0.u0, $0.u1, w.z0 + $0.z0, w.z0 + $0.z1) }
                for sg in [-1.0, 1.0] {
                    if let n = vSheet(w.a + w.inward * (sg * off(w)), w.dir, w.length, zb: w.z0, top: [(0, w.z0 + w.height), (w.length, w.z0 + w.height)], holes: holes, m) { g.addChildNode(n) }
                }
            }
            root.addChildNode(g.flattenedClone())
        }
        if stage >= .insul && stage < .lining || (stage == .lining && sub < 1) {
            for k in storeys { ringSheets(p, F, off: -(D / 2 - 0.004), zb: F.levels[k], zt: F.levels[k] + F.wallHeights[k], gables: false, wool, root) }
            partitions({ $0.depth / 2 - 0.004 }, wool)
            if cur(.insul, 1) && p.roofType != .flat {
                // на своём шаге утеплитель кровли виден, дальше — почти прозрачный, чтобы смотреть внутрь
                let op = stage == .insul ? 0.8 : 0.12
                if p.roofInsulated, let rf {
                    root.addChildNode(roofMesh(model, rings: inner, z: underRafters(rf.sec.wm / 2 / cosA), mat(rgb(0.96, 0.84, 0.42), op)))
                } else {
                    root.addChildNode(extrude(inner, bottom: F.wallTop, top: F.wallTop + woolRoof, mat(rgb(0.96, 0.84, 0.42), op)))
                }
            }
        }
        if stage >= .vapor && (stage < .lining || sub < 1) {
            let vap = mat(rgb(0.62, 0.78, 0.95), 0.85)
            for k in storeys { ringSheets(p, F, off: -(D / 2 + 0.001), zb: F.levels[k], zt: F.levels[k] + F.wallHeights[k], gables: false, vap, root) }
            if stage == .vapor {
                let ceil = mat(rgb(0.62, 0.78, 0.95), 0.5)
                if p.roofInsulated && p.roofType != .flat { root.addChildNode(roofMesh(model, rings: inner, z: underRafters(-0.003), ceil)) }
                else { root.addChildNode(extrude(inner, bottom: F.wallTop - 0.002, top: F.wallTop, ceil)) }
            }
        }
        if stage >= .lining {
            let t = p.interiorFinish.t
            let fin: SCNMaterial
            switch p.interiorFinish {
            case .gkl: fin = mat(rgb(0.94, 0.94, 0.92))
            case .boards: fin = texMat(.wood, uLen: 1, vLen: 1)
            case .osb: fin = mat(rgb(0.84, 0.72, 0.50))
            }
            let ceil = fin.copy() as! SCNMaterial
            ceil.transparency = sub >= 1 ? 0.15 : 0.6; ceil.blendMode = .alpha; ceil.writesToDepthBuffer = false
            let ceilIn = innerRings(p, F, inset: D / 2 + 0.025)
            for k in storeys {
                let z = F.levels[k] + F.wallHeights[k] - 0.025
                if k == storeys.last && p.roofInsulated && p.roofType != .flat {
                    root.addChildNode(roofMesh(model, rings: ceilIn, z: underRafters(-0.03), ceil))
                } else {
                    root.addChildNode(extrude(ceilIn, bottom: z - t, top: z, ceil))
                }
            }
            if sub >= 1 {
                for k in storeys { ringSheets(p, F, off: -(D / 2 + 0.025 + t / 2), zb: F.levels[k], zt: F.levels[k] + F.wallHeights[k] - 0.025, gables: false, fin, root) }
                partitions({ $0.depth / 2 + t / 2 }, fin)
            }
        }

        // --- основание пола
        if stage >= .screed {
            let steps = Steps3D.screedSteps(p)
            let st = stage == .screed ? (sub < steps.count ? steps[sub] : steps.last) : steps.last
            if let st {
                let layers = Array(Steps3D.screedLayers(p).prefix(st.layers))
                let all = Steps3D.screedLayers(p).reduce(0) { $0 + $1.t }
                var z: Double
                switch p.floorBase {
                case .joists: z = F.levelBase
                case .slab: z = F.foundTop
                case .ground: z = F.foundTop - all
                }
                let rings = innerRings(p, F, inset: D / 2 + 0.01)
                for l in layers {
                    let c: NSColor
                    if let f = l.fill { c = f } else {
                        switch l.h {
                        case .insulation: c = rgb(0.75, 0.88, 1.0)
                        case .board: c = rgb(0.82, 0.70, 0.48)
                        case .concrete: c = rgb(0.70, 0.70, 0.68)
                        default: c = rgb(0.80, 0.80, 0.78)
                        }
                    }
                    root.addChildNode(extrude(rings, bottom: z, top: z + max(l.t, 0.003), mat(c)))
                    z += l.t
                }
                if stage == .screed && sub < steps.count && steps[sub].pipes && !steps[sub].title.hasPrefix("Пол") {
                    // трубы тёплого пола змейкой поверх утеплителя
                    let pipe = mat(rgb(0.85, 0.20, 0.15))
                    let g = SCNNode()
                    let (lo, hi) = Geo.bbox(rings)
                    var y = lo.y + 0.15
                    while y < hi.y - 0.1 {
                        for (x0, x1) in Geo.scan(rings, at: y, horizontal: true) where x1 - x0 > 0.4 {
                            g.addChildNode(beam(V2(x0 + 0.15, y), V2(x1 - 0.15, y), width: 0.018, bottom: z, top: z + 0.018, extend: 0, pipe))
                        }
                        y += 0.2
                    }
                    root.addChildNode(g.flattenedClone())
                }
            }
        }
    }
}
