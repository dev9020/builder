import Foundation

/// Очистное сооружение
enum SepticType: String, CaseIterable, Identifiable {
    case bio, septic3, tank
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bio: return "Станция биологической очистки (ЛОС) на 4–5 человек"
        case .septic3: return "Септик 3-камерный 3 м³ + инфильтратор (почвенная доочистка)"
        case .tank: return "Накопительная ёмкость 8 м³ (откачка ассенизатором)"
        }
    }
    var short: String { self == .bio ? "станция биоочистки" : self == .septic3 ? "септик с инфильтратором" : "накопительная ёмкость" }
    /// Рекомендуемое расстояние до питьевой скважины, м
    var wellDistance: Double { self == .tank ? 20 : self == .bio ? 30 : 50 }
    var price: Double { self == .bio ? 135000 : self == .septic3 ? 90000 : 65000 }
    /// Размер в плане (для схем), м
    var size: V2 { self == .tank ? V2(3.2, 1.6) : self == .bio ? V2(1.2, 1.8) : V2(2.4, 1.2) }
}

enum FurnKind { case bed, nightstand, wardrobe, sofa, table, desk, shelf, kitchen, fridge, toilet, sink, shower, bathtub, washer, boiler, heater, tank, collector, bench, filter }

struct Furniture: Identifiable {
    let id = UUID()
    let name: String
    let kind: FurnKind
    var lo: V2, hi: V2
    var room: Int
    var wall: V2                // середина задней стороны (у стены)
    var normal: V2              // от стены в комнату
}

enum PointKind: String { case cold = "ХВ", hot = "ГВ", sewer50 = "К Ø50", sewer110 = "К Ø110" }

/// Точка подключения у прибора
struct WaterPoint: Identifiable {
    let id = UUID()
    let kind: PointKind
    let pos: V2
    let height: Double          // от чистого пола, м
    let fixture: String
    let room: String
    var number = 0
}

struct Pipe {
    enum Kind { case cold, hot, sewer }
    let kind: Kind
    let pts: [V2]
    let d: Int
    var length: Double { zip(pts, pts.dropFirst()).reduce(0) { $0 + ($1.1 - $1.0).len } }
}

/// Мебель, сантехника, разводка и наружные сети дома
struct HouseLayout {
    var rooms: [Room] = []
    var grid = RoomGrid()
    var furniture: [Furniture] = []
    var points: [WaterPoint] = []
    var pipes: [Pipe] = []
    var collector = V2(0, 0)
    var collectorRoom = ""
    var entry = V2(0, 0), entryWall = "", entryOffset = 0.0       // ввод воды
    var entryOut = V2(0, 1)                                        // наружу от стены ввода
    var outlet = V2(0, 0), outletWall = "", outletOffset = 0.0    // выпуск канализации
    var outletDepth = 0.6, maxDrop = 0.0, startDepth = 0.3
    // участок и наружные сети (координаты дома)
    var plotLo = V2(0, 0), plotHi = V2(0, 0)
    var well = V2(0, 0), septic = V2(0, 0)
    var waterLen = 0.0, waterDepth = 1.5, waterHeated = false
    var sewerLen = 0.0, septicInlet = 0.8, sewerInsulate = false, revisionWells = 0
    var dfn = 1.4
    var wellToSeptic = 0.0, houseToSeptic = 0.0, houseToWell = 0.0
    var ffl = 0.5                                                  // чистый пол над землёй, м
    var coldLen: Double { pipes.filter { $0.kind == .cold }.reduce(0) { $0 + $1.length } }
    var hotLen: Double { pipes.filter { $0.kind == .hot }.reduce(0) { $0 + $1.length } }
    func sewerLen(_ d: Int) -> Double { pipes.filter { $0.kind == .sewer && $0.d == d }.reduce(0) { $0 + $1.length } }
    var fixtures: [Furniture] { furniture.filter { [.toilet, .sink, .shower, .bathtub, .washer].contains($0.kind) || ($0.kind == .kitchen) } }

    static func make(_ p: Project, _ r: CalcResults, _ F: Framing) -> HouseLayout {
        var L = HouseLayout()
        let det = Rooms.detect(p)
        L.rooms = det.rooms; L.grid = det.grid
        let hasBoiler = L.rooms.contains { $0.type == .boiler }
        var washerPlaced = false, heaterPlaced = false
        let order = L.rooms.indices.sorted { a, b in
            let pr: [RoomType] = [.boiler, .bath, .wc, .kitchenLiving, .kitchen]
            return (pr.firstIndex(of: L.rooms[a].type) ?? 9) < (pr.firstIndex(of: L.rooms[b].type) ?? 9)
        }
        for i in order {
            var pl = Placer(room: L.rooms[i])
            pl.furnish(p, hasBoiler: hasBoiler, washerPlaced: &washerPlaced, heaterPlaced: &heaterPlaced)
            L.furniture += pl.items
        }
        L.makePoints(p)
        L.site(p, r)
        L.route(p, r, F)
        return L
    }

    // MARK: - Точки

    mutating func makePoints(_ p: Project) {
        var pts: [WaterPoint] = []
        func room(_ f: Furniture) -> String { rooms.indices.contains(f.room) ? rooms[f.room].name : "" }
        for f in furniture {
            let along = V2(-f.normal.y, f.normal.x)
            let w = f.wall + f.normal * 0.05
            switch f.kind {
            case .toilet:
                pts += [WaterPoint(kind: .cold, pos: w + along * 0.2, height: 0.2, fixture: "Унитаз (инсталляция или напольный)", room: room(f)),
                        WaterPoint(kind: .sewer110, pos: w + f.normal * 0.15, height: 0.0, fixture: "Унитаз", room: room(f))]
            case .sink:
                pts += [WaterPoint(kind: .cold, pos: w + along * 0.08, height: 0.55, fixture: "Раковина", room: room(f)),
                        WaterPoint(kind: .hot, pos: w - along * 0.08, height: 0.55, fixture: "Раковина", room: room(f)),
                        WaterPoint(kind: .sewer50, pos: w, height: 0.45, fixture: "Раковина", room: room(f))]
            case .shower:
                pts += [WaterPoint(kind: .cold, pos: w + along * 0.08, height: 1.05, fixture: "Душ (смеситель)", room: room(f)),
                        WaterPoint(kind: .hot, pos: w - along * 0.08, height: 1.05, fixture: "Душ (смеситель)", room: room(f)),
                        WaterPoint(kind: .sewer50, pos: (f.lo + f.hi) / 2, height: 0.0, fixture: "Душ (трап/поддон)", room: room(f))]
            case .bathtub:
                pts += [WaterPoint(kind: .cold, pos: w + along * 0.08, height: 0.8, fixture: "Ванна (смеситель)", room: room(f)),
                        WaterPoint(kind: .hot, pos: w - along * 0.08, height: 0.8, fixture: "Ванна (смеситель)", room: room(f)),
                        WaterPoint(kind: .sewer50, pos: w + along * 0.6 + f.normal * 0.2, height: 0.05, fixture: "Ванна (сифон)", room: room(f))]
            case .washer:
                pts += [WaterPoint(kind: .cold, pos: w + along * 0.15, height: 0.7, fixture: "Стиральная машина (кран)", room: room(f)),
                        WaterPoint(kind: .sewer50, pos: w - along * 0.15, height: 0.6, fixture: "Стиральная машина (сифон)", room: room(f))]
            case .kitchen:
                // мойка — примерно на трети гарнитура от холодильника, ПММ — рядом
                let len = max(f.hi.x - f.lo.x, f.hi.y - f.lo.y)
                let dir = abs(f.normal.x) > 0.5 ? V2(0, 1) : V2(1, 0)
                let start = abs(f.normal.x) > 0.5 ? V2(f.wall.x, f.lo.y) : V2(f.lo.x, f.wall.y)
                let s = start + dir * (len * 0.5) + f.normal * 0.05
                pts += [WaterPoint(kind: .cold, pos: s + dir * 0.08, height: 0.5, fixture: "Мойка кухонная", room: room(f)),
                        WaterPoint(kind: .hot, pos: s - dir * 0.08, height: 0.5, fixture: "Мойка кухонная", room: room(f)),
                        WaterPoint(kind: .sewer50, pos: s, height: 0.5, fixture: "Мойка кухонная", room: room(f)),
                        WaterPoint(kind: .cold, pos: s + dir * 0.6, height: 0.4, fixture: "Посудомоечная машина", room: room(f))]
            case .boiler:
                pts.append(WaterPoint(kind: .cold, pos: w, height: 1.0, fixture: "Котёл (подпитка)", room: room(f)))
            default: break
            }
        }
        for i in pts.indices { pts[i].number = i + 1 }
        points = pts
    }

    // MARK: - Участок: скважина и септик

    mutating func site(_ p: Project, _ r: CalcResults) {
        let (lo, hi) = Geo.bbox(p.rings)
        let D = p.studDepth
        dfn = max(r.strip.dfn, 0.8)
        // септик — в палисаднике у проезда (подъезд ассенизатора), скважина — в глубине участка
        let front = 9.5, side = 3.0
        let sz = p.septic.size
        let toiletX = furniture.first { $0.kind == .toilet }.map { $0.wall.x } ?? (lo.x + hi.x) / 2
        let septicLeft = toiletX < (lo.x + hi.x) / 2
        septic = V2(septicLeft ? lo.x + sz.x / 2 + 0.5 : hi.x - sz.x / 2 - 0.5, lo.y - D / 2 - 5.0 - sz.y / 2 - 0.3)
        plotLo = V2(lo.x - side - (septicLeft ? 0 : 0), lo.y - front)
        let wellX = septicLeft ? hi.x + side - 1.5 : lo.x - side + 1.5
        // скважина: не ближе требуемого к очистному сооружению, ≥ 2 м от дома
        var back = 5.0
        while true {
            let w = V2(wellX, hi.y + back - 1.5)
            if (w - septic).len >= p.septic.wellDistance || back > 60 { well = w; break }
            back += 0.5
        }
        plotHi = V2(hi.x + side, hi.y + back)
        wellToSeptic = (well - septic).len
        houseToSeptic = septic.y + sz.y / 2 <= lo.y ? lo.y - D / 2 - (septic.y + sz.y / 2) : 0
        houseToWell = max(0, well.y - hi.y - D / 2)
    }

    // MARK: - Разводка

    mutating func route(_ p: Project, _ r: CalcResults, _ F: Framing) {
        let D = p.studDepth
        let ext = p.edges.filter { $0.ring == 0 }
        func nearestExt(to target: V2, from v: V2) -> (V2, Int) {
            var best = (V2(0, 0), 0), bestS = Double.greatestFiniteMagnitude
            for (k, e) in p.edges.enumerated() where e.ring == 0 {
                let q = Geo.project(v, e.a, e.b)
                let d = (e.b - e.a).unit
                let out = V2(d.y, -d.x)
                guard dot2(target - q, out) > 0 else { continue }
                let s = (q - v).len + (target - q).len * 0.4
                if s < bestS { bestS = s; best = (q, k) }
            }
            return best
        }
        _ = ext
        func wallName(_ edge: Int, _ q: V2) -> (String, Double) {
            guard let si = p.segments.firstIndex(where: { $0.edge == edge && Geo.distToSegment(q, $0.a, $0.b) < 0.01 }) else { return ("Н", 0) }
            return ("Н\(si + 1)", (q - p.segments[si].a).len)
        }
        // коллектор
        let col = furniture.first { $0.kind == .collector }
        collector = col.map { $0.wall + $0.normal * 0.1 } ?? (points.first?.pos ?? V2(0, 0))
        collectorRoom = col.map { rooms[$0.room].name } ?? ""
        // ввод воды — со стороны скважины
        let (eq, ek) = nearestExt(to: well, from: collector)
        entry = eq
        (entryWall, entryOffset) = wallName(ek, eq)
        let inward: (Int) -> V2 = { k in let e = p.edges[k]; let d = (e.b - e.a).unit; return V2(-d.y, d.x) }
        entryOut = -inward(ek)
        let entryIn = eq + inward(ek) * (D / 2 + 0.15)
        pipes.append(Pipe(kind: .cold, pts: [entryIn, V2(collector.x, entryIn.y), collector], d: 25))
        // вода: лучи от коллектора
        for pt in points where pt.kind == .cold || pt.kind == .hot {
            let off = pt.kind == .hot ? V2(0.06, 0.06) : V2(0, 0)
            let a = collector + off
            pipes.append(Pipe(kind: pt.kind == .cold ? .cold : .hot, pts: [a, V2(pt.pos.x + off.x, a.y), pt.pos + off], d: 16))
        }
        // канализация: выпуск — в сторону септика, ближе к унитазам
        let toilets = points.filter { $0.kind == .sewer110 }
        let anchor = toilets.first?.pos ?? points.first { $0.kind == .sewer50 }?.pos ?? collector
        let (oq, ok) = nearestExt(to: septic, from: anchor)
        outlet = oq
        (outletWall, outletOffset) = wallName(ok, oq)
        let O = oq + inward(ok) * (D / 2 + 0.3)
        var mains: [[V2]] = []
        var drops: [Double] = []
        for t in toilets {
            let path = [t.pos, V2(t.pos.x, O.y), O]
            pipes.append(Pipe(kind: .sewer, pts: path, d: 110))
            mains.append(path)
            drops.append(Pipe(kind: .sewer, pts: path, d: 110).length * 0.02)
        }
        if mains.isEmpty { mains.append([O, O]) }
        for s in points where s.kind == .sewer50 {
            // ближайшая точка на магистралях
            var best = O, bd = Double.greatestFiniteMagnitude
            for m in mains {
                for (a, b) in zip(m, m.dropFirst()) {
                    let q = Geo.project(s.pos, a, b)
                    if (q - s.pos).len < bd { bd = (q - s.pos).len; best = q }
                }
            }
            let path = [s.pos, V2(best.x, s.pos.y), best]
            let br = Pipe(kind: .sewer, pts: path, d: 50)
            pipes.append(br)
            drops.append(br.length * 0.03 + (abs(best.x - O.x) + abs(best.y - O.y)) * 0.02)
        }
        maxDrop = drops.max() ?? 0
        // отметки: чистый пол над землёй, низ трубы у выпуска
        let joists = p.floorBase == .joists
        ffl = joists ? F.levelBase - 0.022 + p.floorBuildUp : F.levelBase + p.floorBuildUp
        switch p.floorBase {
        case .slab: startDepth = p.floorBuildUp + r.slab.t + 0.15
        case .joists: startDepth = p.floorBuildUp + (F.floors.first?.check.sec.wm ?? 0.2) + 0.15
        case .ground: startDepth = p.floorBuildUp + 0.3
        }
        outletDepth = max(0.5, startDepth + maxDrop - ffl)
        // наружные трассы
        let septicIn = septic + V2(0, septic.y < oq.y ? p.septic.size.y / 2 : -p.septic.size.y / 2)
        sewerLen = abs(septicIn.x - oq.x) + abs(septicIn.y - oq.y)
        revisionWells = (sewerLen > 15 ? 1 : 0) + (abs(septicIn.x - oq.x) > 0.3 ? 1 : 0)
        septicInlet = outletDepth + sewerLen * 0.02
        // СП 32: до 0.3 м выше глубины промерзания, но не менее 0.7 м до верха трубы
        sewerInsulate = outletDepth < max(0.81, dfn - 0.3)
        // траншея водопровода отходит от стены на 1.5 м, дальше — к скважине
        let e1 = eq + entryOut * 1.5
        waterLen = 1.5 + abs(well.x - e1.x) + abs(well.y - e1.y)
        // СП 31: на 0.5 м ниже глубины проникания нулевой температуры
        waterHeated = dfn + 0.5 > 2.0
        waterDepth = waterHeated ? 0.8 : dfn + 0.5
    }
}

/// Расстановка мебели в одной комнате: вдоль стен наибольшего прямоугольника, без перекрытия дверей
struct Placer {
    let room: Room
    var items: [Furniture] = []
    var busy: [(V2, V2)] = []
    var doorsBySide: [[(Double, Double)]] = Array(repeating: [], count: 4)
    var winBySide: [[(Double, Double, Bool)]] = Array(repeating: [], count: 4)   // (t0, t1, до пола)

    init(room: Room) {
        self.room = room
        for o in room.openings {
            guard let k = sideOf(o.center) else { continue }
            let s = side(k)
            let t = dot2(o.center - s.a, s.dir)
            let half = o.o.width / 2
            if o.isDoor {
                doorsBySide[k].append((t - half - 0.05, t + half + 0.05))
                // зона открывания двери внутрь
                let a = s.a + s.dir * (t - half - 0.05), b = s.a + s.dir * (t + half + 0.05) + s.n * min(0.95, o.o.width + 0.1)
                busy.append((pointwiseMin(a, b), pointwiseMax(a, b)))
            } else {
                winBySide[k].append((t - half, t + half, o.o.sill < 0.3))
            }
        }
    }

    func side(_ k: Int) -> (a: V2, dir: V2, n: V2, len: Double) {
        let lo = room.lo, hi = room.hi
        switch k {
        case 0: return (lo, V2(1, 0), V2(0, 1), hi.x - lo.x)
        case 1: return (V2(hi.x, lo.y), V2(0, 1), V2(-1, 0), hi.y - lo.y)
        case 2: return (hi, V2(-1, 0), V2(0, -1), hi.x - lo.x)
        default: return (V2(lo.x, hi.y), V2(0, -1), V2(1, 0), hi.y - lo.y)
        }
    }

    func sideOf(_ c: V2) -> Int? {
        let lo = room.lo, hi = room.hi
        let d = [abs(c.y - lo.y), abs(c.x - hi.x), abs(c.y - hi.y), abs(c.x - lo.x)]
        let inX: Bool = c.x > lo.x - 0.2 && c.x < hi.x + 0.2
        let inY: Bool = c.y > lo.y - 0.2 && c.y < hi.y + 0.2
        let inSpan: [Bool] = [inX, inY, inX, inY]
        guard let k = (0..<4).filter({ inSpan[$0] && d[$0] < 0.45 }).min(by: { d[$0] < d[$1] }) else { return nil }
        return k
    }

    /// Стороны: сначала глухие, потом длинные
    func sides(longFirst: Bool = true) -> [Int] {
        (0..<4).sorted { a, b in
            let sa = doorsBySide[a].count * 2 + winBySide[a].count, sb = doorsBySide[b].count * 2 + winBySide[b].count
            if sa != sb { return sa < sb }
            return longFirst ? side(a).len > side(b).len : side(a).len < side(b).len
        }
    }

    func hits(_ lo: V2, _ hi: V2) -> Bool {
        busy.contains { lo.x < $0.1.x - 0.01 && hi.x > $0.0.x + 0.01 && lo.y < $0.1.y - 0.01 && hi.y > $0.0.y + 0.01 }
    }

    @discardableResult
    mutating func place(_ name: String, _ kind: FurnKind, _ w: Double, _ d: Double, sides ks: [Int], tall: Bool, corner: Bool = false, keepFront: Double = 0) -> Furniture? {
        for k in ks {
            let s = side(k)
            guard s.len >= w + 0.02, d < (k % 2 == 0 ? room.h : room.w) - 0.3 else { continue }
            var ts = Array(stride(from: 0.0, through: s.len - w, by: 0.05))
            if corner { ts = [0, s.len - w] + ts }
            for t in ts {
                if tall && winBySide[k].contains(where: { t < $0.1 && t + w > $0.0 }) { continue }
                if !tall && winBySide[k].contains(where: { $0.2 && t < $0.1 && t + w > $0.0 }) { continue }
                let p0 = s.a + s.dir * t, p1 = p0 + s.dir * w + s.n * (d + keepFront)
                let lo = pointwiseMin(p0, p1), hi = pointwiseMax(p0, p1)
                guard !hits(lo, hi) else { continue }
                let q1 = p0 + s.dir * w + s.n * d
                let f = Furniture(name: name, kind: kind, lo: pointwiseMin(p0, q1), hi: pointwiseMax(p0, q1), room: room.id, wall: p0 + s.dir * (w / 2), normal: s.n)
                busy.append((lo, hi))
                items.append(f)
                return f
            }
        }
        return nil
    }

    /// Свободная расстановка (стол) — ближе к центру, с проходами
    mutating func placeFree(_ name: String, _ kind: FurnKind, _ w: Double, _ d: Double, clear: Double) {
        let c = (room.lo + room.hi) / 2
        var best: (V2, Double)? = nil
        var y = room.lo.y + clear
        while y + d < room.hi.y - clear + 1e-6 {
            var x = room.lo.x + clear
            while x + w < room.hi.x - clear + 1e-6 {
                let lo = V2(x, y), hi = V2(x + w, y + d)
                if !hits(lo - V2(clear, clear), hi + V2(clear, clear)) {
                    let dist = ((lo + hi) / 2 - c).len
                    if best == nil || dist < best!.1 { best = (lo, dist) }
                }
                x += 0.1
            }
            y += 0.1
        }
        guard let (lo, _) = best else { return }
        let hi = lo + V2(w, d)
        busy.append((lo, hi))
        items.append(Furniture(name: name, kind: kind, lo: lo, hi: hi, room: room.id, wall: (lo + hi) / 2, normal: V2(0, 1)))
    }

    mutating func furnish(_ p: Project, hasBoiler: Bool, washerPlaced: inout Bool, heaterPlaced: inout Bool) {
        let all = sides()
        let shortSide = min(room.w, room.h), longSide = max(room.w, room.h)
        switch room.type {
        case .bath:
            if longSide >= 2.3 && shortSide >= 1.6 { place("Ванна 1700×750", .bathtub, 1.7, 0.75, sides: sides(longFirst: false), tall: false, corner: true) }
            else { place("Душ 900×900", .shower, 0.9, 0.9, sides: all, tall: false, corner: true) }
            place("Унитаз", .toilet, 0.6, 0.7, sides: all, tall: false, keepFront: 0.5)
            place("Раковина 600", .sink, 0.6, 0.48, sides: all, tall: false, keepFront: 0.6)
            if !washerPlaced && !hasBoiler, place("Стиральная машина", .washer, 0.6, 0.6, sides: all, tall: false, keepFront: 0.5) != nil { washerPlaced = true }
            if !hasBoiler && !heaterPlaced {
                if place("Коллекторный шкаф ХВ/ГВ", .collector, 0.6, 0.15, sides: all, tall: true) != nil {}
                if p.floorHeating != .water, place("Водонагреватель 80 л", .heater, 0.5, 0.5, sides: all, tall: true) != nil { heaterPlaced = true }
            }
        case .wc:
            place("Унитаз", .toilet, 0.6, 0.7, sides: all, tall: false, keepFront: 0.5)
            place("Раковина 450", .sink, 0.45, 0.32, sides: all, tall: false, keepFront: 0.5)
        case .kitchenLiving, .kitchen:
            var placedK = false
            for len in [3.6, 3.0, 2.4, 1.8] where !placedK {
                if place("Кухня \(Int(len * 1000)) (мойка, плита, ПММ)", .kitchen, len, 0.6, sides: all, tall: false, keepFront: 0.9) != nil { placedK = true }
            }
            place("Холодильник", .fridge, 0.6, 0.65, sides: all, tall: true, corner: true, keepFront: 0.7)
            if room.type == .kitchenLiving {
                place("Диван 2200", .sofa, 2.2, 0.95, sides: sides(longFirst: true), tall: false, keepFront: 0.5)
                placeFree("Стол 1600×900 + 6 стульев", .table, 1.6, 0.9, clear: 0.7)
            } else {
                placeFree("Стол 1200×800", .table, 1.2, 0.8, clear: 0.6)
            }
            if !hasBoiler && !heaterPlaced && p.floorHeating == .water {
                place("Котёл настенный", .boiler, 0.45, 0.4, sides: all, tall: true)
            }
        case .living:
            place("Диван 2200", .sofa, 2.2, 0.95, sides: all, tall: false, keepFront: 0.5)
            placeFree("Журнальный стол", .table, 1.0, 0.6, clear: 0.5)
        case .bedroom:
            let bw = shortSide >= 3.0 ? 1.6 : shortSide >= 2.5 ? 1.4 : 0.9
            if place("Кровать \(Int(bw * 1000))×2000 + тумбы", .bed, bw + 0.9, 2.0, sides: all, tall: true, keepFront: 0.6) == nil {
                place("Кровать \(Int(bw * 1000))×2000", .bed, bw, 2.0, sides: all, tall: false, keepFront: 0.5)
            }
            place("Шкаф 1600", .wardrobe, 1.6, 0.6, sides: all, tall: true, corner: true, keepFront: 0.6) == nil ? place("Шкаф 1000", .wardrobe, 1.0, 0.6, sides: all, tall: true, corner: true, keepFront: 0.6) : nil
        case .office:
            place("Стол 1400", .desk, 1.4, 0.7, sides: (0..<4).sorted { winBySide[$0].count > winBySide[$1].count }, tall: false, keepFront: 0.7)
            place("Стеллаж", .shelf, 1.0, 0.4, sides: all, tall: true)
        case .hall:
            place("Шкаф для одежды 1200", .wardrobe, 1.2, 0.6, sides: all, tall: true, corner: true, keepFront: 0.6)
            place("Банкетка", .bench, 1.0, 0.4, sides: all, tall: false)
        case .boiler:
            place("Коллекторный шкаф ХВ/ГВ", .collector, 0.6, 0.15, sides: all, tall: true)
            if p.floorHeating != .electric { place("Котёл", .boiler, 0.45, 0.4, sides: all, tall: true) }
            place(p.floorHeating == .water ? "Бойлер косвенного нагрева 150 л" : "Водонагреватель 100 л", .heater, 0.55, 0.55, sides: all, tall: true)
            heaterPlaced = true
            place("Гидроаккумулятор 100 л", .tank, 0.5, 0.5, sides: all, tall: false)
            place("Фильтры", .filter, 0.4, 0.2, sides: all, tall: true)
            if !washerPlaced, place("Стиральная машина", .washer, 0.6, 0.6, sides: all, tall: false, keepFront: 0.5) != nil { washerPlaced = true }
        case .storage:
            place("Стеллаж", .shelf, 1.0, 0.4, sides: all, tall: true)
        case .corridor:
            break
        }
    }
}

// MARK: - Этапы: сантехника и наружные сети

enum PlumbingWorks {
    static func pointsTable(_ L: HouseLayout) -> StageTable {
        StageTable(head: ["№", "Помещение", "Прибор", "Точка", "Высота от чистого пола"],
                   rows: L.points.map { ["\($0.number)", $0.room, $0.fixture, $0.kind.rawValue, $0.height < 0.01 ? "в полу" : "\(Drawings.mm($0.height)) мм"] })
    }

    /// Материалы внутренней разводки
    static func internalItems(_ L: HouseLayout, _ p: Project) -> [WorkItem] {
        let cold = L.points.filter { $0.kind == .cold }.count, hot = L.points.filter { $0.kind == .hot }.count
        let s110 = L.sewerLen(110), s50 = L.sewerLen(50)
        var it = [
            WorkItem(name: "Труба PE-Xa 16×2.2 для водоснабжения (в гофре/изоляции)", qty: (L.coldLen + L.hotLen) * 1.15 + Double(cold + hot) * 1.0, unit: "м", note: "лучевая разводка от коллектора: \(cold) ХВ + \(hot) ГВ", digits: 0, price: 80),
            WorkItem(name: "Труба PE-Xa 25 (ввод от гильзы до коллектора)", qty: L.pipes.first { $0.d == 25 }.map { $0.length * 1.1 + 2 } ?? 5, unit: "м", digits: 0, price: 160),
            WorkItem(name: "Коллектор ХВ на \(cold) выходов с кранами", qty: 1, unit: "шт", digits: 0, price: 2500 + Double(cold) * 600),
            WorkItem(name: "Коллектор ГВ на \(hot) выходов с кранами", qty: 1, unit: "шт", digits: 0, price: 2500 + Double(hot) * 600),
            WorkItem(name: "Водорозетки + фитинги PE-Xa (на каждую точку)", qty: Double(cold + hot), unit: "компл", digits: 0, price: 450),
            WorkItem(name: "Теплоизоляция труб (вспененный ПЭ 9 мм)", qty: (L.coldLen + L.hotLen) * 1.1, unit: "м", digits: 0, price: 25),
            WorkItem(name: "Труба канализационная ПП Ø110 с фасонными частями", qty: s110 * 1.15 + 2, unit: "м", note: "уклон 2 %", digits: 0, price: 260),
            WorkItem(name: "Труба канализационная ПП Ø50 с фасонными частями", qty: s50 * 1.15, unit: "м", note: "уклон 3 %", digits: 0, price: 130),
            WorkItem(name: "Ревизия Ø110 + обратный клапан на выпуске", qty: 1, unit: "компл", digits: 0, price: 2800),
            WorkItem(name: "Аэратор (вакуумный клапан) Ø110 на стояк", qty: 1, unit: "шт", digits: 0, price: 1200),
            WorkItem(name: "Фильтры: механический + картриджный (на вводе)", qty: 1, unit: "компл", digits: 0, price: 9000),
        ]
        if L.furniture.contains(where: { $0.kind == .heater }) {
            it.append(WorkItem(name: p.floorHeating == .water ? "Бойлер косвенного нагрева 150 л" : "Водонагреватель электрический 80–100 л", qty: 1, unit: "шт", digits: 0, price: p.floorHeating == .water ? 38000 : 16000))
        }
        return it
    }

    static func fixtureItems(_ L: HouseLayout) -> [WorkItem] {
        func n(_ k: FurnKind) -> Int { L.furniture.filter { $0.kind == k }.count }
        var it: [WorkItem] = []
        if n(.toilet) > 0 { it.append(WorkItem(name: "Унитаз подвесной + инсталляция (или напольный)", qty: Double(n(.toilet)), unit: "компл", digits: 0, price: 22000)) }
        if n(.sink) > 0 { it.append(WorkItem(name: "Раковина с тумбой + смеситель + сифон", qty: Double(n(.sink)), unit: "компл", digits: 0, price: 14000)) }
        if n(.shower) > 0 { it.append(WorkItem(name: "Душевой трап/поддон + стеклянная перегородка + душевая система", qty: Double(n(.shower)), unit: "компл", digits: 0, price: 35000)) }
        if n(.bathtub) > 0 { it.append(WorkItem(name: "Ванна акриловая 1700×750 + смеситель + сифон", qty: Double(n(.bathtub)), unit: "компл", digits: 0, price: 30000)) }
        if n(.kitchen) > 0 { it.append(WorkItem(name: "Кухонная мойка + смеситель + сифон с отводом под ПММ", qty: Double(n(.kitchen)), unit: "компл", digits: 0, price: 12000)) }
        if n(.washer) > 0 { it.append(WorkItem(name: "Кран и сифон для стиральной машины", qty: Double(n(.washer)), unit: "компл", digits: 0, price: 1500)) }
        return it
    }

    static func externalItems(_ L: HouseLayout, _ p: Project) -> [WorkItem] {
        var it = [
            WorkItem(name: "Бурение скважины ≈ 40 м с обсадной трубой ПНД/ПВХ 125 (услуга)", qty: 40, unit: "м", note: "глубина — по местной гидрогеологии (песок 20–50 м, известняк 50–120 м)", digits: 0, price: 2800),
            WorkItem(name: "Насос скважинный 3\" / 4\" с кабелем и тросом", qty: 1, unit: "шт", digits: 0, price: 28000),
            WorkItem(name: "Кессон пластиковый утеплённый (или скважинный адаптер)", qty: 1, unit: "шт", digits: 0, price: 38000),
            WorkItem(name: "Гидроаккумулятор 100 л + реле давления + манометр + обратный клапан", qty: 1, unit: "компл", digits: 0, price: 14000),
            WorkItem(name: "Труба ПНД 32 PN10 питьевая (от скважины до дома)", qty: L.waterLen * 1.1 + 3, unit: "м", note: "глубина \(fmt(L.waterDepth, 1)) м", digits: 0, price: 75),
            WorkItem(name: "Гильза ввода (труба ПНД/ПВХ 110) + утеплитель", qty: 1, unit: "компл", digits: 0, price: 1500),
            WorkItem(name: L.sewerInsulate ? "Труба наружной канализации ПВХ Ø110 SN4 (рыжая) + скорлупа ЭППС" : "Труба наружной канализации ПВХ Ø110 SN4 (рыжая)", qty: L.sewerLen * 1.1 + 1, unit: "м", note: "уклон 2 %", digits: 0, price: L.sewerInsulate ? 750 : 420),
            WorkItem(name: p.septic.title, qty: 1, unit: "шт", digits: 0, price: p.septic.price),
            WorkItem(name: "Песок для подушки и обсыпки труб/септика", qty: (L.waterLen + L.sewerLen) * 0.6 * 0.3 + 4, unit: "м³", digits: 1, price: Price.sandM3),
        ]
        if L.waterHeated {
            it.append(WorkItem(name: "Греющий кабель для водопровода (саморегулирующийся) + утеплитель", qty: L.waterLen + 2, unit: "м", digits: 0, price: 900))
        }
        if L.revisionWells > 0 {
            it.append(WorkItem(name: "Колодец ревизионный канализационный Ø315", qty: Double(L.revisionWells), unit: "шт", digits: 0, price: Price.drainWell))
        }
        if p.septic == .septic3 { it.append(WorkItem(name: "Инфильтратор 800 л + щебень + геотекстиль (почвенная доочистка)", qty: 1, unit: "компл", digits: 0, price: 28000)) }
        return it
    }

    /// Наружные сети: скважина, водопровод, септик, канализация
    static func externalStage(_ p: Project, _ r: CalcResults, _ L: HouseLayout) -> BuildStage {
        var s = BuildStage(title: "Наружные сети: скважина, водопровод, септик", icon: "drop.circle", scene: .finish)
        s.goal = "Подать воду из скважины в дом и отвести стоки в \(p.septic.short) — без промерзания и с правильными уклонами."
        s.when = "скважину бурят до стройки; траншеи, ввод и септик — после фундамента и до отмостки (трубы проходят под ней)"
        s.steps = [
            "Разметить трассы по схеме: скважина в \(fmt(L.houseToWell, 1)) м за домом, \(p.septic.short) в \(fmt(L.houseToSeptic, 1)) м перед домом у проезда (ассенизатору/сервису нужен подъезд ≤ 10 м). Расстояние скважина — очистное сооружение: \(fmt(L.wellToSeptic, 0)) м (нужно ≥ \(Int(p.septic.wellDistance)) м).",
            "Скважина: обсадная труба ПНД 125 до водоносного слоя, фильтр, прокачка до чистой воды, анализ воды (химия + микробиология) — по результату подобрать фильтры.",
            "Оголовок: кессон (пластиковый утеплённый) или скважинный адаптер на глубине ниже промерзания; в нём — запорный кран и обратный клапан.",
            L.waterHeated
                ? "Водопровод: глубина промерзания \(fmt(L.dfn, 1)) м — копать ниже слишком дорого, поэтому труба ПНД 32 на глубине 0.8 м в скорлупе ЭППС с саморегулирующимся греющим кабелем (\(fmt(L.waterLen, 0)) м)."
                : "Водопровод: траншея до глубины \(fmt(L.waterDepth, 1)) м (промерзание \(fmt(L.dfn, 1)) м + 0.5 м по СП 31), песок 100 мм, труба ПНД 32 PN10 без стыков на всю длину \(fmt(L.waterLen, 0)) м, сверху песок 100–200 мм, затем грунт.",
            "Ввод в дом: стена \(L.entryWall), \(fmt(L.entryOffset, 2)) м от начала стены — через гильзу Ø110, заложенную в фундамент\(p.selectedFoundation == .slab ? " (под плитой — вертикально вверх в утеплённой гильзе)" : ""); зазор гильзы заделать герметиком и пеной, снаружи — утеплить.",
            "Выпуск канализации: стена \(L.outletWall), \(fmt(L.outletOffset, 2)) м от начала стены, низ трубы на \(fmt(L.outletDepth, 2)) м ниже земли. Наружная труба ПВХ Ø110 «рыжая» с уклоном 2 % (2 см на метр) — \(fmt(L.sewerLen, 0)) м до септика, вход в септик на глубине ≈ \(fmt(L.septicInlet, 2)) м.",
            L.sewerInsulate ? "Труба мельче допустимого (\(fmt(max(0.81, L.dfn - 0.3), 2)) м: промерзание − 0.3 м, но не менее 0.7 м до верха трубы) — уложить сверху ЭППС 50 мм полосой 600 мм или скорлупу; стоки тёплые и при постоянном пользовании не замерзают, но при отъездах зимой утепление обязательно." : "Труба ниже промерзания — утепление не требуется.",
            L.revisionWells > 0 ? "Ревизионный колодец — на повороте трассы\(L.sewerLen > 15 ? " и через каждые 15 м прямого участка" : "")." : "Трасса прямая и короткая — ревизия на выпуске из дома.",
            "Уклон проверять уровнем с клином или нивелиром на каждые 2 м; не больше 3–4 % (иначе вода убегает, а твёрдые стоки остаются). Трубы — раструбом против течения.",
            "\(p.septic.short.prefix(1).uppercased() + p.septic.short.dropFirst()): котлован на 0.3 м больше корпуса, песчаная подушка 200 мм (при высоком УГВ — бетонная плита с анкеровкой корпуса), засыпка послойно песком/ЦПС с одновременным заполнением корпуса водой, утепление горловины ЭППС.",
            p.septic == .bio ? "Станции биоочистки нужно электропитание (отдельный кабель в гофре от щита) и отвод очищенной воды — в дренажный колодец или канаву." : p.septic == .septic3 ? "Инфильтратор — на щебёночной подушке ниже выхода септика, не ближе 1 м к УГВ." : "Накопительную ёмкость откачивают по мере заполнения (≈ 1 раз в 2–4 недели при постоянном проживании).",
        ]
        s.decisions = [
            Decision(title: "Скважина — очистное", value: "\(fmt(L.wellToSeptic, 0)) м", why: "зона санитарной охраны источника; для «\(p.septic.short)» принято ≥ \(Int(p.septic.wellDistance)) м", ref: "СанПиН 2.1.4.1110-02 (ЗСО), \(N.sp32.at("разд. 5"))"),
            Decision(title: "Очистное — дом", value: "≥ 5 м (\(fmt(L.houseToSeptic, 1)) м)", why: "фундамент не подмывается, запах не попадает в дом", ref: N.sp32.code),
            Decision(title: "Водопровод", value: L.waterHeated ? "ПНД 32 на 0.8 м + греющий кабель" : "ПНД 32 на \(fmt(L.waterDepth, 1)) м", why: "нормативная глубина промерзания \(fmt(L.dfn, 2)) м", ref: N.sp31.at("разд. 11, глубина заложения")),
            Decision(title: "Наружная канализация", value: "ПВХ Ø110, уклон 2 %, \(fmt(L.sewerLen, 0)) м", why: "минимальный уклон для Ø110 — 0.02", ref: N.sp32.at("разд. 6")),
        ]
        s.figures = [Figure(kind: .siteNetworks, title: "Наружные сети на участке: скважина, септик, трассы, расстояния", aspect: 0.75),
                     Figure(kind: .sewerProfile, title: "Продольный профиль канализации: от унитаза до септика", aspect: 0.4)]
        s.items = externalItems(L, p)
        s.tools = ["Мини-экскаватор (аренда) или лопаты", "Нивелир / уровень 2 м с клином уклона", "Ножовка, фаскосниматель для ПВХ", "Сварочный аппарат/компрессионные фитинги для ПНД", "Виброплита для засыпки над септиком (вне зоны корпуса — ручная трамбовка)"]
        s.fasteners = [Fastener(what: "Раструбы ПВХ", item: "силиконовая смазка, уплотнительные кольца", how: "вручную, до метки"),
                       Fastener(what: "ПНД 32", item: "компрессионные фитинги (только в кессоне и в доме, не в грунте)", how: "ключ для ПНД"),
                       Fastener(what: "Корпус септика при высоком УГВ", item: "стропы/ленты к бетонной плите через анкерные петли", how: "—")]
        return s
    }

    /// Чистовая сантехника
    static func fixturesStage(_ p: Project, _ L: HouseLayout) -> BuildStage {
        var s = BuildStage(title: "Чистовая сантехника", icon: "shower", scene: .finish)
        s.goal = "Поставить приборы на выведенные точки и проверить всё на протечки."
        s.when = "после плитки и чистового пола в санузлах и на кухне"
        s.steps = [
            "Унитаз: инсталляция крепится к стойкам каркаса (закладные 50×150 между стойками ставятся до обшивки!) саморезами 6×80; выпуск — в раструб Ø110 через манжету/гофру, подвод ХВ — гибкой подводкой с краном.",
            "Раковина/мойка: сифон с отводом под стиральную/посудомоечную машину, подводки ≤ 0.5–0.8 м, краны на каждой точке.",
            "Душ/ванна: смеситель на высоте 1.0–1.1 м (душ) / 0.8 м (ванна), трап — с гидрозатвором ≥ 50 мм, примыкание к гидроизоляции пола — лентой.",
            "Пустить воду под давлением, проверить каждое соединение 24 ч на сухую салфетку; пролить канализацию из всех приборов одновременно.",
        ]
        s.table = pointsTable(L)
        s.items = fixtureItems(L)
        s.tools = ["Ключ разводной и газовый №1", "Фум-лента / лён с пастой", "Шуруповёрт, свёрла по плитке", "Силиконовый герметик и пистолет", "Уровень"]
        s.fasteners = [Fastener(what: "Инсталляция к каркасу", item: "закладная доска 50×150 между стойками + саморезы конструкционные 6×80", how: "ударный шуруповёрт"),
                       Fastener(what: "Раковина, бойлер на стене", item: "закладная ОСП/доска за ГКЛ + саморезы 6×60 / шпильки", how: "шуруповёрт"),
                       Fastener(what: "Резьбовые соединения воды", item: "лён + паста или фум-лента, накидные гайки с прокладками", how: "ключи, без перетяга")]
        return s
    }
}
