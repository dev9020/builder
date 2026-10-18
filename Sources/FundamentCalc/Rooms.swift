import Foundation

/// Назначение помещения
enum RoomType: String, CaseIterable, Identifiable {
    case kitchenLiving, living, kitchen, bedroom, master, office, bath, wc, hall, corridor, boiler, storage, wardrobe, sauna, showerRoom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .kitchenLiving: return "Кухня-гостиная"
        case .living: return "Гостиная"
        case .kitchen: return "Кухня"
        case .bedroom: return "Спальня"
        case .office: return "Кабинет"
        case .bath: return "Санузел"
        case .wc: return "Гостевой с/у"
        case .hall: return "Прихожая"
        case .corridor: return "Коридор / холл"
        case .boiler: return "Котельная / техпомещение"
        case .storage: return "Кладовая"
        case .master: return "Мастер-спальня"
        case .wardrobe: return "Гардеробная"
        case .sauna: return "Сауна (парная)"
        case .showerRoom: return "Душевая с с/у"
        }
    }
    var short: String {
        switch self {
        case .boiler: return "Котельная"
        case .corridor: return "Холл"
        case .sauna: return "Сауна"
        case .showerRoom: return "Душевая"
        default: return title
        }
    }
    var wet: Bool { [.bath, .wc, .kitchen, .kitchenLiving, .boiler, .sauna, .showerRoom].contains(self) }
}

/// Пометка назначения комнаты: точка внутри комнаты → тип (задаётся вручную или в проекте)
struct RoomMark: Equatable {
    var at: V2
    var type: RoomType
}

/// Проём, примыкающий к комнате
struct RoomOpening {
    let o: Opening
    let center: V2
    let dir: V2              // вдоль стены
    let exterior: Bool
    var isDoor: Bool { o.kind.isDoor }
}

struct Room: Identifiable {
    let id: Int
    var type: RoomType = .bedroom
    var area = 0.0
    var seed = V2(0, 0)                         // точка внутри комнаты
    var lo = V2(0, 0), hi = V2(0, 0)            // наибольший прямоугольник внутри (чистовые грани)
    var bbLo = V2(0, 0), bbHi = V2(0, 0)
    var openings: [RoomOpening] = []
    var cells: [(Int, Int)] = []
    var hasExtDoor: Bool { openings.contains { $0.exterior && $0.o.kind.isDoor } }
    var windows: [RoomOpening] { openings.filter { !$0.isDoor && $0.exterior } }
    var w: Double { hi.x - lo.x }
    var h: Double { hi.y - lo.y }
    var name: String { type.title }
}

/// Растровая сетка дома: стены и комнаты
struct RoomGrid {
    let res = 0.05
    var lo = V2(0, 0)
    var nx = 0, ny = 0
    var label: [Int] = []           // −1 — стена/снаружи, ≥ 0 — номер комнаты
    func at(_ p: V2) -> Int {
        let i = Int(((p.x - lo.x) / res).rounded(.down)), j = Int(((p.y - lo.y) / res).rounded(.down))
        guard i >= 0, j >= 0, i < nx, j < ny else { return -1 }
        return label[j * nx + i]
    }
    func center(_ i: Int, _ j: Int) -> V2 { lo + V2((Double(i) + 0.5) * res, (Double(j) + 0.5) * res) }
}

enum Rooms {
    /// Поиск помещений по стенам и перегородкам (растровая заливка, шаг 5 см)
    static func detect(_ p: Project) -> (rooms: [Room], grid: RoomGrid) {
        let rings = p.rings
        let (blo, bhi) = Geo.bbox(rings)
        var g = RoomGrid()
        g.lo = blo - V2(0.3, 0.3)
        g.nx = Int(((bhi.x - blo.x + 0.6) / g.res).rounded(.up))
        g.ny = Int(((bhi.y - blo.y + 0.6) / g.res).rounded(.up))
        let D = p.studDepth + 0.05
        let edges = p.edges
        let parts = p.partitions.filter { $0.length > 0.3 }
        var free = [Bool](repeating: false, count: g.nx * g.ny)
        for j in 0..<g.ny {
            for i in 0..<g.nx {
                let c = g.center(i, j)
                guard Geo.contains(c, rings) else { continue }
                if edges.contains(where: { Geo.distToSegment(c, $0.a, $0.b) < D / 2 }) { continue }
                if parts.contains(where: { Geo.distToSegment(c, $0.a, $0.b) < $0.thickness / 2 + 0.01 }) { continue }
                free[j * g.nx + i] = true
            }
        }
        g.label = [Int](repeating: -1, count: g.nx * g.ny)
        var rooms: [Room] = []
        for start in 0..<free.count where free[start] && g.label[start] < 0 {
            let id = rooms.count
            var stack = [start]
            g.label[start] = id
            var cells: [(Int, Int)] = []
            while let k = stack.popLast() {
                let i = k % g.nx, j = k / g.nx
                cells.append((i, j))
                for (di, dj) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let ii = i + di, jj = j + dj
                    guard ii >= 0, jj >= 0, ii < g.nx, jj < g.ny else { continue }
                    let kk = jj * g.nx + ii
                    if free[kk] && g.label[kk] < 0 { g.label[kk] = id; stack.append(kk) }
                }
            }
            var r = Room(id: id)
            r.cells = cells
            r.area = Double(cells.count) * g.res * g.res
            rooms.append(r)
        }
        // мелкие ниши (< 1 м²) — не комнаты
        var keep: [Int: Int] = [:]
        var out: [Room] = []
        for r in rooms where r.area >= 1.0 { keep[r.id] = out.count; out.append(Room(id: out.count, area: r.area, cells: r.cells)) }
        for k in g.label.indices where g.label[k] >= 0 { g.label[k] = keep[g.label[k]] ?? -1 }
        for idx in out.indices { fill(&out[idx], g) }
        attachOpenings(p, &out, g)
        classify(p, &out)
        return (out, g)
    }

    /// Габарит, наибольший вписанный прямоугольник, точка внутри
    static func fill(_ r: inout Room, _ g: RoomGrid) {
        let i0 = r.cells.map(\.0).min()!, i1 = r.cells.map(\.0).max()!, j0 = r.cells.map(\.1).min()!, j1 = r.cells.map(\.1).max()!
        let W = i1 - i0 + 1, H = j1 - j0 + 1
        var m = [Bool](repeating: false, count: W * H)
        for (i, j) in r.cells { m[(j - j0) * W + (i - i0)] = true }
        var heights = [Int](repeating: 0, count: W)
        var best = (area: 0, i: 0, j: 0, w: 0, h: 0)
        for j in 0..<H {
            for i in 0..<W { heights[i] = m[j * W + i] ? heights[i] + 1 : 0 }
            var stack: [Int] = []
            for i in 0...W {
                let hcur = i < W ? heights[i] : 0
                while let t = stack.last, heights[t] > hcur {
                    stack.removeLast()
                    let left = stack.last.map { $0 + 1 } ?? 0
                    let a = heights[t] * (i - left)
                    if a > best.area { best = (a, left, j - heights[t] + 1, i - left, heights[t]) }
                }
                stack.append(i)
            }
        }
        r.lo = g.lo + V2(Double(i0 + best.i) * g.res, Double(j0 + best.j) * g.res)
        r.hi = r.lo + V2(Double(best.w) * g.res, Double(best.h) * g.res)
        r.bbLo = g.lo + V2(Double(i0) * g.res, Double(j0) * g.res)
        r.bbHi = g.lo + V2(Double(i1 + 1) * g.res, Double(j1 + 1) * g.res)
        r.seed = (r.lo + r.hi) / 2
    }

    static func attachOpenings(_ p: Project, _ rooms: inout [Room], _ g: RoomGrid) {
        let D = p.studDepth + 0.05
        for o in p.validOpenings {
            guard let c = p.openingCenter(o), let l = p.hostLine(o.host) else { continue }
            let d = (l.b - l.a).unit, n = V2(-d.y, d.x)
            var ext = false, t = 0.15
            if case .edge = o.host { ext = true; t = D } else if let pt = p.partitions.first(where: { $0.id == { if case .partition(let id) = o.host { return id }; return UUID() }() }) { t = pt.thickness }
            for s in [1.0, -1.0] {
                let q = c + n * s * (t / 2 + 0.12)
                let id = g.at(q)
                if id >= 0 && id < rooms.count { rooms[id].openings.append(RoomOpening(o: o, center: c, dir: d, exterior: ext)) }
            }
        }
    }

    /// Назначение по эвристикам; ручные пометки важнее
    static func classify(_ p: Project, _ rooms: inout [Room]) {
        guard !rooms.isEmpty else { return }
        var set = Set<Int>()
        for m in p.roomMarks {
            if let i = rooms.firstIndex(where: { contains($0, m.at) }) { rooms[i].type = m.type; set.insert(i) }
        }
        let largest = rooms.indices.max { rooms[$0].area < rooms[$1].area }!
        for i in rooms.indices where !set.contains(i) {
            let r = rooms[i]
            let wins = r.windows
            let small = r.area <= 8.5
            let narrow = min(r.w, r.h) <= 1.7 && max(r.w, r.h) / max(min(r.w, r.h), 0.1) >= 2.3
            let highWin = wins.contains { $0.o.sill >= 1.35 && $0.o.height <= 0.7 }
            let techWin = wins.contains { $0.o.sill >= 1.1 && $0.o.height <= 0.85 && $0.o.width <= 0.85 } && !highWin
            let doors = r.openings.filter(\.isDoor).count
            let fillRatio = r.area / max((r.bbHi.x - r.bbLo.x) * (r.bbHi.y - r.bbLo.y), 0.01)
            var t: RoomType
            if i == largest && r.area >= 18 { t = .kitchenLiving }
            else if r.hasExtDoor && r.area <= 18 && !wins.contains(where: { $0.o.kind == .panoramic }) { t = .hall }
            else if (doors >= 3 && r.area > 6) || fillRatio < 0.55 { t = .corridor }
            else if r.area <= 10.5 && techWin { t = .boiler }
            else if r.area <= 11 && highWin { t = r.area < 2.6 ? .wc : .bath }
            else if small && techWin { t = .boiler }
            else if narrow { t = .corridor }
            else if small && wins.isEmpty { t = r.area < 4 ? .storage : .bath }
            else if wins.isEmpty { t = .corridor }
            else if r.area < 8 { t = .office }
            else { t = .bedroom }
            rooms[i].type = t
        }
        // санузел обязателен: если не нашёлся — самая маленькая комната без панорамных окон
        if !rooms.contains(where: { $0.type == .bath }) {
            if let i = rooms.indices.filter({ !set.contains($0) && rooms[$0].type != .kitchenLiving && rooms[$0].type != .hall && rooms[$0].area >= 3 })
                .min(by: { rooms[$0].area < rooms[$1].area }) { rooms[i].type = .bath }
        }
        // кухня-гостиная обязательна
        if !rooms.contains(where: { $0.type == .kitchenLiving || $0.type == .kitchen }) && !set.contains(largest) { rooms[largest].type = .kitchenLiving }
    }

    static func contains(_ r: Room, _ v: V2) -> Bool {
        v.x >= r.bbLo.x && v.x <= r.bbHi.x && v.y >= r.bbLo.y && v.y <= r.bbHi.y && containsCell(r, v)
    }
    static func containsCell(_ r: Room, _ v: V2) -> Bool {
        let i0 = r.cells.map(\.0).min()!, j0 = r.cells.map(\.1).min()!
        let i = i0 + Int(((v.x - r.bbLo.x) / 0.05).rounded(.down)), j = j0 + Int(((v.y - r.bbLo.y) / 0.05).rounded(.down))
        return r.cells.contains { $0.0 == i && $0.1 == j }
    }
}
