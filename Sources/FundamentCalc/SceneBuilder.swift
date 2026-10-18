import SceneKit
import AppKit
import simd

struct SceneOptions: Hashable {
    var walls = true
    var wallOpacity = 1.0
    var roof = true
    var ground = true
    var rebar = false
    var foundation = true
    var drainage = true
    var site = true
    var stage: Stage3D = .finish
}

enum RGBColor {
    static func darken(_ c: NSColor, _ k: CGFloat) -> NSColor {
        let c = c.usingColorSpace(.sRGB) ?? c
        return NSColor(srgbRed: c.redComponent * k, green: c.greenComponent * k, blue: c.blueComponent * k, alpha: 1)
    }
}

enum SceneBuilder {
    // План (x, y) → сцена (x, высота, −y)
    static func v3(_ p: V2, _ h: Double) -> SCNVector3 { SCNVector3(CGFloat(p.x), CGFloat(h), CGFloat(-p.y)) }
    static func f3(_ p: V2, _ h: Double) -> simd_float3 { simd_float3(Float(p.x), Float(h), Float(-p.y)) }

    static func mat(_ c: NSColor, _ opacity: Double = 1, metal: Bool = false) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = c
        m.isDoubleSided = true
        m.lightingModel = .blinn
        if metal { m.specular.contents = NSColor(white: 0.8, alpha: 1); m.shininess = 0.6 }
        if opacity < 0.999 {
            m.transparency = CGFloat(opacity)
            m.blendMode = .alpha
            m.writesToDepthBuffer = false
        }
        return m
    }

    /// Брус вдоль отрезка a→b
    static func beam(_ a: V2, _ b: V2, width: Double, bottom: Double, top: Double, extend: Double, _ m: SCNMaterial) -> SCNNode {
        let d = b - a
        let g = SCNBox(width: CGFloat(d.len + 2 * extend), height: CGFloat(max(top - bottom, 0.001)), length: CGFloat(width), chamferRadius: 0)
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.position = v3((a + b) / 2, (top + bottom) / 2)
        n.eulerAngles = SCNVector3(0, CGFloat(atan2(d.y, d.x)), 0)
        return n
    }

    static func extrude(_ rings: [[V2]], bottom: Double, top: Double, _ m: SCNMaterial) -> SCNNode {
        let path = NSBezierPath()
        for r in rings where r.count > 2 {
            path.move(to: NSPoint(x: r[0].x, y: r[0].y))
            for v in r.dropFirst() { path.line(to: NSPoint(x: v.x, y: v.y)) }
            path.close()
        }
        path.windingRule = .evenOdd
        let shape = SCNShape(path: path, extrusionDepth: CGFloat(max(top - bottom, 0.001)))
        shape.materials = [m]
        let n = SCNNode(geometry: shape)
        n.eulerAngles = SCNVector3(-CGFloat.pi / 2, 0, 0)
        n.position = SCNVector3(0, CGFloat((top + bottom) / 2), 0)
        return n
    }

    static func mesh(_ tris: [(simd_float3, simd_float3, simd_float3)], _ m: SCNMaterial) -> SCNNode {
        var verts: [SCNVector3] = [], norms: [SCNVector3] = [], idx: [Int32] = []
        for t in tris {
            let n = simd_normalize(simd_cross(t.1 - t.0, t.2 - t.0))
            for v in [t.0, t.1, t.2] {
                verts.append(SCNVector3(v))
                norms.append(SCNVector3(n))
                idx.append(Int32(idx.count))
            }
        }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: norms)],
                            elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        g.materials = [m]
        return SCNNode(geometry: g)
    }

    static func quad(_ a: simd_float3, _ b: simd_float3, _ c: simd_float3, _ d: simd_float3) -> [(simd_float3, simd_float3, simd_float3)] {
        [(a, b, c), (a, c, d)]
    }

    static func rod(_ a: simd_float3, _ b: simd_float3, radius: Double, _ m: SCNMaterial) -> SCNNode {
        let v = b - a
        let l = simd_length(v)
        let g = SCNCylinder(radius: CGFloat(radius), height: CGFloat(max(l, 0.001)))
        g.radialSegmentCount = 8
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.simdPosition = (a + b) / 2
        if l > 1e-6 { n.simdOrientation = simd_quatf(from: simd_float3(0, 1, 0), to: v / l) }
        return n
    }

    // MARK: - Сборка сцены

    static func build(_ p: Project, _ r: CalcResults, _ o0: SceneOptions) -> SCNNode {
        var o = o0
        if o.stage == .foundation { o.rebar = true }
        let root = SCNNode()
        let kind = p.selectedFoundation
        let rings = p.rings
        let (lo, hi) = Geo.bbox(rings)
        let concrete = texMat(.concrete, uLen: 2, vLen: 1, opacity: o.rebar ? 0.28 : 1)
        let sand = texMat(.sand, uLen: 3, vLen: 0.5, opacity: o.rebar ? 0.3 : 1)
        let steel = mat(rgb(0.78, 0.32, 0.10), metal: true)
        let steelGray = mat(rgb(0.55, 0.57, 0.60), metal: true)

        let foundTop: Double
        switch kind {
        case .strip: foundTop = p.plinth
        case .slab: foundTop = SlabCalc.aboveGround
        case .piles: foundTop = 0.15 + r.piles.hg
        }

        if o.ground {
            let (plo, phi) = plot(p)
            let w = phi.x - plo.x + 14, h = phi.y - plo.y + 14
            let g = SCNBox(width: CGFloat(w), height: 0.02, length: CGFloat(h), chamferRadius: 0)
            g.materials = [texMat(.grass, uLen: w, vLen: h, opacity: o.foundation ? 0.6 : 1)]
            let n = SCNNode(geometry: g)
            n.position = v3((plo + phi) / 2, -0.01)
            n.renderingOrder = 10
            root.addChildNode(n)
        }

        let staged = o.stage < .finish
        if o.stage == .site { buildLayout(p, r, root) }
        if o.foundation && o.stage >= .foundation {
            let rebarGroup = SCNNode()
            switch kind {
            case .strip: buildStrip(p, r.strip, concrete, sand, steel, rebarGroup, root, o.rebar)
            case .slab: buildSlab(p, r.slab, concrete, sand, steel, rebarGroup, root, o.rebar)
            case .piles: buildPiles(p, r.piles, concrete, steel, steelGray, rebarGroup, root, o.rebar)
            }
            if o.rebar { root.addChildNode(rebarGroup.flattenedClone()) }
        }
        if staged {
            if o.stage >= .floor { buildFrame(p, r, o.stage, root) }
            return root
        }

        let H = Double(p.floors) * p.floorHeight
        let wallTop = foundTop + H
        frameMat = mat(p.darkFrames ? rgb(0.22, 0.23, 0.25) : rgb(0.96, 0.96, 0.95))
        if o.walls {
            let op = o.wallOpacity
            let ops = p.validOpenings
            let edges = p.edges
            for s in p.segments {
                let t = p.thickness(s.material)
                let e = edges[s.edge]
                let dir = (e.b - e.a).unit
                let start = dot2(s.a - e.a, dir)
                let holes = ops.filter { $0.host == .edge(s.edge) }.map { o in
                    (u0: o.pos - o.width / 2 - start, u1: o.pos + o.width / 2 - start, o: o)
                }.filter { $0.u1 > 0 && $0.u0 < s.length }
                let kind: TexKind = .facade(p.facade)
                wallPieces(root, s.a, s.b, t: t, extend: t / 2, base: foundTop, floors: p.floors, fh: p.floorHeight, holes: holes,
                           exteriorDoorsGroundOnly: true, tex: kind, uStart: start, opacity: op)
            }
            for pt in p.partitions where pt.length > 0.05 {
                let holes = ops.filter { $0.host == .partition(pt.id) }.map { (u0: $0.pos - $0.width / 2, u1: $0.pos + $0.width / 2, o: $0) }
                let kind: TexKind = .plaster
                wallPieces(root, pt.a, pt.b, t: pt.thickness, extend: 0, base: foundTop, floors: p.floors, fh: p.floorHeight, holes: holes,
                           exteriorDoorsGroundOnly: false, tex: kind, uStart: 0, opacity: op)
            }
            // Перекрытия между этажами
            let slabMat = mat(rgb(0.78, 0.76, 0.72), min(op, 0.85))
            for k in 1..<max(p.floors, 1) {
                let h = foundTop + Double(k) * p.floorHeight
                root.addChildNode(extrude(rings, bottom: h - 0.2, top: h, slabMat))
            }
            // Фронтоны
            if p.roofType == .gable || p.roofType == .shed {
                let roof = RoofModel.of(p)
                for s in p.segments {
                    let prof = roof.profile(s.a, s.b)
                    for node in frontons(s, prof, thickness: p.thickness(s.material), base: wallTop, tex: .facade(p.facade), opacity: op) {
                        root.addChildNode(node)
                    }
                }
            }
        }

        if o.roof { buildRoof(p, wallTop: wallTop, root) }
        if o.drainage || o.site {
            let dr = Drainage.make(p, r)
            if o.drainage { buildDrainage(p, dr, wallTop: wallTop, root) }
            if o.site { buildSite(p, dr, root) }
        }
        return root
    }

    // MARK: - Каркас по этапам

    static func buildFrame(_ p: Project, _ r: CalcResults, _ stage: Stage3D, _ root: SCNNode) {
        let F = FrameGen.make(p, r)
        var groups: [MemberKind: SCNNode] = [:]
        var mats: [MemberKind: SCNMaterial] = [:]
        for m in F.members {
            guard m.stage <= stage, !(m.onlyOwnStage && m.stage != stage) else { continue }
            let mat0: SCNMaterial
            if let mm = mats[m.kind] { mat0 = mm } else {
                let c = m.kind.rgb
                let mm = mat(rgb(c.0, c.1, c.2))
                mats[m.kind] = mm; mat0 = mm
            }
            let L = m.length
            guard L > 0.01 else { continue }
            let g = SCNBox(width: CGFloat(L), height: CGFloat(m.sec.wm), length: CGFloat(m.sec.tm), chamferRadius: 0)
            g.materials = [mat0]
            let n = SCNNode(geometry: g)
            func sv(_ v: V3) -> simd_float3 { simd_float3(Float(v.x), Float(v.z), Float(-v.y)) }
            let dir = simd_normalize(sv(m.b - m.a))
            var up = sv(m.up)
            up = simd_normalize(up - dir * simd_dot(up, dir))
            let side = simd_cross(dir, up)
            n.simdOrientation = simd_quatf(simd_float3x3(columns: (dir, up, side)))
            n.simdPosition = (sv(m.a) + sv(m.b)) / 2
            let grp = groups[m.kind] ?? SCNNode()
            grp.addChildNode(n)
            groups[m.kind] = grp
        }
        for (_, g) in groups { root.addChildNode(g.flattenedClone()) }
        // настилы перекрытий (ОСП) — полупрозрачные
        let osb = mat(rgb(0.80, 0.68, 0.45), 0.55)
        let woodFloor = p.selectedFoundation != .slab && p.groundFloor == .wood
        if woodFloor && stage >= .floor { root.addChildNode(extrude(p.rings, bottom: F.levelBase - 0.022, top: F.levelBase, osb)) }
        if stage >= .upper {
            for k in 1..<max(p.floors, 1) {
                let z = F.levelBase + Double(k) * p.floorHeight
                root.addChildNode(extrude(p.rings, bottom: z - 0.022, top: z, osb))
            }
        }
        // анкеры
        if stage == .floor {
            let steel = mat(rgb(0.6, 0.6, 0.62), metal: true)
            for a in F.anchors { root.addChildNode(rod(f3(a, F.foundTop - 0.1), f3(a, F.foundTop + (p.selectedFoundation == .slab ? 0.1 : F.sillSec.tm) + 0.03), radius: 0.008, steel)) }
        }
    }

    /// Обноска и шнуры (этап разбивки)
    static func buildLayout(_ p: Project, _ r: CalcResults, _ root: SCNNode) {
        let sc = Works.plan(p, r).scheme
        let wood = texMat(.wood, uLen: 1, vLen: 0.15)
        for post in sc.posts { root.addChildNode(beam(post - V2(0.025, 0), post + V2(0.025, 0), width: 0.05, bottom: 0, top: 0.8, extend: 0, wood)) }
        let ob = sc.obnoska
        for i in ob.indices { root.addChildNode(beam(ob[i], ob[(i + 1) % ob.count], width: 0.025, bottom: 0.62, top: 0.77, extend: 0.03, wood)) }
        let red = mat(rgb(0.9, 0.1, 0.1))
        for (a, b) in sc.strings { root.addChildNode(rod(f3(a, 0.78), f3(b, 0.78), radius: 0.004, red)) }
        let peg = mat(rgb(0.95, 0.6, 0.1))
        for pl in sc.piles { root.addChildNode(rod(f3(pl, 0), f3(pl, 0.3), radius: 0.015, peg)) }
    }

    // MARK: - Материалы с текстурой

    /// uLen, vLen — размеры грани в метрах, uOff/vOff — смещение (для стыковки рисунка соседних кусков)
    static func texMat(_ k: TexKind, uLen: Double, vLen: Double, uOff: Double = 0, vOff: Double = 0, opacity: Double = 1) -> SCNMaterial {
        let m = mat(.white, opacity)
        let t = Tex.tile(k)
        m.diffuse.contents = Tex.image(k)
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat
        m.diffuse.mipFilter = .linear
        m.diffuse.contentsTransform = SCNMatrix4Mult(SCNMatrix4MakeScale(CGFloat(uLen / t.w), CGFloat(vLen / t.h), 1),
                                                     SCNMatrix4MakeTranslation(CGFloat(uOff / t.w), CGFloat(vOff / t.h), 0))
        return m
    }

    /// Брус стены с текстурой на всех гранях (порядок граней SCNBox: +Z, +X, −Z, −X, +Y, −Y)
    static func texBeam(_ a: V2, _ b: V2, width: Double, bottom: Double, top: Double, extend: Double,
                        _ k: TexKind, uOff: Double, opacity: Double) -> SCNNode {
        let n = beam(a, b, width: width, bottom: bottom, top: top, extend: extend, mat(.white))
        let len = (b - a).len + 2 * extend, h = top - bottom
        let face = texMat(k, uLen: len, vLen: h, uOff: uOff - extend, vOff: -top, opacity: opacity)
        let end = texMat(k, uLen: width, vLen: h, vOff: -top, opacity: opacity)
        let cap = texMat(k, uLen: len, vLen: width, opacity: opacity)
        n.geometry?.materials = [face, end, face, end, cap, cap]
        return n
    }

    /// Стена из кусков вокруг проёмов, по этажам; окна и двери с рамами и стеклом
    static func wallPieces(_ root: SCNNode, _ a: V2, _ b: V2, t: Double, extend: Double, base: Double, floors: Int, fh: Double,
                           holes: [(u0: Double, u1: Double, o: Opening)], exteriorDoorsGroundOnly: Bool,
                           tex: TexKind, uStart: Double, opacity: Double) {
        let len = (b - a).len
        guard len > 1e-6 else { return }
        let dir = (b - a) / len
        func P(_ u: Double) -> V2 { a + dir * u }
        for k in 0..<max(floors, 1) {
            let z0 = base + Double(k) * fh, z1 = z0 + fh
            let hs = holes.filter { !(exteriorDoorsGroundOnly && $0.o.kind.isDoor && k > 0) }
                .map { (u0: max($0.u0, 0), u1: min($0.u1, len), o: $0.o) }
                .sorted { $0.u0 < $1.u0 }
            var cursor = -extend
            func piece(_ u0: Double, _ u1: Double, _ zb: Double, _ zt: Double) {
                guard u1 - u0 > 1e-4, zt - zb > 1e-4 else { return }
                root.addChildNode(texBeam(P(u0), P(u1), width: t, bottom: zb, top: zt, extend: 0, tex, uOff: uStart + u0, opacity: opacity))
            }
            for h in hs {
                piece(cursor, h.u0, z0, z1)
                let ob = z0 + h.o.sill, ot = min(z0 + h.o.sill + h.o.height, z1 - 0.05)
                piece(h.u0, h.u1, z0, ob)
                piece(h.u0, h.u1, ot, z1)
                opening(root, P(h.u0), P(h.u1), bottom: ob, top: ot, wallT: t, kind: h.o.kind, exterior: exteriorDoorsGroundOnly)
                cursor = max(cursor, h.u1)
            }
            piece(cursor, len + extend, z0, z1)
        }
    }

    static var frameMat = mat(rgb(0.96, 0.96, 0.95))
    static let glassMat: SCNMaterial = {
        let m = mat(rgb(0.55, 0.70, 0.85), 0.45)
        m.specular.contents = NSColor.white
        m.shininess = 0.9
        return m
    }()

    static func opening(_ root: SCNNode, _ a: V2, _ b: V2, bottom: Double, top: Double, wallT: Double, kind: OpeningKind, exterior: Bool) {
        let dir = (b - a).unit
        let w = (b - a).len
        let fw = 0.07, depth = min(0.09, wallT * 0.8)
        func post(_ u: Double, _ width: Double = 0.07) {
            let c = a + dir * u
            root.addChildNode(beam(c - dir * (width / 2), c + dir * (width / 2), width: depth, bottom: bottom, top: top, extend: 0, frameMat))
        }
        switch kind {
        case .window, .panoramic:
            post(fw / 2); post(w - fw / 2)
            root.addChildNode(beam(a, b, width: depth, bottom: bottom, top: bottom + fw, extend: 0, frameMat))
            root.addChildNode(beam(a, b, width: depth, bottom: top - fw, top: top, extend: 0, frameMat))
            // импосты: у окон в пол — через ~1.2 м, у обычных — по центру при ширине > 1 м
            let n = kind == .panoramic ? Int((w / 1.25).rounded(.up)) : (w > 1.0 ? 2 : 1)
            if n > 1 { for k in 1..<n { post(w * Double(k) / Double(n), 0.06) } }
            root.addChildNode(beam(a + dir * fw, b - dir * fw, width: 0.02, bottom: bottom + fw, top: top - fw, extend: 0, glassMat))
            if kind == .window {
                root.addChildNode(beam(a - dir * 0.03, b + dir * 0.03, width: wallT + 0.06, bottom: bottom - 0.03, top: bottom, extend: 0, frameMat))
            }
        case .door:
            let wood = texMat(.wood, uLen: w, vLen: top - bottom)
            let frame = mat(exterior ? rgb(0.30, 0.20, 0.13) : rgb(0.93, 0.92, 0.90))
            root.addChildNode(beam(a, a + dir * 0.06, width: depth, bottom: bottom, top: top, extend: 0, frame))
            root.addChildNode(beam(b - dir * 0.06, b, width: depth, bottom: bottom, top: top, extend: 0, frame))
            root.addChildNode(beam(a, b, width: depth, bottom: top - 0.06, top: top, extend: 0, frame))
            root.addChildNode(beam(a + dir * 0.06, b - dir * 0.06, width: 0.045, bottom: bottom, top: top - 0.06, extend: 0,
                                   exterior ? wood : mat(rgb(0.86, 0.80, 0.70))))
            let hp = b - dir * 0.15
            root.addChildNode(beam(hp, hp + dir * 0.12, width: 0.08, bottom: bottom + 0.95, top: bottom + 1.0, extend: 0, mat(rgb(0.75, 0.75, 0.72), metal: true)))
        case .glassDoor:
            // коробка + створки из стекла в тонкой раме; от 1.6 м — две створки (раздвижной портал)
            post(0.03, 0.06); post(w - 0.03, 0.06)
            root.addChildNode(beam(a, b, width: depth, bottom: top - 0.06, top: top, extend: 0, frameMat))
            let leaves = w >= 1.6 ? 2 : 1
            let lw = (w - 0.12) / Double(leaves)
            for k in 0..<leaves {
                let u0 = 0.06 + lw * Double(k), u1 = u0 + lw
                let off = V2(-dir.y, dir.x) * (leaves == 2 ? (k == 0 ? 0.02 : -0.02) : 0)
                let la = a + dir * u0 + off, lb = a + dir * u1 + off
                root.addChildNode(beam(la, la + dir * 0.05, width: 0.05, bottom: bottom, top: top - 0.06, extend: 0, frameMat))
                root.addChildNode(beam(lb - dir * 0.05, lb, width: 0.05, bottom: bottom, top: top - 0.06, extend: 0, frameMat))
                root.addChildNode(beam(la, lb, width: 0.05, bottom: bottom, top: bottom + 0.07, extend: 0, frameMat))
                root.addChildNode(beam(la, lb, width: 0.05, bottom: top - 0.12, top: top - 0.06, extend: 0, frameMat))
                root.addChildNode(beam(la + dir * 0.05, lb - dir * 0.05, width: 0.015, bottom: bottom + 0.07, top: top - 0.12, extend: 0, glassMat))
            }
            let hp = a + dir * (leaves == 2 ? w / 2 - 0.12 : w - 0.18)
            root.addChildNode(beam(hp, hp + dir * 0.03, width: 0.12, bottom: bottom + 0.8, top: bottom + 1.3, extend: 0, mat(rgb(0.7, 0.7, 0.7), metal: true)))
        }
    }

    static func frontons(_ s: WallSegment, _ prof: [(u: Double, h: Double)], thickness: Double, base: Double, tex: TexKind, opacity: Double) -> [SCNNode] {
        var out: [SCNNode] = []
        var run: [(u: Double, h: Double)] = []
        func flush() {
            defer { run = [] }
            guard run.count >= 2, RoofModel.area(run) > 0.01 else { return }
            // убираем точки на прямых участках: на почти коллинеарных точках триангуляция SCNShape ломается
            var pts: [(u: Double, h: Double)] = [run[0]]
            for i in 1..<(run.count - 1) {
                let a = pts.last!, b = run[i], c = run[i + 1]
                let cr = (b.u - a.u) * (c.h - a.h) - (b.h - a.h) * (c.u - a.u)
                if abs(cr) > 1e-4 { pts.append(b) }
            }
            pts.append(run.last!)
            let path = NSBezierPath()
            path.move(to: NSPoint(x: pts.first!.u, y: 0))
            for pt in pts { path.line(to: NSPoint(x: pt.u, y: pt.h)) }
            path.line(to: NSPoint(x: run.last!.u, y: 0))
            path.close()
            let shape = SCNShape(path: path, extrusionDepth: CGFloat(thickness))
            let w = run.last!.u - run.first!.u, h = run.map(\.h).max() ?? 1
            shape.materials = [texMat(tex, uLen: w, vLen: h, opacity: opacity)]
            let n = SCNNode(geometry: shape)
            let d = s.b - s.a
            n.position = v3(s.a, base)
            n.eulerAngles = SCNVector3(0, CGFloat(atan2(d.y, d.x)), 0)
            out.append(n)
        }
        // фронтон чуть ниже ската, чтобы не мерцал с кровлей
        for pt in prof.map({ (u: $0.u, h: max(0, $0.h - 0.05)) }) {
            if pt.h > 1e-3 { run.append(pt) } else { if !run.isEmpty { run.append(pt) }; flush() }
        }
        flush()
        return out
    }

    static func buildRoof(_ p: Project, wallTop: Double, _ root: SCNNode) {
        if p.roofType == .flat {
            let rings = p.rings.enumerated().map { i, r in Geo.offset(r, by: i == 0 ? 0.15 : -0.15) }
            root.addChildNode(extrude(rings, bottom: wallTop, top: wallTop + 0.3, mat(rgb(0.30, 0.31, 0.33))))
            // парапет
            let par = texMat(.concrete, uLen: 2, vLen: 0.5)
            for r in rings {
                for i in r.indices {
                    root.addChildNode(beam(r[i], r[(i + 1) % r.count], width: 0.12, bottom: wallTop + 0.3, top: wallTop + 0.75, extend: 0.06, par))
                }
            }
            return
        }
        // Поверхность кровли — сетка по контуру со свесом; высота из модели «прямого скелета»
        let o = p.overhang
        let model = RoofModel.of(p, overhang: o)
        let rings = p.rings.enumerated().map { i, r in Geo.offset(r, by: i == 0 ? o : -o) }
        let base = wallTop + model.lift - o * model.tanA
        func z(_ v: V2) -> Double { base + model.tanA * (model.depth(v)?.d ?? 0) }
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
        let t = Tex.tile(.roof(p.covering))
        let m = mat(.white)
        m.diffuse.contents = Tex.image(.roof(p.covering))
        m.diffuse.wrapS = .repeat; m.diffuse.wrapT = .repeat; m.diffuse.mipFilter = .linear
        m.diffuse.contentsTransform = SCNMatrix4MakeScale(CGFloat(1 / t.w), CGFloat(1 / t.h), 1)
        m.specular.contents = NSColor(white: 0.35, alpha: 1)
        geo.materials = [m]
        root.addChildNode(SCNNode(geometry: geo))

        // Ветровые и карнизные доски по краю кровли
        var fascia: [(simd_float3, simd_float3, simd_float3)] = []
        for r in rings {
            for i in r.indices {
                let a = r[i], b = r[(i + 1) % r.count]
                let n = max(1, Int((b - a).len / 0.25))
                for k in 0..<n {
                    let p0 = a + (b - a) * (Double(k) / Double(n)), p1 = a + (b - a) * (Double(k + 1) / Double(n))
                    let t0 = z(p0) + 0.03, t1 = z(p1) + 0.03
                    fascia += quad(f3(p0, t0 - 0.2), f3(p1, t1 - 0.2), f3(p1, t1), f3(p0, t0))
                }
            }
        }
        root.addChildNode(mesh(fascia, mat(RGBColor.darken(p.covering.nsColor, 0.6))))
    }

    static func buildStrip(_ p: Project, _ s: StripResult, _ concrete: SCNMaterial, _ sand: SCNMaterial, _ steel: SCNMaterial,
                           _ rebar: SCNNode, _ root: SCNNode, _ showRebar: Bool) {
        let d = s.depth, top = p.plinth
        for sl in s.lines {
            guard let sec = s.section(sl.line) else { continue }
            let a = sl.line.a, b = sl.line.b
            root.addChildNode(beam(a, b, width: sec.b + 0.4, bottom: -d - s.cushion, top: -d, extend: sec.b / 2 + 0.2, sand))
            if sec.isT {
                root.addChildNode(beam(a, b, width: sec.b, bottom: -d, top: -d + sec.soleH, extend: sec.b / 2, concrete))
                root.addChildNode(beam(a, b, width: sec.stemW, bottom: -d + sec.soleH, top: top, extend: sec.stemW / 2, concrete))
            } else {
                root.addChildNode(beam(a, b, width: sec.b, bottom: -d, top: top, extend: sec.b / 2, concrete))
            }
            guard showRebar else { continue }
            let dir = sl.line.dir, nrm = V2(-dir.y, dir.x)
            let c = sec.cover
            func layer(_ n: Int, _ dia: Int, _ w: Double, _ h: Double, ext: Double) {
                for i in 0..<n {
                    let off = n == 1 ? 0 : -w / 2 + c + Double(i) * (w - 2 * c) / Double(n - 1)
                    rebar.addChildNode(rod(f3(a + nrm * off - dir * ext, h), f3(b + nrm * off + dir * ext, h), radius: Double(dia) / 2000, steel))
                }
            }
            let yb = -d + c + Double(sec.botD) / 2000, yt = top - c - Double(sec.topD) / 2000
            layer(sec.botN, sec.botD, sec.b, yb, ext: sec.b / 2 - c)
            layer(sec.topN, sec.topD, sec.stemW, yt, ext: sec.stemW / 2 - c)
            if sec.sideRows > 0 {
                for k in 1...sec.sideRows {
                    let h = yb + (yt - yb) * Double(k) / Double(sec.sideRows + 1)
                    layer(2, sec.sideD, sec.stemW, h, ext: sec.stemW / 2 - c)
                }
            }
            // хомуты
            let hw = sec.stemW / 2 - c
            let cb = yb
            var u = 0.05
            let rr = Double(sec.clampD) / 2000
            while u < sl.line.length {
                let pt = a + dir * u
                let p1 = f3(pt - nrm * hw, cb), p2 = f3(pt + nrm * hw, cb), p3 = f3(pt + nrm * hw, yt), p4 = f3(pt - nrm * hw, yt)
                for (x, y) in [(p1, p2), (p2, p3), (p3, p4), (p4, p1)] { rebar.addChildNode(rod(x, y, radius: rr, steel)) }
                if sec.isT && sec.soleD > 0 {
                    // поперечные стержни подошвы — с их шагом, но не чаще хомутов
                    rebar.addChildNode(rod(f3(pt - nrm * (sec.b / 2 - c), yb - 0.012), f3(pt + nrm * (sec.b / 2 - c), yb - 0.012), radius: Double(sec.soleD) / 2000, steel))
                }
                u += sec.clampStep
            }
        }
    }

    static func buildSlab(_ p: Project, _ s: SlabResult, _ concrete: SCNMaterial, _ sand: SCNMaterial, _ steel: SCNMaterial,
                          _ rebar: SCNNode, _ root: SCNNode, _ showRebar: Bool) {
        guard !s.rings.isEmpty else { return }
        let top = 0.15, bot = 0.15 - s.t
        root.addChildNode(extrude(s.rings, bottom: bot, top: top, concrete))
        let cush = s.rings.enumerated().map { i, r in Geo.offset(r, by: i == 0 ? 0.3 : -0.3) }
        root.addChildNode(extrude(cush, bottom: bot - p.slabCushion, top: bot, sand))
        guard showRebar else { return }
        let rr = Double(s.d) / 2000
        for (a, b) in s.bars {
            for h in [bot + s.cover + rr, top - s.cover - rr] {
                rebar.addChildNode(rod(f3(a, h), f3(b, h), radius: rr, steel))
            }
        }
    }

    static func buildPiles(_ p: Project, _ s: PileResult, _ concrete: SCNMaterial, _ steel: SCNMaterial, _ steelGray: SCNMaterial,
                           _ rebar: SCNNode, _ root: SCNNode, _ showRebar: Bool) {
        let gb = 0.15, gt = 0.15 + s.hg
        for pl in s.lines {
            root.addChildNode(beam(pl.line.a, pl.line.b, width: s.bg, bottom: gb, top: gt, extend: s.bg / 2, concrete))
            if showRebar {
                let dir = pl.line.dir, nrm = V2(-dir.y, dir.x)
                let c = s.cover
                for (n, dia, h) in [(s.botN, s.botD, gb + c), (s.topN, s.topD, gt - c)] {
                    for i in 0..<n {
                        let off = -s.bg / 2 + c + Double(i) * (s.bg - 2 * c) / Double(max(n - 1, 1))
                        rebar.addChildNode(rod(f3(pl.line.a + nrm * off - dir * (s.bg / 2 - c), h), f3(pl.line.b + nrm * off + dir * (s.bg / 2 - c), h), radius: Double(dia) / 2000, steel))
                    }
                }
                var u = 0.05
                let hw = s.bg / 2 - c
                while u < pl.line.length {
                    let pt = pl.line.a + dir * u
                    let q = [f3(pt - nrm * hw, gb + c), f3(pt + nrm * hw, gb + c), f3(pt + nrm * hw, gt - c), f3(pt - nrm * hw, gt - c)]
                    for k in 0..<4 { rebar.addChildNode(rod(q[k], q[(k + 1) % 4], radius: Double(s.stirD) / 2000, steel)) }
                    u += s.stirStep
                }
            }
        }
        for pos in s.positions {
            switch s.type {
            case .bored, .boredEnlarged:
                root.addChildNode(rod(f3(pos, gb + 0.05), f3(pos, gb - s.L), radius: s.d / 2, concrete))
                if s.type == .boredEnlarged {
                    let sp = SCNSphere(radius: CGFloat(s.D / 2))
                    sp.materials = [concrete]
                    let n = SCNNode(geometry: sp)
                    n.position = v3(pos, gb - s.L + s.D * 0.25)
                    n.scale = SCNVector3(1, 0.6, 1)
                    root.addChildNode(n)
                }
                if showRebar {
                    for k in 0..<s.cageN {
                        let ang = Double(k) / Double(s.cageN) * 2 * .pi
                        let off = V2(cos(ang), sin(ang)) * (s.d / 2 - 0.05)
                        rebar.addChildNode(rod(f3(pos + off, gb + 0.3), f3(pos + off, gb - s.L + 0.05), radius: Double(s.cageD) / 2000, steel))
                    }
                }
            case .screw:
                root.addChildNode(rod(f3(pos, gb + 0.05), f3(pos, gb - s.L), radius: s.d / 2, steelGray))
                let blade = SCNCylinder(radius: CGFloat(s.D / 2), height: 0.012)
                blade.materials = [steelGray]
                let n = SCNNode(geometry: blade)
                n.position = v3(pos, gb - s.L + 0.25)
                root.addChildNode(n)
                let cap = SCNBox(width: 0.25, height: 0.006, length: 0.25, chamferRadius: 0)
                cap.materials = [steelGray]
                let cn = SCNNode(geometry: cap)
                cn.position = v3(pos, gb + 0.003)
                root.addChildNode(cn)
            }
        }
    }
}
