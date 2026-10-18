import SceneKit
import AppKit
import simd

/// Участок (забор, газон, деревья, парковка, дорожка, терраса) и отмостка с дренажом
extension SceneBuilder {
    /// Габарит участка вокруг дома
    static func plot(_ p: Project) -> (lo: V2, hi: V2) {
        let (lo, hi) = Geo.bbox(p.rings)
        return (V2(lo.x - 5, lo.y - 9), V2(hi.x + 5, hi.y + 10))
    }

    // MARK: - Отмостка и дренаж

    static func buildDrainage(_ p: Project, _ d: DrainagePlan, wallTop: Double, _ root: SCNNode) {
        guard !d.blindRings.isEmpty else { return }
        let (blo, bhi) = Geo.bbox([d.blindRings[0]])
        root.addChildNode(extrude(d.blindRings, bottom: -0.02, top: 0.06, texMat(.paving, uLen: bhi.x - blo.x, vLen: bhi.y - blo.y)))
        // бордюр
        let curb = mat(rgb(0.45, 0.45, 0.44))
        let outer = d.blindRings[0]
        for i in outer.indices {
            root.addChildNode(beam(outer[i], outer[(i + 1) % outer.count], width: 0.08, bottom: -0.05, top: 0.1, extend: 0.04, curb))
        }
        // дренаж: щебень в геотекстиле + труба
        let gravel = texMat(.gravel, uLen: 2, vLen: 0.4, opacity: 0.55)
        let pipe = mat(rgb(0.15, 0.15, 0.16))
        let ring = d.drainRing
        var path = ring + [ring[0]]
        if let c0 = ring.min(by: { ($0 - d.collector).len < ($1 - d.collector).len }) { path += [c0, d.collector] }
        let y = -d.drainDepth
        for i in 0..<(path.count - 1) where (path[i + 1] - path[i]).len > 0.01 {
            let a = path[i], b = path[i + 1]
            root.addChildNode(beam(a, b, width: 0.4, bottom: y - 0.1, top: y + 0.3, extend: 0.2, gravel))
            root.addChildNode(rod(f3(a, y + 0.06), f3(b, y + 0.06), radius: 0.055, pipe))
        }
        // колодцы
        let wellMat = mat(rgb(0.25, 0.32, 0.25))
        let lidMat = mat(rgb(0.12, 0.16, 0.12))
        for w in d.wells {
            root.addChildNode(rod(f3(w, y - 0.3), f3(w, 0.05), radius: 0.16, wellMat))
            root.addChildNode(rod(f3(w, 0.05), f3(w, 0.08), radius: 0.19, lidMat))
        }
        root.addChildNode(rod(f3(d.collector, -d.drainDepthEnd - 0.8), f3(d.collector, 0.05), radius: 0.5, mat(rgb(0.55, 0.55, 0.53))))
        root.addChildNode(rod(f3(d.collector, 0.05), f3(d.collector, 0.1), radius: 0.56, lidMat))
        // водостоки с дождеприёмниками
        let gutter = mat(rgb(0.30, 0.31, 0.33), metal: true)
        for dp in d.downpipes {
            root.addChildNode(rod(f3(dp, 0.25), f3(dp, wallTop + 0.1), radius: 0.05, gutter))
            root.addChildNode(beam(dp - V2(0.15, 0), dp + V2(0.15, 0), width: 0.3, bottom: 0.0, top: 0.08, extend: 0, mat(rgb(0.2, 0.2, 0.2))))
        }
    }

    // MARK: - Участок

    static func buildSite(_ p: Project, _ d: DrainagePlan, _ root: SCNNode) {
        let (lo, hi) = Geo.bbox(p.rings)
        let (plo, phi) = plot(p)
        let ctr = (lo + hi) / 2

        // Входная дверь: наружная дверь, ближайшая к фасаду (наименьший y)
        var doorPt = V2(ctr.x, lo.y)
        let ops = p.validOpenings
        let ext = ops.compactMap { o -> V2? in
            guard o.kind.isDoor, case .edge = o.host, let c = p.openingCenter(o) else { return nil }
            return c
        }
        if let dp = ext.min(by: { $0.y < $1.y }) { doorPt = dp }
        let pathX = min(max(doorPt.x, plo.x + 1.5), phi.x - 1.5)
        let parkLeft = pathX > ctr.x
        let parkX0 = parkLeft ? max(plo.x + 1.0, lo.x - 1.5) : min(phi.x - 4.6, hi.x - 2.1)
        let parkX1 = parkX0 + 3.6

        // Забор: столбы через 2.5 м, доска «ранчо», ворота у парковки и калитка у дорожки
        let post = mat(rgb(0.22, 0.22, 0.23))
        let fence = texMat(.facade(.imitationTimber), uLen: 2.5, vLen: 1.8)
        let corners = [plo, V2(phi.x, plo.y), phi, V2(plo.x, phi.y)]
        let gates: [(Double, Double)] = [(parkX0 - 0.2, parkX1 + 0.2), (pathX - 0.6, pathX + 0.6)]
        for i in 0..<4 {
            let a = corners[i], b = corners[(i + 1) % 4]
            let len = (b - a).len, dir = (b - a) / len
            let n = Int((len / 2.5).rounded(.up))
            for k in 0..<n {
                let u0 = len * Double(k) / Double(n), u1 = len * Double(k + 1) / Double(n)
                let pa = a + dir * u0, pb = a + dir * u1
                root.addChildNode(beam(pa, pa, width: 0.08, bottom: 0, top: 2.0, extend: 0.04, post))
                if i == 0 {
                    // фасадная сторона: пропуски под ворота и калитку
                    var segs: [(Double, Double)] = [(pa.x, pb.x)]
                    for g in gates {
                        segs = segs.flatMap { s -> [(Double, Double)] in
                            if g.1 <= s.0 || g.0 >= s.1 { return [s] }
                            return [(s.0, g.0), (g.1, s.1)].filter { $0.1 - $0.0 > 0.05 }
                        }
                    }
                    for s in segs { root.addChildNode(beam(V2(s.0, a.y), V2(s.1, a.y), width: 0.04, bottom: 0.1, top: 1.8, extend: 0, fence)) }
                } else {
                    root.addChildNode(beam(pa, pb, width: 0.04, bottom: 0.1, top: 1.8, extend: 0, fence))
                }
            }
        }
        // откатные ворота и калитка — приоткрыты
        let gateMat = mat(rgb(0.25, 0.25, 0.27), metal: true)
        root.addChildNode(beam(V2(parkX1 + 0.3, plo.y - 0.12), V2(parkX1 + 3.8, plo.y - 0.12), width: 0.05, bottom: 0.1, top: 1.8, extend: 0, gateMat))

        // Парковка с машиной
        let park0 = V2(parkX0, plo.y + 0.2), park1 = V2(parkX1, min(lo.y - d.width - d.faceOffset - 0.5, plo.y + 6.5))
        root.addChildNode(extrude([[park0, V2(park1.x, park0.y), park1, V2(park0.x, park1.y)]], bottom: 0, top: 0.05,
                                  texMat(.paving, uLen: park1.x - park0.x, vLen: park1.y - park0.y)))
        car(V2((parkX0 + parkX1) / 2, (park0.y + park1.y) / 2), root)

        // Дорожка от калитки к входу
        let pathEndY = doorPt.y - d.faceOffset - (doorPt.y <= lo.y + 0.01 ? d.width : 0)
        if pathEndY > plo.y + 0.5 {
            root.addChildNode(extrude([[V2(pathX - 0.6, plo.y + 0.1), V2(pathX + 0.6, plo.y + 0.1), V2(pathX + 0.6, pathEndY), V2(pathX - 0.6, pathEndY)]],
                                      bottom: 0, top: 0.05, texMat(.paving, uLen: 1.2, vLen: pathEndY - plo.y)))
        }

        // Терраса у самого широкого наружного портала
        if let big = ops.filter({ $0.kind == .glassDoor && $0.width >= 1.6 }).filter({ if case .edge = $0.host { return true }; return false })
            .max(by: { $0.width < $1.width }), let l = p.hostLine(big.host), let c = p.openingCenter(big) {
            let dir = (l.b - l.a).unit
            var nOut = V2(dir.y, -dir.x)
            if Geo.contains(c + nOut * 0.5, p.rings) { nOut = -nOut }
            let depth = 3.0, half = big.width / 2 + 1.2
            let base = c + nOut * (d.faceOffset + 0.05)
            let q = [base - dir * half, base + dir * half, base + dir * half + nOut * depth, base - dir * half + nOut * depth]
            root.addChildNode(extrude([q], bottom: 0.0, top: 0.18, texMat(.deck, uLen: half * 2, vLen: depth)))
        }

        // Деревья и кусты (детерминированно)
        var seed: UInt64 = 42
        func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double((seed >> 33) & 0xFFFF) / 65535 }
        var spots: [V2] = []
        let backY0 = hi.y + 3.5, backY1 = phi.y - 1.5
        var x = plo.x + 1.8
        while x < phi.x - 1.5 {
            spots.append(V2(x + rnd() * 1.2, backY0 + rnd() * max(0, backY1 - backY0)))
            x += 3.6 + rnd() * 1.5
        }
        for side in [plo.x + 1.5, phi.x - 1.5] {
            var yy = lo.y + 1
            while yy < hi.y + 1 { spots.append(V2(side + (rnd() - 0.5) * 0.8, yy)); yy += 4.5 + rnd() * 2 }
        }
        for (k, s) in spots.enumerated() {
            if s.x > parkX0 - 1.5 && s.x < parkX1 + 1.5 && s.y < lo.y { continue }
            if (s - d.collector).len < 1.5 { continue }
            if k % 3 == 1 { conifer(s, 3.5 + rnd() * 2.5, root) } else { tree(s, 3.5 + rnd() * 2, root) }
        }
        let bushMat = mat(rgb(0.24, 0.45, 0.20))
        var bx = plo.x + 0.8
        while bx < phi.x - 0.8 {
            if !(bx > parkX0 - 0.6 && bx < parkX1 + 0.6) && abs(bx - pathX) > 1.2 {
                let s = SCNSphere(radius: CGFloat(0.35 + rnd() * 0.2)); s.materials = [bushMat]
                let n = SCNNode(geometry: s); n.position = v3(V2(bx, plo.y + 0.7), 0.3); n.scale = SCNVector3(1, 0.8, 1)
                root.addChildNode(n)
            }
            bx += 1.1
        }
        // Грядки
        let bedMat = texMat(.deck, uLen: 3, vLen: 0.3)
        let soilMat = mat(rgb(0.30, 0.21, 0.14))
        for k in 0..<2 {
            let x0 = phi.x - 4.5 + Double(k) * 1.7, y0 = phi.y - 4.8
            root.addChildNode(extrude([[V2(x0, y0), V2(x0 + 1.2, y0), V2(x0 + 1.2, y0 + 3), V2(x0, y0 + 3)]], bottom: 0, top: 0.3, bedMat))
            root.addChildNode(extrude([[V2(x0 + 0.05, y0 + 0.05), V2(x0 + 1.15, y0 + 0.05), V2(x0 + 1.15, y0 + 2.95), V2(x0 + 0.05, y0 + 2.95)]], bottom: 0.3, top: 0.32, soilMat))
        }
    }

    static func tree(_ at: V2, _ h: Double, _ root: SCNNode) {
        root.addChildNode(rod(f3(at, 0), f3(at, h * 0.55), radius: 0.12, mat(rgb(0.40, 0.28, 0.18))))
        let leaf = mat(rgb(0.30, 0.52, 0.22))
        for (dx, dy, dz, r) in [(0.0, 0.75, 0.0, 0.32), (0.25, 0.62, 0.15, 0.25), (-0.22, 0.6, -0.18, 0.24)] {
            let s = SCNSphere(radius: CGFloat(h * r)); s.materials = [leaf]
            let n = SCNNode(geometry: s)
            n.position = v3(at + V2(dx * h * 0.5, dz * h * 0.5), h * dy)
            root.addChildNode(n)
        }
    }

    static func conifer(_ at: V2, _ h: Double, _ root: SCNNode) {
        root.addChildNode(rod(f3(at, 0), f3(at, h * 0.25), radius: 0.1, mat(rgb(0.36, 0.25, 0.16))))
        let needle = mat(rgb(0.16, 0.36, 0.22))
        for (i, k) in [0.0, 0.3, 0.55].enumerated() {
            let c = SCNCone(topRadius: 0, bottomRadius: CGFloat(h * (0.28 - Double(i) * 0.06)), height: CGFloat(h * 0.5))
            c.materials = [needle]
            let n = SCNNode(geometry: c)
            n.position = v3(at, h * (0.25 + k) + h * 0.25)
            root.addChildNode(n)
        }
    }

    static func car(_ at: V2, _ root: SCNNode) {
        let paint = mat(rgb(0.16, 0.30, 0.52), metal: true)
        let glass = mat(rgb(0.15, 0.18, 0.22), metal: true)
        let a = at - V2(0, 2.2), b = at + V2(0, 2.2)
        root.addChildNode(beam(a, b, width: 1.8, bottom: 0.3, top: 0.85, extend: 0, paint))
        root.addChildNode(beam(at - V2(0, 1.1), at + V2(0, 1.0), width: 1.6, bottom: 0.85, top: 1.38, extend: 0, glass))
        let tire = mat(rgb(0.08, 0.08, 0.08))
        for dy in [-1.4, 1.4] {
            for dx in [-0.92, 0.92] {
                let c = at + V2(dx, dy)
                root.addChildNode(rod(f3(c - V2(0.12, 0), 0.32), f3(c + V2(0.12, 0), 0.32), radius: 0.32, tire))
            }
        }
    }
}
