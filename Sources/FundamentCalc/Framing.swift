import Foundation
import simd

typealias V3 = SIMD3<Double>

enum Sheathing: String, CaseIterable, Identifiable {
    case osb, osbBraces, braces
    var id: String { rawValue }
    var title: String {
        switch self {
        case .osb: return "ОСП-3 9 мм снаружи (диафрагма жёсткости)"
        case .osbBraces: return "ОСП-3 9 мм + врезные раскосы в углах"
        case .braces: return "Врезные раскосы 25×100 + ветрозащита"
        }
    }
    var hasOSB: Bool { self != .braces }
    var hasBraces: Bool { self != .osb }
}

enum SillType: String, CaseIterable, Identifiable {
    case timber, board
    var id: String { rawValue }
    var title: String {
        switch self {
        case .timber: return "Обвязочный брус 150 мм на ленте"
        case .board: return "Лежень 50 мм + платформа"
        }
    }
}

/// Этапы для 3D-просмотра (в порядке работ на площадке)
enum Stage3D: Int, CaseIterable, Identifiable, Comparable {
    case site, markout, dig, cushion, formwork, rebar, concrete, backfill, sill, floor, walls, cap, upper, roof, battens, finish
    var id: Int { rawValue }
    static func < (a: Stage3D, b: Stage3D) -> Bool { a.rawValue < b.rawValue }
    /// Этапы нулевого цикла — фундамент ещё не готов
    var isFoundation: Bool { self >= .markout && self <= .backfill }
    var title: String {
        switch self {
        case .site: return "Участок, обноска и оси"
        case .markout: return "Разметка котлована"
        case .dig: return "Котлован / траншея"
        case .cushion: return "Песчаная подушка"
        case .formwork: return "Опалубка"
        case .rebar: return "Армирование"
        case .concrete: return "Бетонирование"
        case .backfill: return "Распалубка и обратная засыпка"
        case .sill: return "Гидроизоляция, обвязка, анкеры"
        case .floor: return "Перекрытие пола 1-го этажа"
        case .walls: return "Подъём стен 1-го этажа"
        case .cap: return "Второй ряд верхней обвязки"
        case .upper: return "Перекрытия и верхние этажи"
        case .roof: return "Стропильная система"
        case .battens: return "Контробрешётка и обрешётка"
        case .finish: return "Готовый дом"
        }
    }
}

enum MemberKind: String, CaseIterable {
    case sill = "Обвязочный брус / лежень"
    case rim = "Обвязочная доска перекрытия"
    case joist = "Балка перекрытия"
    case blocking = "Распорка между балками"
    case nogging = "Распорка стены (под стык листов)"
    case bottomPlate = "Нижняя обвязка стены"
    case stud = "Стойка каркаса"
    case cornerStud = "Угловая / доп. стойка"
    case king = "Стойка проёма (полная)"
    case jack = "Опорная стойка перемычки"
    case header = "Перемычка проёма"
    case sillPiece = "Подоконный ригель"
    case cripple = "Укороченная стойка"
    case topPlate = "Верхняя обвязка"
    case capPlate = "Верхняя обвязка (2-й ряд)"
    case brace = "Раскос врезной"
    case tempBrace = "Временная укосина"
    case ceilingJoist = "Балка чердачного перекрытия"
    case rafter = "Стропильная нога"
    case hip = "Диагональная стропильная нога"
    case ridge = "Коньковая доска"
    case girder = "Прогон (ригель) перекрытия"
    case collar = "Ригель (схватка)"
    case tie = "Затяжка"
    case gableStud = "Стойка фронтона"
    case counterBatten = "Контробрешётка"
    case batten = "Обрешётка"

    var rgb: (Double, Double, Double) {
        switch self {
        case .sill: return (0.55, 0.42, 0.28)
        case .rim, .joist, .ceilingJoist: return (0.86, 0.72, 0.50)
        case .blocking, .nogging: return (0.80, 0.66, 0.45)
        case .bottomPlate, .topPlate, .capPlate: return (0.78, 0.62, 0.40)
        case .stud, .cornerStud, .gableStud: return (0.93, 0.80, 0.58)
        case .king, .jack, .cripple: return (0.90, 0.74, 0.50)
        case .header, .sillPiece: return (0.72, 0.52, 0.30)
        case .brace: return (0.85, 0.40, 0.25)
        case .tempBrace: return (0.95, 0.25, 0.20)
        case .rafter, .hip, .collar, .tie: return (0.83, 0.66, 0.44)
        case .girder: return (0.60, 0.40, 0.22)
        case .ridge: return (0.70, 0.50, 0.30)
        case .counterBatten: return (0.62, 0.50, 0.36)
        case .batten: return (0.90, 0.78, 0.60)
        }
    }
}

struct Member {
    var kind: MemberKind
    var sec: Lumber
    var a: V3, b: V3
    var up: V3                 // направление размера sec.w
    var stage: Stage3D
    var onlyOwnStage = false   // временные элементы
    var role = 0               // 0 — наружная стена/прочее, 1 — несущая перегородка, 2 — ненесущая
    var wall = -1              // индекс стены в Framing.walls (−1 — не стена)
    var storey = 0             // этаж; балки межэтажного перекрытия — этаж, который они несут
    var length: Double { simd_length(b - a) }
}

/// Развёртка стены для чертежа (координаты u — вдоль стены, z — от низа нижней обвязки)
struct WallFrame: Identifiable {
    let id = UUID()
    let name: String
    let storey: Int
    let exterior: Bool
    let depth: Double
    let length: Double
    let height: Double
    var rects: [(kind: MemberKind, u0: Double, u1: Double, z0: Double, z1: Double)] = []
    var braces: [(u0: Double, z0: Double, u1: Double, z1: Double)] = []
    var openings: [(u0: Double, u1: Double, z0: Double, z1: Double, label: String)] = []
    var temps: [Double] = []            // где ставятся временные укосины (u)
    var origin = 0.0                    // начало сетки стоек (u), для наружных стен — наружный угол
    // положение в плане (для 3D: стена собирается лёжа на платформе и поднимается)
    var a = V2(0, 0), dir = V2(1, 0), inward = V2(0, 1)
    var z0 = 0.0
    var bearing = true
}

struct JoistLayout {
    var title: String
    var alongX = true
    var check: Timber.BeamCheck
    var lines: [(V2, V2)] = []
    var supports: [(V2, V2)] = []
    var beams: [(V2, V2)] = []          // добавленные прогоны (ригели) при большом пролёте
    var maxSpan = 0.0
    var zBottom = 0.0
    var qd = 0.0, qn = 0.0
}

struct HeaderInfo: Identifiable {
    let id = UUID()
    let wall: String
    let storey: Int
    let opening: Opening
    let block: StdBlock
    let span: Double
    let q: Double
    let check: Timber.BeamCheck
}

struct Framing {
    var members: [Member] = []
    var walls: [WallFrame] = []
    var floors: [JoistLayout] = []
    var attic: JoistLayout?
    var headers: [HeaderInfo] = []
    var studExt = Lumber(50, 150), studInt = Lumber(50, 150), studPart = Lumber(50, 100)
    var stud: (phi: Double, sigma: Double, ok: Bool, N: Double, step: Double, l: Double) = (1, 0, true, 0, 0.6, 2.5)
    var sillSec = Lumber(150, 150), padSec = Lumber(50, 150)
    var anchors: [V2] = []
    var sillLines: [(V2, V2)] = []
    var rafter: Timber.BeamCheck?
    var rafterRun = 0.0
    var rafterStrut = false
    var separateTies = false
    var rafterLines: [(V2, V2)] = []
    var ridgeLines: [(V2, V2)] = []
    var battenStep = 0.35
    var battenSec = Lumber(25, 100)
    var counterSec = Lumber(50, 50)
    var levelBase = 0.0, wallTop = 0.0, foundTop = 0.0
    var wallHeights: [Double] = []
    var levels: [Double] = []           // отметки низа стен каждого этажа
    /// Порядок подъёма стен 1-го этажа (индексы в walls) с пояснением
    var erect: [(wall: Int, note: String)] = []
    var roofQd = 0.0, roofQn = 0.0
}

enum FrameGen {
    static func studSec(_ m: WallMaterial) -> Lumber {
        switch m {
        case .frame150, .sip: return Lumber(50, 150)
        case .frame200, .frame250: return Lumber(50, 200)
        }
    }

    /// Обрешётка под покрытие: сечение и шаг (по рекомендациям производителей, СП 17.13330.2017)
    static func batten(_ c: RoofCovering, angle: Double) -> (Lumber, Double, String) {
        switch c {
        case .metalTile: return (Lumber(25, 100), 0.35, "доска 25×100 с шагом 350 мм (= шаг волны листа), первая от карниза — на 15 мм толще")
        case .profiledSheet: return (Lumber(25, 100), angle < 15 ? 0.3 : 0.45, "доска 25×100 с шагом \(angle < 15 ? 300 : 450) мм")
        case .seam: return (Lumber(25, 100), 0.2, "доска 25×100 с зазором 100 мм (шаг 200 мм)")
        case .slate: return (Lumber(50, 50), 0.5, "брусок 50×50 с шагом 500 мм (3 бруска на лист 1750 мм)")
        case .ondulin: return (Lumber(50, 50), angle < 15 ? 0.45 : 0.6, "брусок 50×50 с шагом \(angle < 15 ? 450 : 600) мм")
        case .softShingle: return (Lumber(25, 100), 0.3, "доска 25×100 с шагом 300 мм + сплошной настил ОСП-3 12 мм")
        case .compositeTile: return (Lumber(50, 50), 0.37, "брусок 50×50 с шагом 370 мм (по размеру листа)")
        case .ceramicTile, .cementTile: return (Lumber(50, 50), 0.33, "брусок 50×50 с шагом 310–345 мм (подбирается по черепице на месте)")
        }
    }

    // MARK: - Перекрытия

    static func joists(rings: [[V2]], supports allLines: [BearingLine], zBottom: Double, step: Double, qd: Double, qn: Double,
                       preferX: Bool?, title: String, sizes: [Lumber], grid: Double = 0) -> JoistLayout {
        let (lo, hi) = Geo.bbox(rings)
        let maxFree = 4.8
        func layout(_ alongX: Bool) -> (lines: [(V2, V2, [Double])], maxSpan: Double, beams: [Double]) {
            var out: [(V2, V2, [Double])] = []
            var maxSpan = 0.0
            var used = Set<Int>()
            let a0 = alongX ? lo.x : lo.y, a1 = alongX ? hi.x : hi.y
            let nC = max(1, Int(((a1 - a0) / maxFree).rounded(.up)))
            let cand = (1..<max(nC, 1)).map { a0 + (a1 - a0) * Double($0) / Double(nC) }
            let c0 = alongX ? lo.y : lo.x, c1 = alongX ? hi.y : hi.x
            // крайняя балка у стены, остальные — по сетке от наружной грани (над стойками)
            var cs: [Double] = [c0 + 0.025]
            var c = grid > 0 ? c0 - grid + ((0.1 + grid) / step).rounded(.up) * step : c0 + 0.025 + step
            while c < c1 - 0.02 { cs.append(c); c += step }
            if let l = cs.last, c1 - 0.025 - l > 0.1 { cs.append(c1 - 0.025) }
            for c in cs {
                for (s0, s1) in Geo.scan(rings, at: c, horizontal: alongX) {
                    var sup: [Double] = [s0, s1]
                    for ln in allLines {
                        let d = ln.dir
                        guard alongX ? abs(d.x) < 0.1 : abs(d.y) < 0.1 else { continue }
                        let pos = alongX ? ln.a.x : ln.a.y
                        let r0 = alongX ? min(ln.a.y, ln.b.y) : min(ln.a.x, ln.b.x)
                        let r1 = alongX ? max(ln.a.y, ln.b.y) : max(ln.a.x, ln.b.x)
                        if pos > s0 + 0.05 && pos < s1 - 0.05 && c >= r0 - 0.01 && c <= r1 + 0.01 { sup.append(pos) }
                    }
                    sup.sort()
                    // пролёт больше допустимого — промежуточный прогон по общей сетке
                    var changed = true
                    while changed {
                        changed = false
                        for i in 1..<sup.count where sup[i] - sup[i - 1] > maxFree {
                            if let k = cand.indices.first(where: { cand[$0] > sup[i - 1] + 0.5 && cand[$0] < sup[i] - 0.5 && !sup.contains(cand[$0]) }) {
                                sup.append(cand[k]); used.insert(k); changed = true; break
                            }
                        }
                        sup.sort()
                    }
                    for i in 1..<sup.count { maxSpan = max(maxSpan, sup[i] - sup[i - 1]) }
                    let a = alongX ? V2(s0, c) : V2(c, s0), b = alongX ? V2(s1, c) : V2(c, s1)
                    out.append((a, b, sup))
                }
            }
            return (out, maxSpan, used.sorted().map { cand[$0] })
        }
        let lx = layout(true), ly = layout(false)
        let useX = preferX ?? (lx.maxSpan <= ly.maxSpan)
        let L = useX ? lx : ly
        let steps = step > 0.45 ? [step, 0.4] : [step]
        let chk = Timber.pickBeam(span: max(L.maxSpan, 0.5), qd: qd, qn: qn, steps: steps, sizes: sizes)
        var jl = JoistLayout(title: title, alongX: useX, check: chk)
        jl.maxSpan = L.maxSpan
        jl.zBottom = zBottom
        jl.qd = qd; jl.qn = qn
        if chk.step < step - 1e-6 {
            // пересобрать с меньшим шагом
            let again = joists(rings: rings, supports: allLines, zBottom: zBottom, step: chk.step, qd: qd, qn: qn, preferX: useX, title: title, sizes: sizes,
                               grid: abs(chk.step - Module.step) < 1e-6 ? grid : 0)
            return again
        }
        jl.lines = L.lines.map { ($0.0, $0.1) }
        jl.supports = allLines.map { ($0.a, $0.b) }
        for c in L.beams {
            for (s0, s1) in Geo.scan(rings, at: c, horizontal: !useX) {
                jl.beams.append(useX ? (V2(c, s0), V2(c, s1)) : (V2(s0, c), V2(s1, c)))
            }
        }
        return jl
    }

    // MARK: - Сборка каркаса

    static func make(_ p: Project, _ r: CalcResults) -> Framing {
        var F = Framing()
        let kind = p.selectedFoundation
        let rings = p.rings
        let edges = p.edges
        let lines = r.loads.lines
        guard !rings.isEmpty, !lines.isEmpty else { return F }
        let step = p.studStep
        let fh = p.floorHeight
        let floors = max(p.floors, 1)
        let ext0 = p.segments.first?.material ?? p.defaultMaterial
        F.studExt = studSec(ext0)
        let D = F.studExt.wm
        F.studInt = Lumber(50, 150)

        // --- Отметки ---
        switch kind {
        case .strip: F.foundTop = p.plinth
        case .slab: F.foundTop = SlabCalc.aboveGround
        case .piles: F.foundTop = 0.15 + r.piles.hg
        }
        let woodFloor = kind != .slab && p.groundFloor == .wood
        let sillH: Double = kind == .slab ? 0 : (p.sillType == .timber ? 0.15 : 0.05)
        F.sillSec = p.sillType == .timber ? Lumber(150, max(150, F.studExt.w)) : Lumber(50, max(150, F.studExt.w))
        F.padSec = F.sillSec

        // нагрузки на перекрытия, кПа (СП 20.13330.2016: табл. 7.1, 8.3, п. 8.2.2 — перегородки 0.5 кПа)
        let part = 0.5
        // пол 1-го этажа: ОСП + выбранное основание и покрытие (сухая стяжка, плитка и т. п.)
        let gDead = 0.7 + p.floorExtraDead
        let gq = (d: (gDead + part) * 1.2 + 1.5 * 1.3, n: gDead + part + 1.5)
        let fq = (d: (p.floorType.dead + part) * 1.2 + 1.5 * 1.3, n: p.floorType.dead + part + 1.5)
        let atticLive = p.roofInsulated ? 1.5 : 0.7
        let aq = (d: p.floorType.dead * 1.2 + atticLive * 1.3, n: p.floorType.dead + atticLive)
        let jSizes = [Lumber(50, 150), Lumber(50, 200), Lumber(50, 250)]
        // балки — по шагу стоек (над стойками), сетка от наружной грани каркаса
        let jStep = p.modular ? p.studStep : 0.6
        let jGrid = p.modular ? D / 2 : 0

        // карнизные стены — по ним идут затяжки (чердачные балки параллельно стропилам)
        let roofModel0 = RoofModel.of(p)
        var preferAttic: Bool? = nil
        if p.roofType == .gable || p.roofType == .shed, p.wings.count == 1 { preferAttic = !p.wings[0].axisX }

        var groundJ: JoistLayout?
        if woodFloor {
            groundJ = joists(rings: rings, supports: lines, zBottom: F.foundTop + sillH, step: jStep, qd: gq.d, qn: gq.n,
                             preferX: nil, title: "Перекрытие 1-го этажа (по фундаменту)", sizes: jSizes, grid: jGrid)
        }
        let interJ: JoistLayout? = floors > 1
            ? joists(rings: rings, supports: lines, zBottom: 0, step: jStep, qd: fq.d, qn: fq.n, preferX: nil, title: "Межэтажное перекрытие", sizes: jSizes, grid: jGrid)
            : nil
        var atticJ: JoistLayout? = nil
        if p.roofType != .flat {
            let title = p.roofInsulated ? "Перекрытие мансарды" : "Чердачное перекрытие"
            let free = joists(rings: rings, supports: lines, zBottom: 0, step: jStep, qd: aq.d, qn: aq.n, preferX: nil, title: title, sizes: jSizes, grid: jGrid)
            if let pref = preferAttic {
                let tied = joists(rings: rings, supports: lines, zBottom: 0, step: jStep, qd: aq.d, qn: aq.n, preferX: pref, title: title + " (балки — затяжки стропил)", sizes: jSizes, grid: jGrid)
                // балки вдоль стропил работают затяжками; если пролёт заметно больше — балки по короткому пролёту + отдельные затяжки
                atticJ = tied.maxSpan <= free.maxSpan + 0.5 || tied.maxSpan <= 5.0 ? tied : free
                F.separateTies = atticJ!.alongX != pref
            } else { atticJ = free }
        }
        if p.roofType == .flat {
            let flatQ = (d: p.flatSlab.weight * 1.2 + r.loads.snowS * 1.4, n: p.flatSlab.weight + r.loads.snowS)
            atticJ = joists(rings: rings, supports: lines, zBottom: 0, step: jStep, qd: flatQ.d, qn: flatQ.n, preferX: nil,
                            title: "Балки плоской кровли", sizes: jSizes, grid: jGrid)
        }
        let ghJ = groundJ.map { $0.check.sec.wm } ?? 0
        F.levelBase = F.foundTop + sillH + (woodFloor ? ghJ + 0.022 : 0)
        let interH = interJ.map { $0.check.sec.wm + 0.022 } ?? 0
        let atticH = atticJ.map { $0.check.sec.wm } ?? 0.2
        if p.modular {
            // стойка — целая доска 3000: высота каркаса постоянна, этаж = каркас + перекрытие
            F.wallHeights = Array(repeating: Module.frameH, count: floors)
            F.levels = (0..<floors).map { F.levelBase + Double($0) * (Module.frameH + interH) }
        } else {
            F.wallHeights = (0..<floors).map { k in fh - (k < floors - 1 ? interH : atticH) }
            F.levels = (0..<floors).map { F.levelBase + Double($0) * fh }
        }
        F.wallTop = F.levels.last! + F.wallHeights.last!

        // --- Обвязка по фундаменту и анкеры ---
        if kind != .slab {
            for ln in lines {
                let (a, b) = trimmed(ln.a, ln.b, ext: ln.isExterior, depth: ln.isExterior ? F.sillSec.wm : 0.15, p: p, rings: rings)
                F.sillLines.append((a, b))
                let sec = ln.isExterior ? F.sillSec : (p.sillType == .timber ? Lumber(150, 150) : Lumber(50, 150))
                F.members.append(flat(a, b, z0: F.foundTop, t: sec.tm, sec: sec, kind: .sill, stage: .sill))
            }
        } else {
            for ln in lines {
                let (a, b) = trimmed(ln.a, ln.b, ext: ln.isExterior, depth: ln.isExterior ? D : 0.15, p: p, rings: rings)
                F.sillLines.append((a, b))
            }
        }
        for (a, b) in F.sillLines {
            let L = (b - a).len
            guard L > 0.4 else { continue }
            // анкеры: ≤ 300 мм от концов и стыков, шаг ≤ 2.0 м (СП 352, раздел о креплении к фундаменту)
            var marks: [Double] = [0.3, L - 0.3]
            var j = 5.7
            while j < L - 0.6 { marks += [j - 0.3, j + 0.3]; j += 5.7 }
            marks.sort()
            var pts: [Double] = []
            for i in 0..<(marks.count - 1) {
                let s0 = marks[i], s1 = marks[i + 1]
                pts.append(s0)
                let n = Int(((s1 - s0) / 2.0 - 1e-6).rounded(.up))
                if n > 1 { for k in 1..<n { pts.append(s0 + (s1 - s0) * Double(k) / Double(n)) } }
            }
            pts.append(marks.last!)
            var last = -1.0
            for u in pts where u - last > 0.25 { F.anchors.append(a + (b - a).unit * u); last = u }
        }

        // --- Перекрытие 1-го этажа ---
        if var g = groundJ {
            g.zBottom = F.foundTop + sillH
            addJoists(&F, g, rings: rings, depth: D, kind: .joist, stage: .floor, withRim: true)
            F.floors.append(g)
        }

        // --- Стены по этажам ---
        let ops = p.validOpenings
        for k in 0..<floors {
            let z0 = F.levels[k]
            let hw = F.wallHeights[k]
            let stage: Stage3D = k == 0 ? .walls : .upper
            // наружные
            for (si, s) in p.segments.enumerated() {
                let e = edges[s.edge]
                let dir = (e.b - e.a).unit
                let sec = studSec(s.material)
                let depth = sec.wm
                let horizontal = abs(dir.x) > 0.5
                let atStart = (s.a - e.a).len < 1e-6, atEnd = (s.b - e.b).len < 1e-6
                let ext = horizontal ? depth / 2 : -depth / 2
                let inward = e.ring == 0 ? V2(-dir.y, dir.x) : V2(dir.y, -dir.x)
                let uOff = dot2(s.a - e.a, dir)
                let hostOps = ops.filter { $0.host == .edge(s.edge) && !(k > 0 && $0.kind.isDoor) }
                    .map { o -> Opening in var q = o; q.pos -= uOff; return q }
                    .filter { $0.pos > -0.01 && $0.pos < s.length + 0.01 }
                var wf = WallFrame(name: "Н\(si + 1)", storey: k, exterior: true, depth: depth, length: s.length, height: hw)
                wf.origin = -uOff - depth / 2      // сетка стоек — от наружного угла
                let first = F.members.count
                defer { for i in first..<F.members.count { F.members[i].wall = F.walls.count - 1; F.members[i].storey = k } }
                frameWall(&F, &wf, p: p, a: s.a, b: s.b, inward: inward, sec: sec, startExt: atStart ? ext : 0, endExt: atEnd ? ext : 0,
                          z0: z0, hw: hw, openings: hostOps, exterior: true, stage: stage, storey: k, junctions: junctions(p, s.a, s.b, except: nil),
                          sip: s.material == .sip, gable: k == floors - 1 ? roofModel0.profile(s.a, s.b) : [])
                F.walls.append(wf)
            }
            // перегородки
            for (pi, pt) in p.partitions.enumerated() where pt.length > 0.3 {
                let sec = pt.onFoundation ? F.studInt : F.studPart
                let dir = (pt.b - pt.a).unit
                let hs = hostDepth(p, pt.a, except: pt.id, extD: D), he = hostDepth(p, pt.b, except: pt.id, extD: D)
                let hostOps = ops.filter { $0.host == .partition(pt.id) }
                var wf = WallFrame(name: "П\(pi + 1)", storey: k, exterior: false, depth: sec.wm, length: pt.length, height: hw)
                let first = F.members.count
                defer { for i in first..<F.members.count { F.members[i].role = pt.onFoundation ? 1 : 2; F.members[i].wall = F.walls.count - 1; F.members[i].storey = k } }
                frameWall(&F, &wf, p: p, a: pt.a, b: pt.b, inward: V2(-dir.y, dir.x), sec: sec, startExt: -hs / 2, endExt: -he / 2,
                          z0: z0, hw: hw, openings: hostOps, exterior: false, stage: stage, storey: k,
                          junctions: junctions(p, pt.a, pt.b, except: pt.id), sip: false, gable: [], bearing: pt.onFoundation)
                F.walls.append(wf)
            }
            // перекрытие над этажом
            if k < floors - 1, var j = interJ {
                j.zBottom = z0 + hw
                let first = F.members.count
                addJoists(&F, j, rings: rings, depth: D, kind: .joist, stage: .upper, withRim: true)
                for i in first..<F.members.count { F.members[i].storey = k + 1 }
                if k == 0 { F.floors.append(j) }
            }
        }
        if var a = atticJ {
            a.zBottom = F.wallTop
            addJoists(&F, a, rings: rings, depth: D, kind: .ceilingJoist, stage: .roof, withRim: p.roofType == .flat)
            F.attic = a
        }

        F.erect = erectionOrder(F, p)

        // --- Стойка: устойчивость (самая нагруженная, 1-й этаж) ---
        // погонная расчётная нагрузка на стену (без пола 1-го этажа, который опирается на обвязку) × шаг стоек
        let maxDesign = (0..<lines.count).filter { lines[$0].isExterior && $0 < r.loads.slabLoads.count }.map { r.loads.slabLoads[$0].design }.max() ?? 10
        let N = maxDesign * step
        let lStud = F.wallHeights[0] - 0.15
        let sc = Timber.studCheck(F.studExt, N: N, l: lStud)
        F.stud = (sc.phi, sc.sigma, sc.ok, N, step, lStud)

        // --- Кровля ---
        if p.roofType != .flat { buildRafters(&F, p, r) }

        // --- Перемычки ---
        computeHeaders(&F, p, r, ops: ops)
        return F
    }

    /// Порядок подъёма стен 1-го этажа, как на площадке: первой — самая длинная наружная стена
    /// (на неё сразу ставят временные укосины), дальше по кругу — каждая следующая стыкуется в угол
    /// с уже стоящей, так коробка всё время раскреплена; затем стены двора, несущие перегородки, остальные перегородки.
    static func erectionOrder(_ F: Framing, _ p: Project) -> [(wall: Int, note: String)] {
        let ws = F.walls.indices.filter { F.walls[$0].storey == 0 }
        let segs = p.segments
        let edges = p.edges
        var out: [(Int, String)] = []
        for ring in 0..<max(p.rings.count, 1) {
            let ext = ws.filter { i in
                guard F.walls[i].exterior, let k = Int(F.walls[i].name.dropFirst()), k - 1 < segs.count else { return false }
                return edges[segs[k - 1].edge].ring == ring
            }
            guard !ext.isEmpty else { continue }
            let start = ext.indices.max { F.walls[ext[$0]].length < F.walls[ext[$1]].length }!
            for j in 0..<ext.count {
                let i = ext[(start + j) % ext.count]
                let w = F.walls[i]
                let note: String
                if ring == 0 && j == 0 {
                    note = "первой поднимают самую длинную стену \(w.name) (\(fmt(w.length, 2)) м): собрали лёжа на платформе, подняли, выставили по уровню и раскрепили временными укосинами"
                } else if j == ext.count - 1 {
                    note = "стена \(w.name) замыкает контур — стыкуется в оба угла; проверить диагонали коробки (разница ≤ 10 мм)"
                } else {
                    let prev = F.walls[ext[(start + j - 1 + ext.count) % ext.count]].name
                    note = ring == 0 ? "стена \(w.name) (\(fmt(w.length, 2)) м) встаёт в угол к \(prev): угол на 3 гвоздя через 300 мм, отвес по двум плоскостям"
                                     : "стена двора \(w.name) (\(fmt(w.length, 2)) м) — в угол к \(prev)"
                }
                out.append((i, note))
            }
        }
        let parts = ws.filter { !F.walls[$0].exterior }
        for i in parts.filter({ F.walls[$0].bearing }).sorted(by: { F.walls[$0].length > F.walls[$1].length }) {
            out.append((i, "несущая перегородка \(F.walls[i].name) (\(fmt(F.walls[i].length, 2)) м) — до перекрытия: на неё опираются балки"))
        }
        for i in parts.filter({ !F.walls[$0].bearing }).sorted(by: { F.walls[$0].length > F.walls[$1].length }) {
            out.append((i, "перегородка \(F.walls[i].name) (\(fmt(F.walls[i].length, 2)) м) — к стойкам примыкания стен"))
        }
        return out
    }

    /// Стыковка в углах: горизонтальные наружные стены — «проходные» (удлинены на D/2), вертикальные — «примыкающие»
    static func trimmed(_ a: V2, _ b: V2, ext: Bool, depth: Double, p: Project, rings: [[V2]]) -> (V2, V2) {
        let d = (b - a).unit
        guard ext else {
            let ha = hostDepth(p, a, except: nil, extD: depth, partitionPoint: true), hb = hostDepth(p, b, except: nil, extD: depth, partitionPoint: true)
            return (a + d * (ha / 2), b - d * (hb / 2))
        }
        let corners = rings.flatMap { $0 }
        let isCornerA = corners.contains { ($0 - a).len < 1e-6 }, isCornerB = corners.contains { ($0 - b).len < 1e-6 }
        let e = abs(d.x) > 0.5 ? depth / 2 : -depth / 2
        return (a - d * (isCornerA ? e : 0), b + d * (isCornerB ? e : 0))
    }

    /// Толщина стены, в которую упирается точка (для перегородок)
    static func hostDepth(_ p: Project, _ v: V2, except: UUID?, extD: Double, partitionPoint: Bool = false) -> Double {
        for e in p.edges where Geo.distToSegment(v, e.a, e.b) < 0.05 {
            if partitionPoint, (v - e.a).len < 1e-6 || (v - e.b).len < 1e-6 { return 0 }
            return extD
        }
        for pt in p.partitions where pt.id != except && pt.length > 0.3 && Geo.distToSegment(v, pt.a, pt.b) < 0.05 {
            if (v - pt.a).len < 0.05 || (v - pt.b).len < 0.05 { continue }
            return pt.onFoundation ? 0.15 : 0.1
        }
        return 0
    }

    /// Точки примыкания перегородок к стене a→b: (u, толщина)
    static func junctions(_ p: Project, _ a: V2, _ b: V2, except: UUID?) -> [(Double, Double)] {
        let d = (b - a).unit, L = (b - a).len
        var out: [(Double, Double)] = []
        for pt in p.partitions where pt.id != except && pt.length > 0.3 {
            for v in [pt.a, pt.b] where Geo.distToSegment(v, a, b) < 0.05 {
                let u = dot2(v - a, d)
                if u > 0.2 && u < L - 0.2 { out.append((u, pt.onFoundation ? 0.15 : 0.1)) }
            }
        }
        return out
    }

    // MARK: - Элементы

    static func v3(_ p: V2, _ z: Double) -> V3 { V3(p.x, p.y, z) }

    /// Плашмя лежащий элемент вдоль a→b (ширина — поперёк, толщина — вертикально)
    static func flat(_ a: V2, _ b: V2, z0: Double, t: Double, sec: Lumber, kind: MemberKind, stage: Stage3D, offset: V2 = V2(0, 0)) -> Member {
        let d = (b - a).unit
        let n = V2(-d.y, d.x)
        return Member(kind: kind, sec: sec, a: v3(a + offset, z0 + t / 2), b: v3(b + offset, z0 + t / 2), up: V3(n.x, n.y, 0), stage: stage)
    }

    /// Доска «на ребро» вдоль a→b
    static func onEdge(_ a: V2, _ b: V2, z0: Double, sec: Lumber, kind: MemberKind, stage: Stage3D) -> Member {
        Member(kind: kind, sec: sec, a: v3(a, z0 + sec.wm / 2), b: v3(b, z0 + sec.wm / 2), up: V3(0, 0, 1), stage: stage)
    }

    static func addJoists(_ F: inout Framing, _ j: JoistLayout, rings: [[V2]], depth: Double, kind: MemberKind, stage: Stage3D, withRim: Bool) {
        let sec = j.check.sec
        let n = j.check.count
        for (a, b) in j.beams {
            F.members.append(onEdge(a, b, z0: j.zBottom, sec: Lumber(150, sec.w), kind: .girder, stage: stage))
        }
        for (a, b) in j.lines {
            let d = (b - a).unit
            let a1 = a - d * (depth / 2 - 0.05), b1 = b + d * (depth / 2 - 0.05)
            for c in 0..<n {
                let off = V2(-d.y, d.x) * (Double(c) - Double(n - 1) / 2) * sec.tm
                F.members.append(onEdge(a1 + off, b1 + off, z0: j.zBottom, sec: sec, kind: kind, stage: stage))
            }
        }
        // распорки между балками — при пролёте > 2.5 м, не реже чем через 2 м
        let sorted = j.lines.sorted { j.alongX ? $0.0.y < $1.0.y : $0.0.x < $1.0.x }
        if j.maxSpan > 2.5 {
            let (lo, hi) = Geo.bbox(rings)
            let c0 = j.alongX ? lo.x : lo.y, c1 = j.alongX ? hi.x : hi.y
            var rows: [Double] = []
            var c = c0 + 2.0
            while c < c1 - 0.5 { rows.append(c); c += 2.0 }
            for row in rows {
                for i in 0..<(max(sorted.count, 1) - 1) {
                    let l0 = sorted[i], l1 = sorted[i + 1]
                    func covers(_ l: (V2, V2)) -> Bool { j.alongX ? (row > min(l.0.x, l.1.x) && row < max(l.0.x, l.1.x)) : (row > min(l.0.y, l.1.y) && row < max(l.0.y, l.1.y)) }
                    guard covers(l0), covers(l1) else { continue }
                    let p0 = j.alongX ? V2(row, l0.0.y) : V2(l0.0.x, row), p1 = j.alongX ? V2(row, l1.0.y) : V2(l1.0.x, row)
                    guard (p1 - p0).len < 0.9 else { continue }
                    let d = (p1 - p0).unit
                    F.members.append(onEdge(p0 + d * 0.025 * Double(n), p1 - d * 0.025 * Double(n), z0: j.zBottom, sec: sec, kind: .blocking, stage: stage))
                }
            }
        }
        guard withRim else { return }
        for (ri, ring) in rings.enumerated() {
            for i in ring.indices {
                let a = ring[i], b = ring[(i + 1) % ring.count]
                let d = (b - a).unit
                let out = ri == 0 ? V2(d.y, -d.x) : V2(-d.y, d.x)
                let o = out * (depth / 2 - 0.025)
                let horizontal = abs(d.x) > 0.5
                let e = horizontal ? depth / 2 : -(depth / 2 - 0.05)
                F.members.append(onEdge(a + o - d * e, b + o + d * e, z0: j.zBottom, sec: sec, kind: .rim, stage: stage))
            }
        }
    }

    // MARK: - Стена

    static func frameWall(_ F: inout Framing, _ wf: inout WallFrame, p: Project, a: V2, b: V2, inward: V2, sec: Lumber,
                          startExt: Double, endExt: Double, z0: Double, hw: Double, openings: [Opening], exterior: Bool,
                          stage: Stage3D, storey: Int, junctions: [(Double, Double)], sip: Bool,
                          gable: [(u: Double, h: Double)], bearing: Bool = true) {
        let L = (b - a).len
        guard L > 0.3 else { return }
        let dir = (b - a) / L
        let n3 = V3(inward.x, inward.y, 0)
        let D = sec.wm
        let s0 = -startExt, s1 = L + endExt
        let pt = 0.05
        let zTopB = z0 + hw - 2 * pt
        let gridOrigin = p.modular ? wf.origin : 0
        wf = WallFrame(name: wf.name, storey: wf.storey, exterior: wf.exterior, depth: D, length: s1 - s0, height: hw)
        wf.origin = gridOrigin - s0
        wf.a = a + dir * s0; wf.dir = dir; wf.inward = inward; wf.z0 = z0; wf.bearing = bearing
        func P(_ u: Double) -> V2 { a + dir * u }
        func rect(_ k: MemberKind, _ u0: Double, _ u1: Double, _ zb: Double, _ zt: Double) {
            wf.rects.append((k, u0 - s0, u1 - s0, zb - z0, zt - z0))
        }
        func vertical(_ k: MemberKind, _ u: Double, _ zb: Double, _ zt: Double, _ s: Lumber = sec) {
            guard zt - zb > 0.03 else { return }
            F.members.append(Member(kind: k, sec: s, a: v3(P(u), zb), b: v3(P(u), zt), up: n3, stage: stage))
            rect(k, u - 0.025, u + 0.025, zb, zt)
        }
        func horiz(_ k: MemberKind, _ u0: Double, _ u1: Double, _ zb: Double, s: Lumber? = nil) {
            guard u1 - u0 > 0.03 else { return }
            let ss = s ?? Lumber(50, sec.w)
            F.members.append(flat(P(u0), P(u1), z0: zb, t: ss.tm, sec: ss, kind: k, stage: stage))
            rect(k, u0, u1, zb, zb + ss.tm)
        }

        // проёмы
        struct RO { var r0: Double, r1: Double, zs: Double, zt: Double, door: Bool, label: String, o: Opening }
        let ros: [RO] = openings.map { o in
            let blk = StdBlock.nearest(o, exterior: exterior)
            return RO(r0: o.pos - o.width / 2, r1: o.pos + o.width / 2, zs: z0 + pt + o.sill, zt: min(z0 + pt + o.sill + o.height, zTopB - 0.15),
                      door: o.kind.isDoor || o.sill < 0.05, label: "\(o.kind.title) \(blk.mm)", o: o)
        }
        for ro in ros { wf.openings.append((ro.r0 - s0, ro.r1 - s0, ro.zs - z0, ro.zt - z0, ro.label)) }

        // нижняя обвязка (вырезается в дверных проёмах)
        var cuts = ros.filter { $0.door }.map { ($0.r0, $0.r1) }.sorted { $0.0 < $1.0 }
        var cur = s0
        cuts.append((s1, s1))
        for c in cuts { horiz(.bottomPlate, cur, min(c.0, s1), z0); cur = max(cur, c.1) }
        // верхняя обвязка в 2 ряда, второй ряд перевязывает углы
        horiz(.topPlate, s0, s1, zTopB)
        let c0 = exterior ? (startExt > 0 ? s0 + D : (startExt < 0 ? s0 - D : s0)) : s0
        let c1 = exterior ? (endExt > 0 ? s1 - D : (endExt < 0 ? s1 + D : s1)) : s1
        horiz(.capPlate, c0, c1, zTopB + pt)

        // стойки
        var studs: [(Double, MemberKind)] = []
        func add(_ u: Double, _ k: MemberKind) {
            guard u >= s0 + 0.02, u <= s1 - 0.02, !studs.contains(where: { abs($0.0 - u) < 0.045 }) else { return }
            studs.append((u, k))
        }
        add(s0 + 0.025, .cornerStud); add(s1 - 0.025, .cornerStud)
        if exterior && startExt > 0 { add(s0 + D + 0.025, .cornerStud) }
        if exterior && endExt > 0 { add(s1 - D - 0.025, .cornerStud) }
        for (u, t) in junctions { add(u - t / 2 - 0.025, .cornerStud); add(u + t / 2 + 0.025, .cornerStud) }
        for ro in ros { add(ro.r0 - 0.075, .king); add(ro.r1 + 0.075, .king) }
        let stepU = sip ? 1.25 : p.studStep
        var cripples: [Double] = []
        var u = sip ? stepU : gridOrigin + ((s0 + 0.05 - gridOrigin) / stepU).rounded(.up) * stepU
        if u < s0 + 0.06 { u += stepU }
        while u < s1 - 0.05 {
            if ros.contains(where: { u > $0.r0 - 0.1 && u < $0.r1 + 0.1 }) {
                if ros.contains(where: { u > $0.r0 + 0.03 && u < $0.r1 - 0.03 }) { cripples.append(u) }
            } else if !junctions.contains(where: { abs($0.0 - u) < $0.1 / 2 + 0.06 }) { add(u, .stud) }
            u += stepU
        }
        for (u, k) in studs { vertical(k, u, z0 + pt, zTopB) }

        // распорки под горизонтальный стык листов (ОСП снаружи, ГКЛ изнутри) — в каждом пролёте вне проёмов
        if p.modular && !sip {
            let zs = z0 + Module.seamZ - pt / 2
            let xs = studs.map(\.0).sorted()
            for i in 1..<max(xs.count, 1) {
                let ua = xs[i - 1] + 0.025, ub = xs[i] - 0.025
                guard ub - ua > 0.1, !ros.contains(where: { ua < $0.r1 + 0.05 && ub > $0.r0 - 0.05 && $0.zs < zs + 0.1 }) else { continue }
                F.members.append(Member(kind: .nogging, sec: Lumber(50, sec.w), a: v3(P(ua), zs + pt / 2), b: v3(P(ub), zs + pt / 2), up: V3(0, 0, 1), stage: stage))
                rect(.nogging, ua, ub, zs, zs + pt)
            }
        }

        // проёмы: опорные стойки, перемычки, ригели, укороченные стойки
        for ro in ros {
            let span = ro.r1 - ro.r0 + 0.1
            let hh = headerHeight(F, span: span, exterior: exterior, bearing: bearing)
            var zt = ro.zt
            if zt + hh > zTopB { zt = zTopB - hh }
            vertical(.jack, ro.r0 - 0.025, z0 + pt, zt)
            vertical(.jack, ro.r1 + 0.025, z0 + pt, zt)
            let hs = Lumber(50, Int((hh * 1000).rounded()))
            let across = max(D / 2 - 0.025, 0.025)
            for sgn in [-1.0, 1.0] where !(D <= 0.1 && sgn > 0) {
                let off = inward * (sgn * across)
                F.members.append(Member(kind: .header, sec: hs, a: v3(P(ro.r0 - 0.05) + off, zt + hh / 2), b: v3(P(ro.r1 + 0.05) + off, zt + hh / 2),
                                        up: V3(0, 0, 1), stage: stage))
            }
            rect(.header, ro.r0 - 0.05, ro.r1 + 0.05, zt, zt + hh)
            for cu in cripples where cu > ro.r0 && cu < ro.r1 { vertical(.cripple, cu, zt + hh, zTopB) }
            if !ro.door {
                let double = ro.r1 - ro.r0 > 1.5
                horiz(.sillPiece, ro.r0, ro.r1, ro.zs - pt)
                if double { horiz(.sillPiece, ro.r0, ro.r1, ro.zs - 2 * pt) }
                let zc = ro.zs - (double ? 2 : 1) * pt
                for cu in cripples where cu > ro.r0 && cu < ro.r1 { vertical(.cripple, cu, z0 + pt, zc) }
            }
        }

        // раскосы — от углов под 45…60°: снаружи, если нет ОСП-диафрагмы (или выбраны «ОСП + раскосы»);
        // во внутренних стенах — если изнутри нет листовой обшивки (вагонка не работает как диафрагма)
        if (exterior && p.sheathing.hasBraces) || (!exterior && !p.interiorFinish.isDiaphragm) {
            let hgt = zTopB - (z0 + pt)
            // свободные от проёмов участки стены; в каждом — раскос, у торцов стены — от угла
            var free: [(Double, Double)] = []
            var cur = s0
            for ro in ros.sorted(by: { $0.r0 < $1.r0 }) {
                if ro.r0 - 0.2 > cur { free.append((cur, ro.r0 - 0.2)) }
                cur = max(cur, ro.r1 + 0.2)
            }
            if s1 > cur { free.append((cur, s1)) }
            var pairs: [(Double, Double)] = []
            for (a0, a1) in free where a1 - a0 >= 1.2 {
                let run = min(hgt * 0.75, a1 - a0 - 0.2)
                let atStart = abs(a0 - s0) < 1e-6, atEnd = abs(a1 - s1) < 1e-6
                if atStart && atEnd && a1 - a0 > 2 * run + 0.6 {
                    pairs += [(a0 + 0.1, a0 + 0.1 + run), (a1 - 0.1, a1 - 0.1 - run)]
                } else if atEnd && !atStart {
                    pairs.append((a1 - 0.1, a1 - 0.1 - run))
                } else {
                    pairs.append((a0 + 0.1, a0 + 0.1 + run))
                }
            }
            for (ua, ub) in pairs {
                let pa = v3(P(ua) - inward * (D / 2 - 0.0125), z0 + pt), pb = v3(P(ub) - inward * (D / 2 - 0.0125), zTopB)
                let d3 = simd_normalize(pb - pa)
                let up = simd_normalize(simd_cross(n3, d3))
                F.members.append(Member(kind: .brace, sec: Lumber(25, 100), a: pa, b: pb, up: up, stage: stage))
                wf.braces.append((ua - s0, pt, ub - s0, zTopB - z0))
            }
        }

        // временные укосины при подъёме стен (только на этапе возведения)
        if exterior {
            var t = s0 + 0.6
            while t < s1 - 0.4 {
                if !ros.contains(where: { t > $0.r0 - 0.1 && t < $0.r1 + 0.1 }) {
                    let top = v3(P(t) + inward * (D / 2 + 0.0125), z0 + hw * 0.65)
                    let foot = v3(P(t) + inward * (D / 2 + hw * 0.6), z0)
                    let d3 = simd_normalize(foot - top)
                    let up = simd_normalize(simd_cross(V3(dir.x, dir.y, 0), d3))
                    F.members.append(Member(kind: .tempBrace, sec: Lumber(25, 100), a: top, b: foot, up: up, stage: stage, onlyOwnStage: true))
                    wf.temps.append(t - s0)
                }
                t += 2.4
            }
        }

        // стойки фронтона
        if !gable.isEmpty {
            let zTop = z0 + hw
            func gh(_ uu: Double) -> Double {
                guard let i = gable.firstIndex(where: { $0.u >= uu }) else { return gable.last!.h }
                if i == 0 { return gable[0].h }
                let p0 = gable[i - 1], p1 = gable[i]
                return p0.h + (p1.h - p0.h) * (uu - p0.u) / max(p1.u - p0.u, 1e-6)
            }
            var uu = stepU
            while uu < L - 0.05 {
                let h = gh(uu) - 0.1
                if h > 0.15 { F.members.append(Member(kind: .gableStud, sec: sec, a: v3(P(uu), zTop), b: v3(P(uu), zTop + h), up: n3, stage: .roof)) }
                uu += stepU
            }
        }
    }

    static func headerHeight(_ F: Framing, span: Double, exterior: Bool, bearing: Bool) -> Double {
        // предварительно — по пролёту; уточняется в computeHeaders
        if !bearing { return 0.1 }
        if span <= 1.0 { return 0.15 }
        if span <= 1.6 { return 0.2 }
        return 0.25
    }

    /// Проверка перемычек: нагрузка от перекрытий и кровли, пара досок на ребро; прогиб ≤ l/200 (СП 20, табл. Д.1)
    static func computeHeaders(_ F: inout Framing, _ p: Project, _ r: CalcResults, ops: [Opening]) {
        let floors = max(p.floors, 1)
        let roof = RoofModel.of(p)
        let jSpan = F.floors.first.map { $0.maxSpan } ?? F.attic?.maxSpan ?? 4
        let aSpan = F.attic?.maxSpan ?? jSpan
        let roofQ = 1.2 * r.loads.roofDead + 1.4 * r.loads.snowS
        let fQ = (p.floorType.dead + 0.5) * 1.2 + 1.5 * 1.3
        let aQ = p.floorType.dead * 1.2 + (p.roofInsulated ? 1.5 : 0.7) * 1.3
        for o in ops {
            guard let host = p.hostLine(o.host) else { continue }
            var exterior = false, bearing = true, name = ""
            switch o.host {
            case .edge(let i):
                exterior = true
                name = p.segments.firstIndex { $0.edge == i }.map { "Н\($0 + 1)" } ?? "Н"
            case .partition(let id):
                let idx = p.partitions.firstIndex { $0.id == id } ?? 0
                bearing = p.partitions[idx].onFoundation
                name = "П\(idx + 1)"
            }
            let eave = exterior && roof.onEave(host.a, host.b)
            let blk = StdBlock.nearest(o, exterior: exterior)
            let span = o.width + 0.1
            for k in 0..<floors where !(exterior && o.kind.isDoor && k > 0) {
                let trib = exterior ? 0.5 : 1.0
                var q = 0.0
                if bearing {
                    q += Double(floors - 1 - k) * fQ * jSpan * trib
                    q += aQ * aSpan * trib
                    if eave { q += roofQ * (F.rafterRun > 0 ? F.rafterRun : aSpan / 2) + roofQ * p.overhang }
                }
                q += 0.6 * 0.5 * 1.1     // стена над проёмом, ~0.5 м
                let qn = q / 1.25
                var chk = Timber.check(Lumber(50, 150), count: 2, step: 1, span: span, qd: q, qn: qn)
                let maxN = F.studExt.w >= 200 ? 4 : 3     // пакет не шире стены
                search: for n in 2...maxN {
                    for s in [Lumber(50, 150), Lumber(50, 200), Lumber(50, 250)] {
                        chk = Timber.check(s, count: n, step: 1, span: span, qd: q, qn: qn)
                        chk.fu = span / 200
                        chk.ok = chk.sigma <= Timber.Ri && chk.f <= chk.fu
                        if chk.ok { break search }
                    }
                }
                if !bearing { chk = Timber.check(Lumber(50, 100), count: 1, step: 1, span: span, qd: q, qn: qn); chk.ok = true }
                F.headers.append(HeaderInfo(wall: name, storey: k, opening: o, block: blk, span: span, q: q, check: chk))
            }
        }
    }

    // MARK: - Стропила

    static func buildRafters(_ F: inout Framing, _ p: Project, _ r: CalcResults) {
        let o = p.overhang
        let model = RoofModel.of(p, overhang: o)
        let rings = p.rings.enumerated().map { i, rr in Geo.offset(rr, by: i == 0 ? o : -o) }
        let tanA = model.tanA
        let alpha = atan(tanA)
        let cosA = cos(alpha)
        let D = F.studExt.wm
        let faceDepth = o - D / 2
        // пролёт стропила (горизонтальная проекция от наружной грани стены до конька)
        var maxD = 0.0
        let (lo, hi) = Geo.bbox(rings)
        var y = lo.y + 0.05
        while y < hi.y { var x = lo.x + 0.05; while x < hi.x { if Geo.contains(V2(x, y), rings), let d = model.depth(V2(x, y)) { maxD = max(maxD, d.d) }; x += 0.1 }; y += 0.1 }
        if p.roofType == .shed { maxD -= o }
        F.rafterRun = max(0.5, maxD - faceDepth)
        F.roofQd = 1.2 * r.loads.roofDead + 1.4 * r.loads.snowS
        F.roofQn = r.loads.roofDead + r.loads.snowS
        let steps = [p.studStep]
        let sizes = [Lumber(50, 150), Lumber(50, 200), Lumber(50, 250)]
        var chk = Timber.pickBeam(span: F.rafterRun, qd: F.roofQd, qn: F.roofQn, steps: steps, cosA: cosA, sizes: sizes, counts: [1])
        if !chk.ok {
            // промежуточная опора (подкос / стойка на несущую стену) — пролёт делится пополам
            F.rafterStrut = true
            chk = Timber.pickBeam(span: F.rafterRun / 2, qd: F.roofQd, qn: F.roofQn, steps: steps, cosA: cosA, sizes: sizes, counts: [1, 2])
        }
        F.rafter = chk
        let hR = chk.sec.wm
        let bt = batten(p.covering, angle: p.roofAngleEff)
        F.battenSec = bt.0; F.battenStep = bt.1

        func zb(_ v: V2, _ d: Double) -> Double { F.wallTop + (d - faceDepth) * tanA }
        func zc(_ v: V2, _ d: Double) -> Double { zb(v, d) + hR / 2 / cosA }
        func face(_ v: V2) -> Int? { Geo.contains(v, rings) ? model.depth(v)?.edge : nil }
        func slopeUp(_ n: V2) -> V3 { simd_normalize(V3(n.x * cosA, n.y * cosA, sin(alpha))) }
        func roofNormal(_ n: V2) -> V3 { simd_normalize(V3(-n.x * sin(alpha), -n.y * sin(alpha), cosA)) }

        var ridgeKeys = Set<String>()
        func key(_ a: V3, _ b: V3) -> String {
            let f = { (v: V3) in "\(Int((v.x * 50).rounded())),\(Int((v.y * 50).rounded()))" }
            let s = [f(a), f(b)].sorted()
            return s[0] + "|" + s[1]
        }
        let step = p.studStep
        for (ei, e) in model.edges.enumerated() where e.eave {
            let d = (e.b - e.a).unit
            let len = (e.b - e.a).len
            let cA = dot2(e.a, d)
            var us: [Double] = [0.04]
            // стропила — над стойками: та же сетка от наружной грани каркаса
            let g = p.modular ? ((d.x + d.y) > 0 ? -D / 2 : D / 2) : 0
            var k = ((cA + 0.1 - g) / step).rounded(.up)
            while k * step + g - cA < len - 0.1 { us.append(k * step + g - cA); k += 1 }
            us.append(len - 0.04)
            var ends: [(u: Double, end: V3, run: Double)] = []
            for u in us {
                let P0 = e.a + d * u
                guard face(P0 + e.n * 0.02) == ei else { continue }
                var s = 0.02
                while s < 30, face(P0 + e.n * (s + 0.02)) == ei { s += 0.02 }
                guard s > 0.15 else { continue }
                let P1 = P0 + e.n * s
                let a3 = v3(P0, zc(P0, 0)), b3 = v3(P1, zc(P1, s))
                let up = simd_normalize(simd_cross(simd_cross(simd_normalize(b3 - a3), V3(0, 0, 1)), simd_normalize(b3 - a3)))
                F.members.append(Member(kind: .rafter, sec: chk.sec, a: a3, b: b3, up: simd_dot(up, V3(0, 0, 1)) < 0 ? -up : up, stage: .roof))
                if chk.count > 1 {
                    let side = V3(d.x, d.y, 0) * 0.05
                    F.members.append(Member(kind: .rafter, sec: chk.sec, a: a3 + side, b: b3 + side, up: simd_dot(up, V3(0, 0, 1)) < 0 ? -up : up, stage: .roof))
                }
                F.rafterLines.append((P0, P1))
                // контробрешётка по стропилу
                let rn = roofNormal(e.n)
                let off = rn * (hR / 2 + F.counterSec.wm / 2)
                F.members.append(Member(kind: .counterBatten, sec: F.counterSec, a: a3 + off, b: b3 + off, up: rn, stage: .battens))
                ends.append((u, V3(P1.x, P1.y, zb(P1, s)), s))
            }
            // конёк: соседние стропила одной высоты, концы на расстоянии шага
            for i in 1..<max(ends.count, 1) {
                let a = ends[i - 1], b = ends[i]
                guard abs(a.end.z - b.end.z) < 0.02, simd_length(a.end - b.end) < step + 0.1 else { continue }
                let k = key(a.end, b.end)
                guard !ridgeKeys.contains(k) else { continue }
                ridgeKeys.insert(k)
                let rs = Lumber(50, chk.sec.w + 50)
                let za = a.end.z + hR / cosA - rs.wm / 2 + 0.02
                F.members.append(Member(kind: .ridge, sec: rs, a: V3(a.end.x, a.end.y, za), b: V3(b.end.x, b.end.y, za), up: V3(0, 0, 1), stage: .roof))
                F.ridgeLines.append((V2(a.end.x, a.end.y), V2(b.end.x, b.end.y)))
            }
            // отдельные затяжки, если балки чердачного перекрытия идут поперёк стропил
            if F.separateTies && p.roofType == .gable {
                let zt = F.wallTop + (F.attic?.check.sec.wm ?? 0.2)
                for en in ends where en.run > 0.5 {
                    let base = V2(en.end.x, en.end.y) - e.n * en.run
                    let da = (d.x < -0.5 || (abs(d.x) < 0.5 && d.y < 0)) ? -d : d
                    let a2 = base + da * 0.05 + e.n * (faceDepth), b2 = V2(en.end.x, en.end.y) + da * 0.05
                    let a3 = v3(a2, zt + 0.075), b3 = v3(b2 + (b2 - a2), zt + 0.075)
                    let k = key(a3, b3)
                    guard !ridgeKeys.contains(k), !ridgeKeys.contains(key(b3, a3)) else { continue }
                    ridgeKeys.insert(k)
                    F.members.append(Member(kind: .tie, sec: Lumber(50, 150), a: a3, b: b3, up: V3(0, 0, 1), stage: .roof))
                }
            }
            // ригели (схватки) двускатной кровли на 1/3 высоты от конька
            if p.roofType == .gable {
                for en in ends where ends.contains(where: { abs($0.end.z - en.end.z) < 0.02 && $0.u != en.u }) {
                    let rise = en.end.z - F.wallTop
                    guard rise > 1.2 else { continue }
                    let dz = rise / 3
                    let half = dz / tanA
                    let da = (d.x < -0.5 || (abs(d.x) < 0.5 && d.y < 0)) ? -d : d
                    let c = V2(en.end.x, en.end.y) + da * 0.05
                    let a3 = v3(c - e.n * half, en.end.z - dz), b3 = v3(c + e.n * half, en.end.z - dz)
                    let k = key(a3, b3)
                    guard !ridgeKeys.contains(k) else { continue }
                    ridgeKeys.insert(k)
                    F.members.append(Member(kind: .collar, sec: Lumber(50, 150), a: a3, b: b3, up: V3(0, 0, 1), stage: .roof))
                }
            }
            // обрешётка параллельно карнизу
            let sb = F.battenStep * cosA
            var dd = 0.05
            let maxS = ends.map(\.run).max() ?? 0
            while dd < maxS - 0.05 {
                var runStart: Double? = nil
                var t = -maxS - 0.1
                let tEnd = len + maxS + 0.1
                func emit(_ t0: Double, _ t1: Double) {
                    guard t1 - t0 > 0.2 else { return }
                    let A = e.a + d * t0 + e.n * dd, B = e.a + d * t1 + e.n * dd
                    let z = zb(A, dd) + (hR + F.counterSec.wm) / cosA + F.battenSec.tm / 2 / cosA
                    F.members.append(Member(kind: .batten, sec: F.battenSec, a: v3(A, z), b: v3(B, z), up: slopeUp(e.n), stage: .battens))
                }
                while t <= tEnd {
                    let inFace = face(e.a + d * t + e.n * dd) == ei
                    if inFace && runStart == nil { runStart = t }
                    if !inFace, let s = runStart { emit(s, t - 0.05); runStart = nil }
                    t += 0.05
                }
                if let s = runStart { emit(s, tEnd) }
                dd += sb
            }
        }

        // диагональные (накосные и ендовые) ноги — по биссектрисам углов, где сходятся два карниза
        var start = 0
        for ring in rings {
            let n = ring.count
            let es = Array(model.edges[start..<(start + n)])
            for i in 0..<n where es[i].eave && es[(i - 1 + n) % n].eave {
                let prev = start + (i - 1 + n) % n, cur = start + i
                let V = es[i].a
                let bis = (es[i].n + es[(i - 1 + n) % n].n).unit
                let perp = V2(-bis.y, bis.x)
                var t = 0.05
                while t < 30 {
                    let q = V + bis * (t + 0.05)
                    let f1 = face(q + perp * 0.06), f2 = face(q - perp * 0.06)
                    guard let a = f1, let b = f2, Set([a, b]) == Set([prev, cur]) else { break }
                    t += 0.05
                }
                guard t > 0.3 else { continue }
                let P1 = V + bis * t
                let dV = dot2(V - es[i].a, es[i].n), d1 = dot2(P1 - es[i].a, es[i].n)
                let a3 = v3(V, zc(V, dV) + 0.02), b3 = v3(P1, zc(P1, d1) + 0.02)
                let dir3 = simd_normalize(b3 - a3)
                let up = simd_normalize(simd_cross(simd_cross(dir3, V3(0, 0, 1)), dir3))
                let side = V3(perp.x, perp.y, 0) * 0.025
                for s in [-1.0, 1.0] {
                    F.members.append(Member(kind: .hip, sec: chk.sec, a: a3 + side * s, b: b3 + side * s, up: up.z < 0 ? -up : up, stage: .roof))
                }
            }
            start += n
        }
    }

    // MARK: - Ведомость пиломатериалов

    struct TakeoffRow: Identifiable {
        let id = UUID()
        let sec: Lumber
        let use: String
        let totalLength: Double
        let pieces: Int
        var stock = 6.0                 // длина хлыста, м
        var whole = false               // элементы ставятся целиком, без реза
        var volume: Double { Double(pieces) * sec.tm * sec.wm * stock }
    }

    /// Ведомость по стандартным длинам: элементы ровно 3000 (стойки) — целыми досками 3 м,
    /// короткие ≤ 1 м (распорки, укороченные стойки) — из досок 3 м, остальное — раскрой хлыстов 6 м
    static func takeoff(_ members: [Member]) -> [TakeoffRow] {
        var out: [TakeoffRow] = []
        var bySec: [Lumber: [Member]] = [:]
        for m in members { bySec[m.sec, default: []].append(m) }
        func uses(_ ms: [Member]) -> String {
            Dictionary(grouping: ms, by: \.kind).sorted { $0.value.count > $1.value.count }.map { "\($0.key.rawValue.lowercased()) (\($0.value.count))" }.prefix(4).joined(separator: ", ")
        }
        for s in bySec.keys.sorted() {
            let ms = bySec[s]!
            let whole = ms.filter { abs($0.length - Module.studLen) < 0.005 }
            let short = ms.filter { $0.length <= 1.0 && abs($0.length - Module.studLen) >= 0.005 }
            let rest = ms.filter { $0.length > 1.0 && abs($0.length - Module.studLen) >= 0.005 }
            if !whole.isEmpty {
                out.append(TakeoffRow(sec: s, use: uses(whole), totalLength: Double(whole.count) * Module.studLen,
                                      pieces: Int((Double(whole.count) * 1.03).rounded(.up)), stock: 3, whole: true))
            }
            if !short.isEmpty {
                out.append(TakeoffRow(sec: s, use: uses(short), totalLength: short.reduce(0) { $0 + $1.length },
                                      pieces: Int((Double(Timber.pack(short.map(\.length), stock: 3)) * 1.05).rounded(.up)), stock: 3))
            }
            if !rest.isEmpty {
                out.append(TakeoffRow(sec: s, use: uses(rest), totalLength: rest.reduce(0) { $0 + $1.length },
                                      pieces: Int((Double(Timber.pack(rest.map(\.length))) * 1.05).rounded(.up))))
            }
        }
        return out
    }
}
