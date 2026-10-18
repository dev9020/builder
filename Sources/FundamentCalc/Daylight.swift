import Foundation

/// Естественный свет в помещениях.
/// • Жилые комнаты и кухня: площадь световых проёмов ≥ 1/8 площади пола (СП 55.13330.2016, разд. 9).
/// • Коридоры, холлы и прихожие: по возможности — своё окно; длинный проход не должен быть тёмным
///   дальше ≈ 4 м от ближайшего остекления.
/// • Угловые комнаты: на глухую наружную стену — узкое высокое окно (второй источник света и сквозное проветривание).
/// Окно ставится только туда, где есть свободный участок наружной стены, и встаёт на сетку стоек 625 мм.
enum Daylight {
    /// Узкое высокое окно: блок 600×1800, черновой проём 640×1850; верх — на одной отметке с обычными окнами
    static let narrow = (w: 0.64, h: 1.85, sill: 0.45)
    static let regular = (w: 1.24, h: 1.45, sill: 0.85)
    static let minRatio = 1.0 / 8
    static let darkReach = 4.0

    struct Change {
        let room: String
        let text: String
    }

    /// Свободный участок наружной стены у комнаты: стена (edge), диапазон по оси стены
    struct Run {
        let edge: Int
        let u0: Double, u1: Double
        var len: Double { u1 - u0 }
        var mid: Double { (u0 + u1) / 2 }
    }

    static func glazing(_ r: Room) -> [RoomOpening] { r.openings.filter { $0.exterior && $0.o.kind.isGlazed } }
    static func glazedArea(_ r: Room) -> Double { glazing(r).reduce(0) { $0 + $1.o.width * $1.o.height } }

    /// Участки наружных стен, к которым примыкает комната, без существующих проёмов (с запасом под стойки)
    static func freeRuns(_ p: Project, _ room: Room, _ g: RoomGrid) -> [Run] {
        let D = p.studDepth
        let rings = p.rings
        var out: [Run] = []
        for (ei, e) in p.edges.enumerated() {
            let L = (e.b - e.a).len
            guard L > 1 else { continue }
            let d = (e.b - e.a) / L
            var n = V2(-d.y, d.x)
            if !Geo.contains((e.a + e.b) / 2 + n * (D / 2 + 0.2), rings) { n = -n }
            // где за стеной — эта комната
            var adj: [(Double, Double)] = []
            var start: Double? = nil
            var u = 0.0
            while u <= L + 1e-9 {
                let on = g.at(e.a + d * u + n * (D / 2 + 0.12)) == room.id
                if on, start == nil { start = u }
                if !on, let s = start { adj.append((s, u)); start = nil }
                u += 0.05
            }
            if let s = start { adj.append((s, L)) }
            // минус проёмы на этой стене (с простенком под стойки)
            let blocked = p.validOpenings.filter { $0.host == .edge(ei) }.map { ($0.pos - $0.width / 2 - 0.3, $0.pos + $0.width / 2 + 0.3) }
            for (a0, a1) in adj {
                var parts = [(a0 + 0.1, a1 - 0.1)]
                for (b0, b1) in blocked {
                    parts = parts.flatMap { (s0, s1) -> [(Double, Double)] in
                        guard b1 > s0 && b0 < s1 else { return [(s0, s1)] }
                        return [(s0, b0), (b1, s1)].filter { $0.1 - $0.0 > 0.05 }
                    }
                }
                out += parts.filter { $0.1 - $0.0 > 0.05 }.map { Run(edge: ei, u0: $0.0, u1: $0.1) }
            }
        }
        return out
    }

    /// Стойки примыкания перегородок на стене (центры, по оси стены)
    static func junctionStuds(_ p: Project, edge: Int) -> [Double] {
        let e = p.edges[edge]
        var out: [Double] = []
        for (u, t) in FrameGen.junctions(p, e.a, e.b, except: nil) {
            let h = t / 2 + 0.025
            out += [u - h, u + h]
        }
        return out
    }

    /// Положение центра окна ширины w в участке так, чтобы крайняя стойка проёма была рядовой:
    /// левая — на сетке 625 мм (от наружного угла) или любая — на стойке примыкания перегородки. Ближе к середине участка.
    /// nil — так не встаёт
    static func place(_ run: Run, w: Double, D: Double, studs: [Double] = []) -> Double? {
        guard run.len >= w else { return nil }
        let origin = -D / 2
        let lo = run.u0 - 0.05, hi = run.u1 + 0.05 - w
        var cand: [Double] = []
        var k = ((lo - 0.075 - origin) / Module.step).rounded(.down)
        while origin + k * Module.step + 0.075 <= hi + 1e-9 { cand.append(origin + k * Module.step + 0.075); k += 1 }
        for s in studs { cand += [s + 0.075, s - 0.075 - w] }
        return cand.filter { $0 >= lo - 1e-9 && $0 <= hi + 1e-9 }.map { $0 + w / 2 }.min { abs($0 - run.mid) < abs($1 - run.mid) }
    }

    /// Добавить окна в тёмные помещения; возвращает список изменений
    @discardableResult
    static func improve(_ p: Project) -> [Change] {
        var changes: [Change] = []
        let D = p.studDepth
        for _ in 0..<3 {
            let (rooms, g) = Rooms.detect(p)
            var added = false
            func add(_ room: Room, _ run: Run, _ size: (w: Double, h: Double, sill: Double), _ why: String) -> Bool {
                guard run.len >= size.w else { return false }
                let pos = place(run, w: size.w, D: D, studs: junctionStuds(p, edge: run.edge)) ?? run.mid
                p.openings.append(Opening(host: .edge(run.edge), pos: pos, kind: .window, width: size.w, height: size.h, sill: size.sill))
                // назначение комнаты не должно поменяться из-за нового окна
                if !p.roomMarks.contains(where: { Rooms.contains(room, $0.at) }) { p.roomMarks.append(RoomMark(at: room.seed, type: room.type)) }
                changes.append(Change(room: room.name, text: why))
                return true
            }
            for room in rooms {
                let runs = freeRuns(p, room, g)
                guard !runs.isEmpty else { continue }
                let glz = glazing(room)
                let e = p.edges
                func point(_ r: Run) -> V2 { e[r.edge].a + (e[r.edge].b - e[r.edge].a).unit * r.mid }
                switch room.type {
                case .corridor, .hall:
                    // самый тёмный участок прохода — дальше всего от остекления
                    let cand = runs.filter { $0.len >= narrow.w }
                        .map { r in (r, glz.map { ($0.center - point(r)).len }.min() ?? .infinity) }
                        .filter { $0.1 >= darkReach }
                        .max { a, b in
                            // сначала — где окно встаёт на сетку стоек, затем — самый тёмный
                            let ga = place(a.0, w: narrow.w, D: D, studs: junctionStuds(p, edge: a.0.edge)) != nil
                            let gb = place(b.0, w: narrow.w, D: D, studs: junctionStuds(p, edge: b.0.edge)) != nil
                            return ga != gb ? !ga : a.1 < b.1
                        }
                    if let (r, dist) = cand {
                        added = add(room, r, narrow, dist.isFinite ? "узкое окно 600×1800 в конце прохода (до остекления было \(fmt(dist, 1)) м)" : "узкое окно 600×1800 — своё окно вместо тёмного помещения") || added
                    }
                case .bedroom, .office, .living, .kitchen, .kitchenLiving:
                    let area = room.area
                    if glazedArea(room) < area * minRatio {
                        let r = runs.max { $0.len < $1.len }!
                        let size = r.len >= regular.w ? regular : narrow
                        if r.len >= size.w {
                            added = add(room, r, size, "окно \(size.w > 1 ? "1200×1400" : "600×1800"): остекление было \(fmt(glazedArea(room), 1)) м² < 1/8 пола (\(fmt(area / 8, 1)) м²)") || added
                        }
                    } else if [.bedroom, .office, .living].contains(room.type), area >= 10,
                              Set(glz.compactMap { o -> Int? in if case .edge(let i) = o.o.host { return i }; return nil }).count == 1 {
                        // угловая комната со светом с одной стороны: на глухую наружную стену ≥ 2 м — узкое окно
                        let litEdges = Set(glz.compactMap { o -> Int? in if case .edge(let i) = o.o.host { return i }; return nil })
                        let byEdge = Dictionary(grouping: runs, by: \.edge).filter { !litEdges.contains($0.key) }
                        if let (_, rs) = byEdge.filter({ $0.value.reduce(0) { $0 + $1.len } >= 2.0 - 0.3 }).max(by: { $0.value.reduce(0) { $0 + $1.len } < $1.value.reduce(0) { $0 + $1.len } }),
                           let r = rs.filter({ $0.len >= narrow.w }).max(by: { a, b in
                               let ga = place(a, w: narrow.w, D: D, studs: junctionStuds(p, edge: a.edge)) != nil
                               let gb = place(b, w: narrow.w, D: D, studs: junctionStuds(p, edge: b.edge)) != nil
                               return ga != gb ? !ga : a.len < b.len }) {
                            added = add(room, r, narrow, "узкое окно 600×1800 на глухую наружную стену угловой комнаты — свет с двух сторон и сквозное проветривание") || added
                        }
                    }
                default: break
                }
            }
            if !added { break }
        }
        return changes
    }

    /// Помещения, где света по-прежнему мало (для проверки проекта)
    static func issues(_ p: Project) -> [String] {
        let (rooms, _) = Rooms.detect(p)
        var out: [String] = []
        for r in rooms {
            switch r.type {
            case .bedroom, .office, .living, .kitchen, .kitchenLiving:
                if glazedArea(r) < r.area * minRatio { out.append("\(r.name) \(fmt(r.area, 1)) м²: окна \(fmt(glazedArea(r), 1)) м² < 1/8 пола") }
            case .corridor, .hall:
                if glazing(r).isEmpty { out.append("\(r.name) \(fmt(r.area, 1)) м²: без естественного света") }
            default: break
            }
        }
        return out
    }
}
