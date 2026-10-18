import Foundation
import Combine

/// Прямоугольное «крыло» здания для построения кровли. axisX — конёк вдоль оси X.
struct Wing {
    var x0: Double, y0: Double, x1: Double, y1: Double
    var axisX: Bool
    var alongMin: Double { axisX ? x0 : y0 }
    var alongMax: Double { axisX ? x1 : y1 }
    var spanMin: Double { axisX ? y0 : x0 }
    var spanMax: Double { axisX ? y1 : x1 }
    var span: Double { spanMax - spanMin }
    func contains(_ p: V2) -> Bool { p.x >= x0 - 1e-9 && p.x <= x1 + 1e-9 && p.y >= y0 - 1e-9 && p.y <= y1 + 1e-9 }

    static func auto(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> Wing {
        Wing(x0: x0, y0: y0, x1: x1, y1: y1, axisX: (x1 - x0) >= (y1 - y0))
    }
}

struct EdgeConfig: Equatable {
    var splits: [Double] = []
    var materials: [WallMaterial?] = [nil]
}

struct WallSegment: Identifiable {
    let id: String
    let edge: Int
    let sub: Int
    let a: V2
    let b: V2
    let material: WallMaterial
    var length: Double { (b - a).len }
}

struct Partition: Identifiable, Equatable {
    var id = UUID()
    var a: V2
    var b: V2
    var material: WallMaterial
    var onFoundation: Bool
    var thickness: Double
    var length: Double { (b - a).len }

    init(id: UUID = UUID(), a: V2, b: V2, material: WallMaterial, onFoundation: Bool, thickness: Double? = nil) {
        self.id = id; self.a = a; self.b = b; self.material = material; self.onFoundation = onFoundation
        self.thickness = thickness ?? material.partitionThickness(bearing: onFoundation)
    }
}

enum OpeningKind: String, CaseIterable, Identifiable {
    case window, panoramic, door, glassDoor
    var id: String { rawValue }
    var title: String {
        switch self {
        case .window: return "Окно"
        case .panoramic: return "Окно в пол"
        case .door: return "Дверь"
        case .glassDoor: return "Стекл. дверь"
        }
    }
    var isDoor: Bool { self == .door || self == .glassDoor }
    var isGlazed: Bool { self != .door }
}

enum OpeningHost: Hashable {
    case edge(Int)
    case partition(UUID)
}

/// Проём (окно/дверь); pos — расстояние от начала стены до центра проёма, м
struct Opening: Identifiable, Equatable {
    var id = UUID()
    var host: OpeningHost
    var pos: Double
    var kind: OpeningKind
    var width: Double
    var height: Double
    var sill: Double

    static func make(_ kind: OpeningKind, host: OpeningHost, pos: Double) -> Opening {
        let interior: Bool
        if case .partition = host { interior = true } else { interior = false }
        switch kind {
        case .window: return Opening(host: host, pos: pos, kind: .window, width: 1.2, height: 1.4, sill: 0.85)
        case .panoramic: return Opening(host: host, pos: pos, kind: .panoramic, width: 2.0, height: 2.4, sill: 0)
        case .door: return Opening(host: host, pos: pos, kind: .door, width: interior ? 0.8 : 0.9, height: interior ? 2.0 : 2.1, sill: 0)
        case .glassDoor: return Opening(host: host, pos: pos, kind: .glassDoor, width: interior ? 0.9 : 1.0, height: interior ? 2.1 : 2.3, sill: 0)
        }
    }
}

/// Снимок состояния на начало перетаскивания стены
struct DragSnapshot {
    var length: Double, width: Double, wingA: Double, wingB: Double, innerL: Double, innerW: Double
    var partitions: [Partition]
    var openingWorld: [UUID: V2]
    var edge: (a: V2, b: V2)
}

final class Project: ObservableObject {
    // Форма
    @Published var shape: HouseShape = .rectangle {
        didSet { if oldValue != shape { edgeConfigs = [:]; partitions = []; openings = []; roomMarks = [] } }
    }
    @Published var length = 12.0
    @Published var width = 9.0
    @Published var wingA = 4.5
    @Published var wingB = 4.5
    @Published var innerL = 4.0
    @Published var innerW = 3.0

    // Стены
    @Published var floors = 1
    @Published var floorHeight = 2.8
    @Published var defaultMaterial: WallMaterial = .frame200
    @Published var thicknesses: [WallMaterial: Double] = Dictionary(uniqueKeysWithValues: WallMaterial.allCases.map { ($0, $0.defaultThickness) })
    @Published var edgeConfigs: [Int: EdgeConfig] = [:]
    @Published var partitions: [Partition] = []
    @Published var openings: [Opening] = []
    @Published var facade: FacadeFinish = .imitationTimber
    @Published var darkFrames = false

    // Перекрытия
    @Published var floorType: FloorType = .woodJoists
    @Published var groundFloor: GroundFloorType = .wood
    // Пол 1-го этажа и отделка
    @Published var floorSystem: FloorSystem = .osbJoists
    @Published var floorHeating: FloorHeating = .none
    @Published var floorFinish: FloorFinish = .laminate
    @Published var interiorFinish: InteriorFinish = .gkl
    /// Назначение комнат (ручные пометки) и наружные сети
    @Published var roomMarks: [RoomMark] = []
    @Published var septic: SepticType = .bio

    // Кровля
    @Published var roofType: RoofType = .gable
    @Published var covering: RoofCovering = .metalTile
    @Published var roofAngle = 30.0
    @Published var roofAngleAuto = true
    @Published var roofInsulated = true
    @Published var overhang = 0.5
    @Published var ridgeAlongLong = true
    @Published var flatSlab: FlatRoofSlab = .wood

    // Климат
    @Published var cityIndex = 0 {
        didSet {
            if cityIndex >= 0 && cityIndex < cities.count {
                mt = cities[cityIndex].mt; snowRegion = cities[cityIndex].snow
                tHeat = cities[cityIndex].tHeat; zHeat = cities[cityIndex].zHeat
            }
        }
    }
    @Published var tHeat = -2.2
    @Published var zHeat = 205.0
    var climate: HeatClimate { HeatClimate(tHeat: tHeat, zHeat: zHeat) }

    // Каркас (проект дома)
    @Published var studStep = 0.625
    /// Модульная система: стойка 3000, шаг 625, размеры кратны листу 1250, только стандартные блоки
    @Published var modular = true
    @Published var sheathing: Sheathing = .osb
    @Published var sillType: SillType = .timber
    @Published var mt = 23.0
    @Published var snowRegion: SnowRegion = .r3
    @Published var heated = true

    // Грунт
    @Published var soilPreset = 4 {
        didSet { if soilPreset >= 0 && soilPreset < Soil.presets.count { soil = Soil.presets[soilPreset] } }
    }
    @Published var soil: Soil = Soil.presets[4]
    @Published var gwl = 3.0

    // Фундамент
    @Published var selectedFoundation: FoundationKind = .strip
    @Published var concrete: ConcreteClass = .B20
    @Published var rebar: RebarClass = .A500
    @Published var stripKind: StripKind = .deep
    @Published var shallowDepth = 0.5
    @Published var plinth = 0.4
    @Published var concretePrep = true
    @Published var topsoil = 0.25
    @Published var slabMinThickness = 0.25
    @Published var slabCushion = 0.4
    @Published var pileType: PileType = .bored {
        didSet {
            guard oldValue != pileType else { return }
            switch pileType {
            case .bored: pileDiameter = 0.3
            case .boredEnlarged: pileDiameter = 0.25; pileEnlarge = 0.5
            case .screw: pileDiameter = 0.108; pileEnlarge = 0.3
            }
        }
    }
    @Published var pileDiameter = 0.3
    @Published var pileEnlarge = 0.5
    @Published var pileLengthAuto = true
    @Published var pileLength = 2.5
    @Published var grillageH = 0.4

    init() { loadDefault() }

    /// Дом по умолчанию: каркасный 10×8 м с имитацией бруса, несущая стена посередине, окна и двери
    func loadDefault() {
        shape = .rectangle
        length = 10; width = 8
        defaultMaterial = .frame200
        facade = .imitationTimber
        edgeConfigs = [:]
        roofType = .gable
        roofAngleAuto = true
        floorType = .woodJoists
        groundFloor = .wood
        let p1 = Partition(a: V2(5, 0), b: V2(5, 8), material: .frame150, onFoundation: true)
        let p2 = Partition(a: V2(0, 4), b: V2(5, 4), material: .frame150, onFoundation: false)
        let p3 = Partition(a: V2(7.5, 8), b: V2(7.5, 5), material: .frame150, onFoundation: false)
        let p4 = Partition(a: V2(7.5, 5), b: V2(10, 5), material: .frame150, onFoundation: false)
        partitions = [p1, p2, p3, p4]
        // e0 — низ (0,0)→(10,0), e1 — право (10,0)→(10,8), e2 — верх (10,8)→(0,8), e3 — лево (0,8)→(0,0)
        openings = [
            Opening.make(.window, host: .edge(0), pos: 2.5),
            Opening.make(.door, host: .edge(0), pos: 6.0),
            { var o = Opening.make(.window, host: .edge(0), pos: 8.3); o.width = 1.5; return o }(),
            Opening.make(.window, host: .edge(1), pos: 2.5),
            { var o = Opening.make(.window, host: .edge(2), pos: 1.25); o.width = 0.6; o.height = 0.6; o.sill = 1.5; return o }(),
            Opening.make(.window, host: .edge(2), pos: 7.5),
            Opening.make(.window, host: .edge(3), pos: 2.0),
            Opening.make(.door, host: .partition(p1.id), pos: 5.8),
            Opening.make(.door, host: .partition(p2.id), pos: 3.8),
            Opening.make(.door, host: .partition(p4.id), pos: 1.2),
        ]
        fitToModule()
    }

    /// Выбор формы: загружается типовой проект этой формы с полной планировкой, тип фундамента сохраняется
    static let shapeDefaults: [HouseShape: String] = [.square: "cube81", .rectangle: "scandi112", .lShape: "l114", .uShape: "u150", .ring: "atrium153"]

    func applyShapeDefault(_ s: HouseShape) {
        guard let id = Project.shapeDefaults[s], let preset = HousePreset.all.first(where: { $0.id == id }) else { shape = s; return }
        let keep = selectedFoundation
        preset.apply(self)
        selectedFoundation = keep
    }

    /// Эффективный уклон кровли, град. Авто: по минимальному уклону покрытия; для односкатной —
    /// с ограничением перепада высот стен (~2.2 м), для двускатной/вальмовой — 30° (сход снега).
    var roofAngleEff: Double {
        guard roofAngleAuto, roofType != .flat else { return roofAngle }
        let minA = covering.minSlope
        switch roofType {
        case .shed:
            let span = wings.map(\.span).max() ?? width
            return max(minA, min(25, (atan(2.2 / max(span, 1)) * 180 / .pi).rounded()))
        default:
            return max(minA, 30)
        }
    }

    /// Перепад высот стен для односкатной кровли, м
    var shedDrop: Double { (wings.map(\.span).max() ?? width) * tan(roofAngleEff * .pi / 180) }

    // MARK: - Проёмы

    func hostLine(_ h: OpeningHost) -> (a: V2, b: V2)? {
        switch h {
        case .edge(let i):
            let e = edges
            return i < e.count ? (e[i].a, e[i].b) : nil
        case .partition(let id):
            return partitions.first { $0.id == id }.map { ($0.a, $0.b) }
        }
    }

    /// Проёмы с действующей геометрией (центр в пределах стены)
    var validOpenings: [Opening] {
        openings.compactMap { o in
            guard let l = hostLine(o.host) else { return nil }
            let len = (l.b - l.a).len
            guard len > o.width + 0.1 else { return nil }
            var c = o
            c.pos = min(max(o.pos, o.width / 2 + 0.05), len - o.width / 2 - 0.05)
            return c
        }
    }

    func openingCenter(_ o: Opening) -> V2? {
        guard let l = hostLine(o.host) else { return nil }
        return l.a + (l.b - l.a).unit * o.pos
    }

    func removePartition(_ id: UUID) {
        partitions.removeAll { $0.id == id }
        openings.removeAll { $0.host == .partition(id) }
    }

    // MARK: - Перетаскивание стен

    func snapshot(edge: Int) -> DragSnapshot {
        let e = edges[edge]
        var ow: [UUID: V2] = [:]
        for o in openings { if let c = openingCenter(o) { ow[o.id] = c } }
        return DragSnapshot(length: length, width: width, wingA: wingA, wingB: wingB, innerL: innerL, innerW: innerW,
                            partitions: partitions, openingWorld: ow, edge: (e.a, e.b))
    }

    /// Сдвинуть сторону контура на delta (м) по нормали к ней (по оси X для вертикальных, Y для горизонтальных)
    func applyEdgeDrag(edge: Int, delta: Double, from s: DragSnapshot) {
        let horizontal = abs(s.edge.b.y - s.edge.a.y) < 1e-9
        var L = s.length, W = s.width, a = s.wingA, b = s.wingB, il = s.innerL, iw = s.innerW
        var shift = V2(0, 0)
        let d = delta
        switch (shape, edge) {
        case (.square, 0): L -= d; shift = V2(0, d)
        case (.square, 3): L -= d; shift = V2(d, 0)
        case (.square, _): L += d
        case (.rectangle, 0), (.ring, 0): W -= d; shift = V2(0, d)
        case (.rectangle, 1), (.ring, 1): L += d
        case (.rectangle, 2), (.ring, 2): W += d
        case (.rectangle, 3), (.ring, 3): L -= d; shift = V2(d, 0)
        case (.ring, 4): iw -= 2 * d
        case (.ring, 5): il += 2 * d
        case (.ring, 6): iw += 2 * d
        case (.ring, 7): il -= 2 * d
        case (.lShape, 0): W -= d; a -= d; shift = V2(0, d)
        case (.lShape, 1): L += d
        case (.lShape, 2): a += d
        case (.lShape, 3): b += d
        case (.lShape, 4): W += d
        case (.lShape, 5): L -= d; b -= d; shift = V2(d, 0)
        case (.uShape, 0): W -= d; a -= d; shift = V2(0, d)
        case (.uShape, 1): L += d
        case (.uShape, 2), (.uShape, 6): W += d
        case (.uShape, 3): b -= d
        case (.uShape, 4): a += d
        case (.uShape, 5): b += d
        case (.uShape, 7): L -= d; shift = V2(d, 0)
        default: return
        }
        length = min(max(L, 3), 40)
        width = min(max(W, 3), 40)
        wingA = max(a, 1.5); wingB = max(b, 1.5)
        innerL = max(il, 1); innerW = max(iw, 1)

        // точки на перемещаемой стене сдвигаются вместе с ней, всё — на shift
        let move = horizontal ? V2(0, d) : V2(d, 0)
        func moved(_ v: V2) -> V2 {
            let onEdge = Geo.distToSegment(v, s.edge.a, s.edge.b) < 0.06
            return (onEdge ? v + move : v) - shift
        }
        partitions = s.partitions.map { var q = $0; q.a = moved(q.a); q.b = moved(q.b); return q }
        let ee = edges
        openings = openings.map { o in
            guard case .edge(let i) = o.host, let w0 = s.openingWorld[o.id], i < ee.count else { return o }
            var q = o
            q.pos = dot2(w0 - shift - ee[i].a, (ee[i].b - ee[i].a).unit)
            return q
        }
    }

    func thickness(_ m: WallMaterial) -> Double { thicknesses[m] ?? m.defaultThickness }

    var effW: Double { shape == .square ? length : width }

    static func ringsFor(_ shape: HouseShape, L l0: Double, W w0: Double, a a0: Double, b b0: Double, il: Double, iw: Double) -> [[V2]] {
        let L = max(l0, 3), W = shape == .square ? L : max(w0, 3)
        switch shape {
        case .square, .rectangle:
            return [[V2(0, 0), V2(L, 0), V2(L, W), V2(0, W)]]
        case .lShape:
            let a = min(max(a0, 1.5), W - 1), b = min(max(b0, 1.5), L - 1)
            return [[V2(0, 0), V2(L, 0), V2(L, a), V2(b, a), V2(b, W), V2(0, W)]]
        case .uShape:
            let d = min(max(a0, 1.5), W - 1), t = min(max(b0, 1.5), (L - 3) / 2)   // двор не уже 3 м
            return [[V2(0, 0), V2(L, 0), V2(L, W), V2(L - t, W), V2(L - t, d), V2(t, d), V2(t, W), V2(0, W)]]
        case .ring:
            let l = min(max(il, 1), L - 3), w = min(max(iw, 1), W - 3)
            let x0 = (L - l) / 2, y0 = (W - w) / 2
            return [[V2(0, 0), V2(L, 0), V2(L, W), V2(0, W)],
                    [V2(x0, y0), V2(x0 + l, y0), V2(x0 + l, y0 + w), V2(x0, y0 + w)]]
        }
    }

    var rings: [[V2]] { Project.ringsFor(shape, L: length, W: width, a: wingA, b: wingB, il: innerL, iw: innerW) }

    var wings: [Wing] {
        let r = rings
        let L = r[0].map(\.x).max() ?? length
        let W = r[0].map(\.y).max() ?? width
        switch shape {
        case .square, .rectangle:
            let long = L >= W
            return [Wing(x0: 0, y0: 0, x1: L, y1: W, axisX: ridgeAlongLong ? long : !long)]
        case .lShape:
            let a = r[0][2].y, b = r[0][3].x
            return [Wing.auto(0, 0, L, a), Wing.auto(0, 0, b, W)]
        case .uShape:
            let d = r[0][4].y, t = r[0][5].x
            return [Wing.auto(0, 0, L, d), Wing.auto(0, 0, t, W), Wing.auto(L - t, 0, L, W)]
        case .ring:
            let inner = r[1]
            let k = inner[0].x, m = inner[0].y
            return [Wing.auto(0, 0, L, m), Wing.auto(0, W - m, L, W), Wing.auto(0, 0, k, W), Wing.auto(L - k, 0, L, W)]
        }
    }

    var edges: [(a: V2, b: V2, ring: Int)] {
        var out: [(V2, V2, Int)] = []
        for (ri, r) in rings.enumerated() {
            for i in r.indices { out.append((r[i], r[(i + 1) % r.count], ri)) }
        }
        return out
    }

    var segments: [WallSegment] {
        var out: [WallSegment] = []
        for (ei, e) in edges.enumerated() {
            let cfg = edgeConfigs[ei] ?? EdgeConfig()
            let fr = [0.0] + cfg.splits + [1.0]
            for k in 0..<(fr.count - 1) {
                let a = e.a + (e.b - e.a) * fr[k], b = e.a + (e.b - e.a) * fr[k + 1]
                let m = (k < cfg.materials.count ? cfg.materials[k] : nil) ?? defaultMaterial
                out.append(WallSegment(id: "e\(ei)-\(k)", edge: ei, sub: k, a: a, b: b, material: m))
            }
        }
        return out
    }

    var usedMaterials: [WallMaterial] {
        let set = Set(segments.map(\.material) + partitions.map(\.material))
        return WallMaterial.allCases.filter { set.contains($0) }
    }

    // MARK: - Редактирование

    func setMaterial(_ seg: WallSegment, _ m: WallMaterial) {
        var cfg = edgeConfigs[seg.edge] ?? EdgeConfig()
        while cfg.materials.count < cfg.splits.count + 1 { cfg.materials.append(nil) }
        cfg.materials[seg.sub] = m
        edgeConfigs[seg.edge] = cfg
    }

    /// Разделить участок стены на расстоянии dist (м) от его начала
    func split(_ seg: WallSegment, at dist: Double) {
        let e = edges[seg.edge]
        let elen = (e.b - e.a).len
        guard elen > 0, dist > 0.2, dist < seg.length - 0.2 else { return }
        var cfg = edgeConfigs[seg.edge] ?? EdgeConfig()
        while cfg.materials.count < cfg.splits.count + 1 { cfg.materials.append(nil) }
        let fr = [0.0] + cfg.splits + [1.0]
        let f = fr[seg.sub] + dist / elen
        cfg.splits.insert(f, at: seg.sub)
        cfg.materials.insert(cfg.materials[seg.sub], at: seg.sub)
        edgeConfigs[seg.edge] = cfg
    }

    func mergeEdge(_ edge: Int) { edgeConfigs[edge] = nil }

    func setAllExterior(_ m: WallMaterial) { edgeConfigs = [:]; defaultMaterial = m }
}
