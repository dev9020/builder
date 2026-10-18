import SceneKit
import AppKit
import simd

/// Шаг 3D-просмотра: этап + подшаг (сколько стен уже поднято, какой этаж) и что делают на площадке
struct Step3D: Hashable {
    var stage: Stage3D
    var sub = Int.max
    var title: String
    var note: String
}

/// Последовательность работ для бегунка «Этап» — как на реальной стройке
enum Steps3D {
    static func make(_ p: Project, _ r: CalcResults, _ F: Framing) -> [Step3D] {
        var out: [Step3D] = []
        func add(_ st: Stage3D, _ sub: Int?, _ title: String?, _ note: String) {
            out.append(Step3D(stage: st, sub: sub ?? Int.max, title: title ?? st.title, note: note))
        }
        func add(_ st: Stage3D, note: String) { add(st, nil, nil, note) }
        let kind = p.selectedFoundation
        let mm = { (v: Double) in "\(Int((v * 1000).rounded())) мм" }
        add(.site, note: "Обноска в 1–1.5 м от осей, оси дома натянуты шнурами; прямые углы — по диагоналям (разница ≤ 10 мм)")
        switch kind {
        case .strip:
            let s = r.strip
            let b = s.ext?.b ?? 0.4
            add(.markout, note: "По шнурам известью размечают траншею: ширина подошвы \(mm(b)) + по 200–300 мм на опалубку и подушку")
            add(.dig, note: "Траншея на \(mm(s.depth + s.cushion)) (подошва \(mm(s.depth)) + подушка \(mm(s.cushion))); дно горизонтально по нивелиру, стенки — откосом")
            add(.cushion, note: "Геотекстиль, песок слоями 100–150 мм с проливкой и трамбованием (Kупл ≥ 0.95), сверху плёнка 200 мкм")
            add(.formwork, note: "Щиты из доски 25 мм на брусках 50×50, распорки по верху через 1 м; верх щитов по нивелиру = верх цоколя \(mm(p.plinth))")
            if let e = s.ext {
                add(.rebar, note: "Каркас в два пояса: низ \(e.botN)Ø\(e.botD), верх \(e.topN)Ø\(e.topD), хомуты Ø\(e.clampD) шаг \(mm(e.clampStep)); защитный слой \(mm(e.cover)) — на фиксаторах, углы — Г-образными вставками")
            }
            add(.concrete, note: "Бетон без перерыва, слоями ≈ 300 мм с вибрированием; 7 суток уход — полив и укрытие")
            add(.backfill, note: "Через 7–10 дней — распалубка, обмазочная гидроизоляция, ЭППС по цоколю, обратная засыпка песком с трамбованием")
        case .slab:
            let s = r.slab
            add(.markout, note: "Котлован — по контуру плиты + 500 мм на подушку и опалубку; колышки по углам, известь по контуру")
            add(.dig, note: "Снимают растительный слой и выбирают котлован на \(mm(s.depth + (p.soil.heave != .none ? 0.1 : 0))); дно ровняют и трамбуют")
            add(.cushion, note: "Геотекстиль, песок \(mm(p.slabCushion)) слоями 100–150 мм с трамбованием" + (p.soil.heave != .none ? ", сверху ЭППС 100 мм (УШП)" : "") + ", плёнка 200 мкм")
            add(.formwork, note: "Опалубка по периметру на высоту плиты \(mm(s.t)) + 30 мм, укосины через 1 м; верх — по нивелиру (\(mm(SlabCalc.aboveGround)) над землёй)")
            add(.rebar, note: "Две сетки Ø\(s.d) шаг \(mm(s.step)): нижняя на фиксаторах \(mm(s.cover)), верхняя — на «лягушках» ≈ 1.5 шт/м²; по торцам — П-образные стержни")
            add(.concrete, note: "Бетон за один приём, вибрирование, затирка по маякам; 7 суток уход — полив и укрытие")
            add(.backfill, note: "Распалубка, ЭППС по торцу плиты, засыпка пазух котлована песком")
        case .piles:
            let s = r.piles
            add(.markout, note: "Колышки в центрах свай (\(s.positions.count) шт.) — рулеткой от осей, по шнурам")
            if s.type == .screw {
                add(.dig, nil, "Завинчивание свай", "Сваи Ø\(mm(s.d)) завинчивают на \(fmt(s.L, 1)) м строго вертикально (контроль уровнем на каждом метре)")
                add(.cushion, nil, "Срезка свай по уровню", "Срезка по нивелиру, бетон М300 в ствол, оголовки на сварке")
            } else {
                add(.dig, nil, "Бурение скважин", "Скважины Ø\(mm(s.d)) на \(fmt(s.L, 1)) м" + (s.type == .boredEnlarged ? ", внизу уширение Ø\(mm(s.D))" : "") + "; дно — 100 мм щебня, трамбовка")
                add(.cushion, nil, "Каркасы и бетонирование свай", "Рубероид-рукав, каркас \(s.cageN)Ø\(s.cageD) с выпусками в ростверк, бетон с штыкованием")
            }
            add(.formwork, nil, "Опалубка ростверка", "Дно ростверка на подставках \(mm(0.15)) над землёй, борта на высоту \(mm(s.hg)), стяжки через 1 м")
            add(.rebar, nil, "Армирование ростверка", "Низ \(s.botN)Ø\(s.botD), верх \(s.topN)Ø\(s.topD), хомуты Ø\(s.stirD) шаг \(mm(s.stirStep)); выпуски свай заводят в каркас")
            add(.concrete, nil, "Бетонирование ростверка", "Бетон за один приём с вибрированием; 7 суток уход")
            add(.backfill, nil, "Распалубка ростверка", "Распалубка, гидроизоляция; зазор под ростверком не засыпают (пучение)")
        }
        add(.sill, nil, kind == .slab ? "Гидроизоляция и лежни на плите" : nil,
            kind == .slab ? "По контурам всех стен — гидроизоляция 2 слоя, лежень \(F.sillSec.label) на анкерах через ≤ 2 м и ≤ 300 мм от концов; стены потом ставятся на лежни"
                          : "Гидроизоляция в 2 слоя, обвязка \(F.sillSec.label) в угол «в лапу», анкеры через ≤ 2 м и ≤ 300 мм от углов")
        if F.members.contains(where: { $0.stage == .floor }) {
            add(.floor, note: "Балки \(F.floors.first.map { $0.check.sec.label } ?? "") с шагом \(mm(p.studStep)) по обвязке, утепление, настил ОСП — получается платформа для сборки стен")
        }
        // стены — по одной, в реальном порядке; следующая стена в это время собирается лёжа на платформе
        let E = F.erect
        for k in 0...E.count where !E.isEmpty {
            let next = k < E.count ? F.walls[E[k].wall].name : nil
            let title = k == 0 ? "Сборка первой стены" : "Стены: \(k) из \(E.count)"
            var note = k == 0 ? "Стену \(next!) собирают лёжа на платформе: обвязки, стойки через \(mm(p.studStep)), проёмы, раскосы; диагонали равны"
                              : E[k - 1].note.prefix(1).uppercased() + E[k - 1].note.dropFirst()
            if k > 0, let next { note += ". На платформе уже собирают \(next)" }
            add(.walls, k, title, note)
        }
        add(.cap, note: "Второй ряд верхней обвязки внахлёст: перекрывает стыки и углы и связывает стены в жёсткую коробку")
        let floors = max(p.floors, 1)
        if floors > 1 {
            for s in 1..<floors {
                add(.upper, (s - 1) * 3, "Перекрытие над \(s)-м этажом", "Балки по верхней обвязке с шагом \(mm(p.studStep)), настил ОСП — платформа для стен \(s + 1)-го этажа")
                add(.upper, (s - 1) * 3 + 1, "Наружные стены \(s + 1)-го этажа", "Собирают на платформе и поднимают в том же порядке, что и внизу; временные укосины")
                add(.upper, (s - 1) * 3 + 2, "Перегородки \(s + 1)-го этажа", "Перегородки и второй ряд обвязки")
            }
        }
        if F.members.contains(where: { $0.stage == .roof }) {
            add(.roof, nil, p.roofType == .flat ? "Балки плоской кровли" : nil,
                p.roofType == .flat ? "Балки по верхней обвязке, контруклон — после" : "Чердачные балки, затем стропильные пары — от фронтона к фронтону по шнуру, конёк, ветровые связи")
        }
        if F.members.contains(where: { $0.stage == .battens }) {
            add(.battens, note: "Мембрана, контробрешётка \(F.counterSec.label) по стропилам, обрешётка — под покрытие")
        }
        add(.finish, note: "Утепление, обшивка, фасад, кровля, окна и двери")
        return out
    }
}

/// Котлован или траншея на растре 5 см: вырез в грунте, стенки, дно и разметка известью
struct Pit {
    var lo = V2(0, 0), res = 0.05
    var nx = 0, ny = 0
    var hole: [Bool] = []
    var bottom = 0.0
    func at(_ i: Int, _ j: Int) -> Bool { i >= 0 && j >= 0 && i < nx && j < ny && hole[j * nx + i] }
    var hi: V2 { lo + V2(Double(nx) * res, Double(ny) * res) }

    static func make(_ p: Project, _ r: CalcResults) -> Pit? {
        var inside: (V2) -> Bool
        var pit = Pit()
        var lo: V2, hi: V2
        switch p.selectedFoundation {
        case .strip:
            let s = r.strip
            let ls: [(a: V2, d: V2, n: V2, len: Double, hw: Double)] = s.lines.compactMap { sl in
                guard let sec = s.section(sl.line) else { return nil }
                let d = sl.line.dir
                return (sl.line.a, d, V2(-d.y, d.x), sl.line.length, sec.b / 2 + 0.3)
            }
            guard !ls.isEmpty else { return nil }
            inside = { c in ls.contains { l in
                let v = c - l.a, u = dot2(v, l.d)
                return abs(dot2(v, l.n)) <= l.hw && u >= -l.hw && u <= l.len + l.hw
            } }
            pit.bottom = -(s.depth + s.cushion)
            (lo, hi) = Geo.bbox(p.rings)
        case .slab:
            let rings = r.slab.rings.enumerated().map { i, ring in Geo.offset(ring, by: i == 0 ? 0.5 : -0.5) }
            guard !rings.isEmpty else { return nil }
            inside = { Geo.contains($0, rings) }
            pit.bottom = -max(0.2, r.slab.depth + (p.soil.heave != .none ? 0.1 : 0))
            (lo, hi) = Geo.bbox(rings)
        case .piles:
            return nil
        }
        pit.lo = V2((lo.x - 1.2).rounded(.down), (lo.y - 1.2).rounded(.down))
        pit.nx = Int(((hi.x + 1.2 - pit.lo.x) / pit.res).rounded(.up))
        pit.ny = Int(((hi.y + 1.2 - pit.lo.y) / pit.res).rounded(.up))
        pit.hole = [Bool](repeating: false, count: pit.nx * pit.ny)
        for j in 0..<pit.ny {
            for i in 0..<pit.nx {
                pit.hole[j * pit.nx + i] = inside(pit.lo + V2((Double(i) + 0.5) * pit.res, (Double(j) + 0.5) * pit.res))
            }
        }
        return pit
    }

    /// Границы выреза — отрезки (слитые по рядам и столбцам)
    func boundary() -> [(V2, V2)] {
        var out: [(V2, V2)] = []
        for j in 0...ny {
            var run: Int? = nil
            for i in 0...nx {
                let edge = i < nx && at(i, j - 1) != at(i, j)
                if edge, run == nil { run = i }
                if !edge, let s = run {
                    let y = lo.y + Double(j) * res
                    out.append((V2(lo.x + Double(s) * res, y), V2(lo.x + Double(i) * res, y)))
                    run = nil
                }
            }
        }
        for i in 0...nx {
            var run: Int? = nil
            for j in 0...ny {
                let edge = j < ny && at(i - 1, j) != at(i, j)
                if edge, run == nil { run = j }
                if !edge, let s = run {
                    let x = lo.x + Double(i) * res
                    out.append((V2(x, lo.y + Double(s) * res), V2(x, lo.y + Double(j) * res)))
                    run = nil
                }
            }
        }
        return out
    }

    /// Прямоугольники по рядам: где есть вырез (hole = true) или где его нет
    func rows(_ want: Bool) -> [(V2, V2)] {
        var out: [(V2, V2)] = []
        for j in 0..<ny {
            var run: Int? = nil
            for i in 0...nx {
                let on = i < nx && at(i, j) == want
                if on, run == nil { run = i }
                if !on, let s = run {
                    out.append((lo + V2(Double(s) * res, Double(j) * res), lo + V2(Double(i) * res, Double(j + 1) * res)))
                    run = nil
                }
            }
        }
        // слить одинаковые ряды по вертикали
        var merged: [(V2, V2)] = []
        for r in out.sorted(by: { ($0.0.x, $0.0.y) < ($1.0.x, $1.0.y) }) {
            if let k = merged.indices.last, abs(merged[k].0.x - r.0.x) < 1e-6, abs(merged[k].1.x - r.1.x) < 1e-6, abs(merged[k].1.y - r.0.y) < 1e-6 {
                merged[k].1.y = r.1.y
            } else { merged.append(r) }
        }
        return merged
    }
}

extension SceneBuilder {
    /// Горизонтальные прямоугольники одной сеткой; UV — в метрах (материал задаёт размер плитки)
    static func flatRects(_ rects: [(V2, V2)], z: Double, _ m: SCNMaterial) -> SCNNode {
        var verts: [SCNVector3] = [], norms: [SCNVector3] = [], uvs: [CGPoint] = [], idx: [Int32] = []
        for (a, b) in rects {
            let base = Int32(verts.count)
            for v in [V2(a.x, a.y), V2(b.x, a.y), V2(b.x, b.y), V2(a.x, b.y)] {
                verts.append(v3(v, z)); norms.append(SCNVector3(0, 1, 0)); uvs.append(CGPoint(x: v.x, y: v.y))
            }
            idx += [base, base + 1, base + 2, base, base + 2, base + 3]
        }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: norms), SCNGeometrySource(textureCoordinates: uvs)],
                            elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        g.materials = [m]
        return SCNNode(geometry: g)
    }

    /// Грунт участка; при открытом котловане — с вырезом, стенками и дном
    static func stagedGround(_ p: Project, pit: Pit?, open: Bool, opacity: Double, _ root: SCNNode) {
        let (plo0, phi0) = plot(p)
        let plo = plo0 - V2(7, 7), phi = phi0 + V2(7, 7)
        let grass = texMat(.grass, uLen: 1, vLen: 1, opacity: opacity)
        guard open, let pit else {
            root.addChildNode(flatRects([(plo, phi)], z: 0, grass))
            return
        }
        let a = pit.lo, b = pit.hi
        var rects: [(V2, V2)] = [(plo, V2(phi.x, a.y)), (V2(plo.x, b.y), phi), (V2(plo.x, a.y), V2(a.x, b.y)), (V2(b.x, a.y), V2(phi.x, b.y))]
        rects += pit.rows(false)
        root.addChildNode(flatRects(rects, z: 0, grass))
        let soil = mat(rgb(0.47, 0.36, 0.25))
        root.addChildNode(flatRects(pit.rows(true), z: pit.bottom, mat(rgb(0.40, 0.31, 0.22))))
        var tris: [(simd_float3, simd_float3, simd_float3)] = []
        for (u, v) in pit.boundary() {
            tris += quad(f3(u, pit.bottom), f3(v, pit.bottom), f3(v, 0), f3(u, 0))
        }
        root.addChildNode(mesh(tris, soil))
    }

    /// Разметка известью по контуру будущего котлована/траншеи
    static func limeMarks(_ pit: Pit, _ root: SCNNode) {
        let lime = mat(rgb(0.97, 0.97, 0.94))
        let g = SCNNode()
        for (a, b) in pit.boundary() { g.addChildNode(beam(a, b, width: 0.06, bottom: 0.002, top: 0.008, extend: 0.03, lime)) }
        root.addChildNode(g.flattenedClone())
    }

    /// Опалубка вдоль лент/ростверка: щиты с двух сторон (в узлах обрезаны), стойки и распорки по верху через 1 м.
    /// lines — ось, ширина бетона; zb…zt — высота щитов; stake — низ стоек; bottom — дно (ростверк над землёй)
    static func formwork(_ lines: [(a: V2, b: V2, w: Double)], zb: Double, zt: Double, stake: Double, bottom: Bool, opacity: Double = 1, _ root: SCNNode) {
        let wood = mat(rgb(0.88, 0.76, 0.56), opacity)
        let bar = mat(rgb(0.70, 0.55, 0.36))
        let g = SCNNode()
        func inOther(_ c: V2, _ k: Int) -> Bool {
            for (j, l) in lines.enumerated() where j != k {
                let d = (l.b - l.a).unit, n = V2(-d.y, d.x), L = (l.b - l.a).len
                let v = c - l.a, u = dot2(v, d)
                if abs(dot2(v, n)) < l.w / 2 - 0.002 && u > -l.w / 2 + 0.002 && u < L + l.w / 2 - 0.002 { return true }
            }
            return false
        }
        for (k, l) in lines.enumerated() {
            let L = (l.b - l.a).len
            guard L > 0.05 else { continue }
            let d = (l.b - l.a) / L, n = V2(-d.y, d.x)
            for side in [-1.0, 1.0] {
                let off = n * side * (l.w / 2 + 0.0125)
                let u0 = -l.w / 2 - 0.025, u1 = L + l.w / 2 + 0.025
                var runs: [(Double, Double)] = []
                var start: Double? = nil
                var u = u0
                while u <= u1 + 1e-9 {
                    let free = !inOther(l.a + d * u + off, k)
                    if free, start == nil { start = u }
                    if !free, let s = start { runs.append((s, u)); start = nil }
                    u += 0.02
                }
                if let s = start { runs.append((s, u1)) }
                for (r0, r1) in runs where r1 - r0 > 0.05 {
                    g.addChildNode(beam(l.a + d * r0 + off, l.a + d * r1 + off, width: 0.025, bottom: zb, top: zt, extend: 0, wood))
                    // стойки снаружи щита
                    var t = r0 + 0.1
                    while t < r1 - 0.05 {
                        let c = l.a + d * t + n * side * (l.w / 2 + 0.05)
                        g.addChildNode(beam(c - d * 0.025, c + d * 0.025, width: 0.05, bottom: stake, top: zt + 0.1, extend: 0, bar))
                        t += 1.0
                    }
                }
            }
            // распорки (стяжки) поперёк по верху
            var t = 0.4
            while t < L - 0.2 {
                let c = l.a + d * t
                if !inOther(c, k) {
                    g.addChildNode(beam(c - n * (l.w / 2 + 0.08), c + n * (l.w / 2 + 0.08), width: 0.05, bottom: zt + 0.02, top: zt + 0.07, extend: 0, bar))
                }
                t += 1.0
            }
            if bottom {
                g.addChildNode(beam(l.a, l.b, width: l.w + 0.05, bottom: zb, top: zb + 0.025, extend: l.w / 2, wood))
            }
        }
        root.addChildNode(g.flattenedClone())
    }

    /// Опалубка плиты по периметру со стойками и укосинами
    static func slabFormwork(_ s: SlabResult, top: Double, bot: Double, opacity: Double = 1, _ root: SCNNode) {
        let wood = mat(rgb(0.88, 0.76, 0.56), opacity)
        let bar = mat(rgb(0.70, 0.55, 0.36))
        let g = SCNNode()
        for (ri, ring0) in s.rings.enumerated() {
            let out = ri == 0 ? 1.0 : -1.0
            let ring = Geo.offset(ring0, by: out * 0.0125)
            let ringS = Geo.offset(ring0, by: out * 0.05)
            for i in ring.indices {
                let a = ring[i], b = ring[(i + 1) % ring.count]
                g.addChildNode(beam(a, b, width: 0.025, bottom: bot - 0.05, top: top + 0.03, extend: 0.0125, wood))
                let a2 = ringS[i], b2 = ringS[(i + 1) % ringS.count]
                let L = (b2 - a2).len, d = (b2 - a2).unit
                var t = 0.3
                while t < L - 0.1 {
                    let c = a2 + d * t
                    // наружу — от центра стороны к точке на смещённом контуре
                    let m0 = ring0[i] + (ring0[(i + 1) % ring0.count] - ring0[i]).unit * t
                    let o = (c - m0).unit
                    g.addChildNode(beam(c - d * 0.025, c + d * 0.025, width: 0.05, bottom: bot - 0.3, top: top + 0.08, extend: 0, bar))
                    g.addChildNode(rod(f3(c + o * 0.03, top), f3(c + o * 0.55, bot - 0.05), radius: 0.02, bar))
                    t += 1.0
                }
            }
        }
        root.addChildNode(g.flattenedClone())
    }

    /// Утеплитель ЭППС по наружной грани (торец плиты, цоколь ленты)
    static func epsSkirt(_ rings: [[V2]], bottom: Double, top: Double, _ root: SCNNode) {
        let eps = mat(rgb(0.62, 0.80, 0.70))
        let g = SCNNode()
        for (ri, r) in rings.enumerated() {
            let ring = Geo.offset(r, by: ri == 0 ? 0.03 : -0.03)
            for i in ring.indices { g.addChildNode(beam(ring[i], ring[(i + 1) % ring.count], width: 0.05, bottom: bottom, top: top, extend: 0.025, eps)) }
        }
        root.addChildNode(g.flattenedClone())
    }

    // MARK: - Сцена этапа

    static func buildStaged(_ p: Project, _ r: CalcResults, _ o: SceneOptions, _ root: SCNNode) {
        let st = o.stage
        let kind = p.selectedFoundation
        let pit = Pit.make(p, r)
        let open = st >= .dig && st < .backfill
        if o.ground {
            // сваи и ростверк видно сквозь грунт, пока идёт нулевой цикл
            stagedGround(p, pit: pit, open: open, opacity: kind == .piles && st.isFoundation && st >= .dig ? 0.55 : 1, root)
        }
        if st <= .formwork { buildLayout(p, r, root, strings: st != .dig && st != .cushion) }
        if st == .markout, let pit { limeMarks(pit, root) }
        guard st >= .dig else { return }

        let showRebar = st == .rebar
        let parts = FoundParts(cushion: st >= .cushion, concrete: st >= .concrete,
                               piles: st >= .cushion || (kind == .piles && r.piles.type == .screw),
                               cages: kind == .piles && r.piles.type != .screw && st >= .cushion && st <= .rebar,
                               holes: kind == .piles && r.piles.type != .screw && st == .dig)
        let concrete = texMat(.concrete, uLen: 2, vLen: 1)
        let sand = texMat(.sand, uLen: 3, vLen: 0.5)
        let steel = mat(rgb(0.78, 0.32, 0.10), metal: true)
        let steelGray = mat(rgb(0.55, 0.57, 0.60), metal: true)
        let rebar = SCNNode()
        let formworkOn = st >= .formwork && st <= .concrete
        // на этапе армирования щиты полупрозрачные — видно каркас внутри
        let fo = st == .rebar ? 0.3 : 1.0
        switch kind {
        case .strip:
            let s = r.strip
            buildStrip(p, s, concrete, sand, steel, rebar, root, showRebar, parts: parts)
            if formworkOn {
                let secs = s.lines.compactMap { sl in s.section(sl.line).map { (sl, $0) } }
                let stem = secs.map { (a: $0.0.line.a, b: $0.0.line.b, w: $0.1.stemW) }
                let anyT = secs.contains { $0.1.isT }
                let soleH = secs.first(where: { $0.1.isT })?.1.soleH ?? 0
                let zb = anyT ? -s.depth + soleH : -s.depth
                formwork(stem, zb: zb, zt: p.plinth + 0.03, stake: -s.depth, bottom: false, opacity: fo, root)
                if anyT { formwork(secs.map { (a: $0.0.line.a, b: $0.0.line.b, w: $0.1.b) }, zb: -s.depth, zt: zb, stake: -s.depth, bottom: false, opacity: fo, root) }
            }
            if st >= .backfill {
                let ext = s.lines.filter { $0.line.isExterior }.compactMap { sl in s.section(sl.line).map { _ in sl } }
                if !ext.isEmpty, let e = s.ext { epsSkirt(p.rings.enumerated().map { i, ring in Geo.offset(ring, by: (i == 0 ? 1 : -1) * e.stemW / 2) }, bottom: -0.4, top: p.plinth, root) }
            }
        case .slab:
            let s = r.slab
            buildSlab(p, s, concrete, sand, steel, rebar, root, showRebar, parts: parts)
            if formworkOn { slabFormwork(s, top: SlabCalc.aboveGround, bot: SlabCalc.aboveGround - s.t, opacity: fo, root) }
            if st >= .backfill { epsSkirt(s.rings, bottom: -0.4, top: SlabCalc.aboveGround, root) }
        case .piles:
            let s = r.piles
            buildPiles(p, s, concrete, steel, steelGray, rebar, root, showRebar, parts: parts)
            if formworkOn {
                formwork(s.lines.map { (a: $0.line.a, b: $0.line.b, w: s.bg) }, zb: 0.15 - 0.025, zt: 0.15 + s.hg + 0.03, stake: 0, bottom: true, opacity: fo, root)
            }
        }
        root.addChildNode(rebar.flattenedClone())
        if st >= .sill { buildFrame(p, r, st, o.sub, root) }
    }
}

/// Какие части фундамента показывать на этапе
struct FoundParts {
    var cushion = true, concrete = true, piles = true, cages = false, holes = false
    static let all = FoundParts()
}
