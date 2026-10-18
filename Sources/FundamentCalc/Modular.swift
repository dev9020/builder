import Foundation

/// Модульная система: все размеры дома подогнаны под стандартные размеры материалов,
/// чтобы почти всё ставилось целиком, а неизбежный рез был один и без отходов.
///
/// Логика модуля:
/// • шаг стоек, балок и стропил 625 мм — лист ОСП 1250 = 2 шага (стык всегда на стойке/балке),
///   плита утеплителя 600 мм входит в просвет 575 мм в распор без подрезки;
/// • стойка — целая доска 3000 мм, высота каркаса 50 + 3000 + 2×50 = 3150 мм;
/// • по высоте стены: снизу полоса-половинка листа (ОСП 625, ГКЛ 600, утеплитель 600), выше — целый лист 2500 / две плиты 1200;
///   стык листов — на распорке 50 мм на отметке 600–650 мм;
/// • наружные размеры каркаса кратны 1250 мм — целое число листов ОСП по длине стены и пола;
/// • окна и двери — только стандартные блоки, проём ставится так, чтобы стойка проёма совпала со стойкой по шагу.
enum Module {
    static let step = 0.625
    static let plan = 1.25
    static let studLen = 3.0
    static let plate = 0.05
    /// Высота каркаса стены: нижняя обвязка + стойка + 2 ряда верхней обвязки
    static var frameH: Double { plate + studLen + 2 * plate }
    /// Отметка оси распорки под стык листов (от низа нижней обвязки)
    static let seamZ = 0.625
    /// Просвет между стойками
    static var clear: Double { step - 0.05 }

    /// Ось стены, при которой наружный размер каркаса (ось + толщина) кратен 1250
    static func axis(_ v: Double, depth D: Double, minN: Double = 3) -> Double {
        max(minN, ((v + D) / plan).rounded()) * plan - D
    }
    /// Размер двора по осям, при котором двор в свету (между наружными гранями внутренних стен) кратен 1250
    static func courtyardAxis(_ v: Double, depth D: Double) -> Double {
        max(1, ((v - D) / plan).rounded()) * plan + D
    }
    static func isModular(_ v: Double, depth D: Double) -> Bool { abs(axis(v, depth: D, minN: 1) - v) < 0.004 }

    /// Положение левой стойки проёма на сетке: origin — начало сетки в координате стены
    static func snapOpening(pos: Double, width: Double, origin: Double, length: Double, taken: [(Double, Double)], studs: [Double] = []) -> Double? {
        let r0 = pos - width / 2
        let k0 = ((r0 - 0.075 - origin) / step).rounded()
        func free(_ p: Double) -> Bool {
            let a = p - width / 2, b = p + width / 2
            return a > 0.3 && b < length - 0.3 && !taken.contains(where: { a < $0.1 + 0.2 && b > $0.0 - 0.2 })
        }
        // ближайшая точка сетки, где проём помещается и не задевает соседние
        for dk in [0.0, -1, 1, -2, 2, -3, 3, -4, 4, -5, 5, -6, 6] {
            let p = origin + (k0 + dk) * step + 0.075 + width / 2
            if free(p) { return p }
        }
        // на сетку не встаёт — стойка проёма на стойке примыкания перегородки (тоже без лишней стойки)
        var byStud: [Double] = []
        for s in studs {
            let off = 0.075 + width / 2
            for c in [s + off, s - off] where free(c) { byStud.append(c) }
        }
        if let p = byStud.min(by: { abs($0 - pos) < abs($1 - pos) }), abs(p - pos) < 1.0 { return p }
        // иначе — ближайшее свободное место
        for d in stride(from: 0.0, through: length, by: 0.05) {
            for p in [pos - d, pos + d] where free(p) { return p }
        }
        return nil
    }
}

/// Строка «стандартного комплекта»: какой материал, какого размера и как он ложится в модуль
struct KitRow: Identifiable {
    let id = UUID()
    let group: String
    let material: String
    let size: String
    let rule: String
    let cut: String
    let qty: String
    var whole = true          // ставится целиком / рез без отходов
}

/// Проверка соответствия проекта модулю
struct ModuleCheck: Identifiable {
    let id = UUID()
    let title: String
    let ok: Bool
    let detail: String
}

extension Project {
    /// Толщина каркаса наружных стен (по стойке)
    var studDepth: Double { FrameGen.studSec(defaultMaterial).wm }

    /// Подогнать дом под модуль: размеры, шаг, высоту этажа, проёмы — под стандартные блоки и сетку стоек
    func fitToModule() {
        let D = studDepth
        let oldRings = rings
        modular = true
        studStep = Module.step
        length = Module.axis(length, depth: D)
        width = Module.axis(width, depth: D)
        switch shape {
        case .lShape, .uShape:
            wingA = Module.axis(wingA, depth: D, minN: 2)
            wingB = Module.axis(wingB, depth: D, minN: 2)
        case .ring:
            innerL = Module.courtyardAxis(innerL, depth: D)
            innerW = Module.courtyardAxis(innerW, depth: D)
        default: break
        }
        floorHeight = Module.frameH + 0.222
        remap(from: oldRings)
        snapOpeningsToModule()
    }

    /// Перенос перегородок и проёмов на новую геометрию: кусочно-линейно по координатам углов контура
    private func remap(from old: [[V2]]) {
        let new = rings
        guard old.count == new.count, zip(old, new).allSatisfy({ $0.count == $1.count }) else { return }
        func axisMap(_ get: (V2) -> Double) -> (Double) -> Double {
            var pairs: [(Double, Double)] = []
            for (ro, rn) in zip(old, new) { for (a, b) in zip(ro, rn) { pairs.append((get(a), get(b))) } }
            var uniq: [(Double, Double)] = []
            for p in pairs.sorted(by: { $0.0 < $1.0 }) where !uniq.contains(where: { abs($0.0 - p.0) < 1e-6 }) { uniq.append(p) }
            return { v in
                guard uniq.count > 1 else { return v }
                var i = 1
                while i < uniq.count - 1 && v > uniq[i].0 { i += 1 }
                let (x0, y0) = uniq[i - 1], (x1, y1) = uniq[i]
                return y0 + (v - x0) * (y1 - y0) / max(x1 - x0, 1e-9)
            }
        }
        let mx = axisMap(\.x), my = axisMap(\.y)
        func m(_ v: V2) -> V2 { V2(mx(v.x), my(v.y)) }
        var centers: [UUID: V2] = [:]
        for o in openings { if let c = openingCenter(o) { centers[o.id] = m(c) } }
        partitions = partitions.map { var q = $0; q.a = m(q.a); q.b = m(q.b); return q }
        roomMarks = roomMarks.map { RoomMark(at: m($0.at), type: $0.type) }
        openings = openings.map { o in
            guard let c = centers[o.id], let l = hostLine(o.host) else { return o }
            var q = o
            q.pos = dot2(c - l.a, (l.b - l.a).unit)
            return q
        }
    }

    /// Проёмы → черновые проёмы стандартных блоков; стойка проёма — на сетке 625 мм
    func snapOpeningsToModule() {
        let D = studDepth
        let ee = edges
        var taken: [OpeningHost: [(Double, Double)]] = [:]
        // сначала широкие — им труднее найти место
        let order = openings.indices.sorted { openings[$0].width > openings[$1].width }
        var drop = Set<UUID>()
        for i in order {
            var o = openings[i]
            var exterior = false
            if case .edge = o.host { exterior = true }
            guard let l = hostLine(o.host) else { continue }
            let len = (l.b - l.a).len
            var origin = 0.0
            if case .edge(let ei) = o.host, ei < ee.count { origin = -D / 2 }
            // стандартный блок; если не помещается на стене — следующий меньший того же типа
            let first = StdBlock.nearest(o, exterior: exterior)
            let smaller = StdBlock.catalog.filter { $0.kind == first.kind && $0.id.prefix(1) == first.id.prefix(1) && $0.w < first.w }.sorted { $0.w > $1.w }
            var placed = false
            for blk in [first] + smaller {
                let w = (blk.roW * 1000).rounded() / 1000
                var studs: [Double] = []
                if case .edge(let ei) = o.host, ei < ee.count { studs = Daylight.junctionStuds(self, edge: ei) }
                guard let pos = Module.snapOpening(pos: o.pos, width: w, origin: origin, length: len, taken: taken[o.host] ?? [], studs: studs) else { continue }
                o.width = w
                o.height = (blk.roH * 1000).rounded() / 1000
                if blk.kind.isDoor || blk.kind == .panoramic { o.sill = 0 }
                o.pos = pos
                placed = true
                break
            }
            if !placed { drop.insert(o.id); continue }
            taken[o.host, default: []].append((o.pos - o.width / 2, o.pos + o.width / 2))
            openings[i] = o
        }
        openings.removeAll { drop.contains($0.id) }
    }

    /// Насколько проект соответствует модулю
    func moduleChecks(_ b: BuildPlan) -> [ModuleCheck] {
        let D = studDepth
        var out: [ModuleCheck] = []
        let dims: [(String, Double)] = {
            var d = [("Длина", length)]
            if shape != .square { d.append(("Ширина", width)) }
            if shape == .lShape || shape == .uShape { d += [("Крыло A", wingA), ("Крыло B", wingB)] }
            return d
        }()
        let bad = dims.filter { !Module.isModular($0.1, depth: D) }
        out.append(ModuleCheck(title: "Наружные размеры каркаса кратны 1250 мм",
                               ok: bad.isEmpty,
                               detail: bad.isEmpty ? dims.map { "\($0.0.lowercased()) \(Drawings.mm($0.1 + D))" }.joined(separator: ", ") + " мм = целое число листов ОСП"
                                                   : bad.map { "\($0.0.lowercased()) \(Drawings.mm($0.1 + D)) → \(Drawings.mm(Module.axis($0.1, depth: D) + D))" }.joined(separator: ", ")))
        out.append(ModuleCheck(title: "Шаг стоек, балок и стропил 625 мм", ok: abs(studStep - Module.step) < 1e-6,
                               detail: abs(studStep - Module.step) < 1e-6 ? "лист 1250 = 2 шага, утеплитель 600 в просвет 575 без подрезки" : "сейчас \(Drawings.mm(studStep)) мм — стыки листов не попадут на стойки"))
        out.append(ModuleCheck(title: "Стойка — целая доска 3000 мм", ok: modular,
                               detail: modular ? "высота каркаса 3150 мм (50 + 3000 + 2×50), этаж \(Drawings.mm(b.frame.levels.count > 1 ? b.frame.levels[1] - b.frame.levels[0] : floorHeight)) мм" : "высота этажа задана вручную — стойки придётся резать"))
        let nonStd = b.openings.filter { !$0.standard }.count
        out.append(ModuleCheck(title: "Окна и двери — стандартные блоки", ok: nonStd == 0,
                               detail: nonStd == 0 ? "\(b.openings.count) проёмов, все под типовые размеры ГОСТ" : "\(nonStd) проём(ов) под заказ"))
        let off = openings.filter { o in
            guard case .edge(let ei) = o.host else { return false }
            let g = (o.pos - o.width / 2 - 0.075 + D / 2) / Module.step
            if abs(g - g.rounded()) <= 0.01 { return false }
            // стойка проёма совпала со стойкой примыкания перегородки — тоже без лишней стойки
            let kings = [o.pos - o.width / 2 - 0.075, o.pos + o.width / 2 + 0.075]
            return !Daylight.junctionStuds(self, edge: ei).contains { s in kings.contains { abs($0 - s) < 0.01 } }
        }.count
        out.append(ModuleCheck(title: "Стойки проёмов на сетке стоек", ok: off == 0,
                               detail: off == 0 ? "у каждого окна одна стойка — рядовая, лишних стоек меньше" : "\(off) проём(ов) не на сетке — лишние стойки и подрезка утеплителя"))
        let dark = Daylight.issues(self)
        out.append(ModuleCheck(title: "Естественный свет в комнатах и коридорах", ok: dark.isEmpty,
                               detail: dark.isEmpty ? "окна жилых комнат ≥ 1/8 площади пола (\(N.sp55.code)), у коридоров и прихожих есть остекление"
                                                    : dark.joined(separator: "; ") + " — добавьте окно (для прохода — узкое 600×1800)"))
        return out
    }
}

enum Kit {
    /// Карта стандартных материалов проекта
    static func make(_ p: Project, _ r: CalcResults, _ b: BuildPlan) -> [KitRow] {
        let F = b.frame
        let D = F.studExt
        let floors = max(p.floors, 1)
        let mod = p.modular
        func n(_ k: MemberKind, _ f: (Member) -> Bool = { _ in true }) -> Int { F.members.filter { $0.kind == k && f($0) }.count }
        let fullStuds = F.members.filter { [.stud, .cornerStud, .king].contains($0.kind) && abs($0.length - Module.studLen) < 0.01 }.count
        let otherStuds = F.members.filter { [.stud, .cornerStud, .king, .jack, .cripple].contains($0.kind) }.count - fullStuds
        let plateLen = F.members.filter { [.bottomPlate, .topPlate, .capPlate].contains($0.kind) }.reduce(0) { $0 + $1.length }
        let nog = n(.nogging)
        var rows: [KitRow] = []

        // --- пиломатериал ---
        rows.append(KitRow(group: "Пиломатериал", material: "Стойки каркаса", size: "доска \(D.label)×3000",
                           rule: mod ? "высота каркаса 3150 = 50 (низ) + 3000 (стойка) + 2×50 (верх)" : "высота этажа задана вручную",
                           cut: mod ? "без резки — ставится целиком" : "рез каждой стойки в размер", qty: "\(fullStuds) шт целиком" + (otherStuds > 0 ? " + \(otherStuds) у проёмов (из обрезков и 3 м)" : ""), whole: mod))
        rows.append(KitRow(group: "Пиломатериал", material: "Обвязки (низ, верх 2 ряда)", size: "доска \(D.label)×6000",
                           rule: "кладутся целыми хлыстами, стыки рядов разнесены ≥ 1250", cut: "рез только последнего отрезка стены и в дверях",
                           qty: "\(Int((plateLen / 6 * 1.05).rounded(.up))) шт (\(fmt(plateLen, 0)) м)"))
        if nog > 0 {
            rows.append(KitRow(group: "Пиломатериал", material: "Распорки под стык листов", size: "доска \(D.label), длина 575",
                               rule: "просвет 625 − 50 = 575 мм на отметке 600–650 мм", cut: "из доски 3000 — 5 распорок, 1 настройка упора пилы",
                               qty: "\(nog) шт = \(Int((Double(nog) / 5).rounded(.up))) досок 3000"))
        }
        if let g = F.floors.first {
            rows.append(KitRow(group: "Пиломатериал", material: "Балки перекрытий", size: "доска \(g.check.sec.label)×6000",
                               rule: "шаг 625 — над стойками (балка на стойку, без смещения)", cut: "торец по месту, пролёт ≤ 6 м — одной доской",
                               qty: "\(F.members.filter { $0.kind == .joist }.count) шт"))
        }
        if let rf = F.rafter {
            rows.append(KitRow(group: "Пиломатериал", material: "Стропила", size: "доска \(rf.sec.label)×6000",
                               rule: "шаг 625 — над стойками и балками", cut: "2 реза по шаблону (конёк + опорный запил)",
                               qty: "\(n(.rafter)) шт"))
        }
        rows.append(KitRow(group: "Пиломатериал", material: "Контррейка фасада", size: "брусок 25×50×3000",
                           rule: "вертикально по каждой стойке, длина = стойке", cut: "без резки",
                           qty: "\(Int((b.wallGross / Module.step / 3 * 1.05).rounded(.up))) шт"))
        rows.append(KitRow(group: "Пиломатериал", material: "Обрешётка изнутри (инсталляционная)", size: "брусок 25×50×3000",
                           rule: "горизонтально шаг 600, стык на стойке", cut: "рез на 2500 (4 шага), обрезок 500 — на откосы",
                           qty: "\(Int((b.wallNet / 0.6 / 2.5 * 1.05).rounded(.up))) шт", whole: false))

        // --- листы ---
        let perim = p.segments.reduce(0) { $0 + $1.length }
        let cols = Int(((perim + 4 * D.wm) / 1.25).rounded(.up))
        let osbWalls = Int((Double(cols * floors) * 1.0).rounded(.up)), osbStrips = cols * floors
        rows.append(KitRow(group: "Листы", material: "ОСП-3 9 мм (стены снаружи)", size: "2500×1250",
                           rule: "лист вертикально = 2 шага; снизу полоса 625 (лист пополам вдоль), выше — целый 2500",
                           cut: "1 рез пополам на 2 полосы — 0 отходов; проёмы — по месту",
                           qty: "\(osbWalls + Int((Double(osbStrips) / 2).rounded(.up))) листов (\(osbWalls) целых + \(osbStrips) полос) + фронтоны"))
        if F.floors.first != nil || floors > 1 {
            let area = r.loads.floorArea * Double(F.floors.isEmpty ? floors - 1 : floors)
            rows.append(KitRow(group: "Листы", material: "ОСП-3 22 мм шпунт (пол)", size: "2500×1250",
                               rule: "2500 поперёк балок = 4 пролёта по 625, ряды по 1250", cut: "без резки в поле, у стен — по месту",
                               qty: "\(Int((area / 3.125 * 1.04).rounded(.up))) листов"))
        }
        let gklA = b.wallNet + b.partitionArea * 2
        let gb = p.gklBase
        switch p.interiorFinish {
        case .gkl:
            rows.append(KitRow(group: "Листы", material: "ГКЛ 12.5 мм (стены изнутри)", size: "2500×1200",
                               rule: gb > 0.001 ? "от стяжки целый лист 2500, сверху полоса \(Drawings.mm(3.11 - gb - 2.51))" : "снизу полоса 600 (лист пополам вдоль), выше — целый 2500: 10 + 600 + 2500 = 3110 до потолка",
                               cut: gb > 0.001 ? "1 рез поперёк на полосу" : "1 рез пополам на 2 полосы — 0 отходов", qty: "\(Int((gklA / (1.2 * 3.1) * 1.25 * 1.05).rounded(.up))) листов", whole: gb < 0.001))
        case .boards:
            rows.append(KitRow(group: "Отделка", material: "Вагонка (стены изнутри)", size: "14×96×3000",
                               rule: "вертикально, длина 3000 = высота стены (зазоры закрывают плинтус и галтель)", cut: "по длине без резки",
                               qty: "\(Int((gklA / (3.0 * 0.088) * 1.05).rounded(.up))) шт"))
        case .osb:
            rows.append(KitRow(group: "Листы", material: "ОСП-3 12 мм (стены изнутри)", size: "2500×1250",
                               rule: "как снаружи: полоса 625 + лист 2500, стыки на стойках", cut: "1 рез пополам — 0 отходов",
                               qty: "\(Int((gklA / 3.125 * 1.08).rounded(.up))) листов"))
        }
        switch p.floorSystemEff {
        case .semiDry:
            rows.append(KitRow(group: "Пол", material: "ЭППС под стяжку", size: "плита 1185×585", rule: "вразбежку, без щелей", cut: "только у стен", qty: "\(Int((r.loads.floorArea * 1.05 / 0.693).rounded(.up))) плит"))
        case .dryScreed:
            rows.append(KitRow(group: "Пол", material: "ГВЛ элементы пола", size: "1200×600×20", rule: "обрезок ряда начинает следующий ряд", cut: "1 рез на ряд", qty: "\(Int((r.loads.floorArea / 0.72 * 1.05).rounded(.up))) шт"))
        default: break
        }
        rows.append(KitRow(group: "Пол", material: p.floorFinish.title, size: p.floorFinish == .tile ? "600×600" : "панели в пачках", rule: "обрезок ряда (≥ 300) начинает следующий ряд", cut: "по ряду у стены", qty: "\(fmt(r.loads.floorArea * Double(floors) * 1.05, 0)) м²", whole: false))
        let ceil = r.loads.floorArea * Double(floors)
        rows.append(KitRow(group: "Листы", material: "ГКЛ 12.5 мм (потолок)", size: "2500×1200",
                           rule: "поперёк обрешётки 25×50 шаг 400", cut: "по месту у стен", qty: "\(Int((ceil / 3.0 * 1.08).rounded(.up))) листов", whole: false))

        // --- утеплитель ---
        let bays = b.wallNet / (Module.step * Module.studLen)
        let layers = woolLayers(b.woolWall, depth: D.wm)
        rows.append(KitRow(group: "Утеплитель", material: "Минвата в стены", size: "плита 1200×600×" + layers.map { "\(Int($0 * 1000))" }.joined(separator: "+"),
                           rule: "600 в просвет 575 — в распор; по высоте 600 (под распоркой) + 1200 + 1200",
                           cut: "1 рез: плита 1200 пополам на 2 по 600 — 0 отходов",
                           qty: "\(Int((bays * 2.5 * Double(layers.count) * 1.03).rounded(.up))) плит"))
        if let g = F.floors.first {
            rows.append(KitRow(group: "Утеплитель", material: "Минвата в пол", size: "плита 1200×600×\(Int(b.woolFloor * 1000))",
                               rule: "600 в просвет между балками 575 — в распор", cut: "только последняя плита у стены",
                               qty: "\(Int((r.loads.floorArea / 0.72 * Double(max(1, Int((b.woolFloor / 0.1).rounded())))  * 1.03).rounded(.up))) плит по 100 мм"))
            _ = g
        }

        // --- плёнки ---
        rows.append(KitRow(group: "Плёнки", material: "Ветрозащитная мембрана", size: "рулон 1.5×50 м",
                           rule: "горизонтально снизу вверх, нахлёст 150: 3 полосы на этаж", cut: "только по длине",
                           qty: "\(Int((b.wallNet * 1.15 / 75).rounded(.up))) рул."))
        rows.append(KitRow(group: "Плёнки", material: "Пароизоляция", size: "рулон 1.5×50 м",
                           rule: "горизонтально, нахлёст 100 + лента", cut: "только по длине",
                           qty: "\(Int(((b.wallNet + ceil) * 1.15 / 75).rounded(.up))) рул."))

        // --- фасад и кровля ---
        rows.append(KitRow(group: "Фасад", material: p.facade.title, size: facadeSize(p.facade), rule: facadeRule(p.facade), cut: facadeCut(p.facade), qty: "\(fmt(b.wallNet * 1.1, 0)) м²", whole: false))
        if p.roofType != .flat {
            let (sz, rl, ct) = roofFit(p, F)
            rows.append(KitRow(group: "Кровля", material: p.covering.title, size: sz, rule: rl, cut: ct, qty: "\(fmt(r.loads.roofArea * 1.1, 0)) м²"))
        }

        // --- проёмы ---
        var byBlock: [String: (StdBlock, Int)] = [:]
        for o in b.openings {
            let k = o.opening.kind.isDoor || o.wall.hasPrefix("П") ? 1 : floors
            byBlock[o.block.id, default: (o.block, 0)].1 += k
        }
        for (_, (blk, k)) in byBlock.sorted(by: { $0.key < $1.key }) {
            rows.append(KitRow(group: "Окна и двери", material: blk.kind.title, size: "блок \(blk.mm)",
                               rule: "черновой проём \(Drawings.mm(blk.roW))×\(Drawings.mm(blk.roH)) (монтажный зазор по ГОСТ 30971)",
                               cut: "типовой размер — со склада, без заказа", qty: "\(k) шт"))
        }
        return rows
    }

    /// Утеплитель стены — набор стандартных толщин (50/100/150) на толщину каркаса
    static func woolLayers(_ need: Double, depth: Double) -> [Double] {
        let t = max(need, depth)
        switch Int((t * 1000).rounded()) {
        case ...100: return [0.1]
        case 101...150: return [0.1, 0.05]
        case 151...200: return [0.1, 0.1]
        case 201...250: return [0.1, 0.1, 0.05]
        default: return [0.1, 0.1, 0.1]
        }
    }

    static func facadeSize(_ f: FacadeFinish) -> String {
        switch f {
        case .siding: return "панель 3660×230"
        case .imitationTimber: return "доска 20×146×6000"
        case .fiberCement: return "панель 3030×455"
        case .plaster: return "плита фасадная 1200×600"
        case .facingBrick: return "кирпич 250×120×65"
        }
    }
    static func facadeRule(_ f: FacadeFinish) -> String {
        switch f {
        case .siding: return "по контррейкам 625, стык панелей — на рейке"
        case .imitationTimber: return "горизонтально по контррейкам 625; 6000 → 5625 = 9 шагов"
        case .fiberCement: return "по подсистеме с шагом 625"
        case .plaster: return "плиты 1200×600 вразбежку на клей + дюбели"
        case .facingBrick: return "кладка на выступе фундамента, связи в стойки 625"
        }
    }
    static func facadeCut(_ f: FacadeFinish) -> String {
        switch f {
        case .imitationTimber: return "1 рез на доску (обрезок 375 — доборы и откосы)"
        case .facingBrick: return "без резки, ½ кирпича в перевязке"
        default: return "у углов и проёмов"
        }
    }

    /// Покрытие кровли под длину ската
    static func roofFit(_ p: Project, _ F: Framing) -> (String, String, String) {
        let a = p.roofAngleEff * .pi / 180
        let slope = (F.rafterRun + p.overhang) / cos(a)
        switch p.covering {
        case .metalTile:
            let waves = Int((slope / 0.35).rounded(.up))
            return ("лист 1180 (полезн. 1100) × \(Drawings.mm(Double(waves) * 0.35 + 0.05))", "длина листа кратна волне 350: \(waves) волн на скат \(fmt(slope, 2)) м", "лист заказывается в размер — на крыше не режется")
        case .profiledSheet, .seam:
            return ("лист/картина длиной \(Drawings.mm(slope + 0.05))", "одним листом на скат без поперечных стыков", "в размер на заводе")
        case .softShingle:
            return ("ОСП-3 12 мм 2500×1250 + гонт", "лист ОСП 2500 поперёк стропил = 4 шага 625", "рез только у конька и ендов")
        case .slate, .ondulin, .compositeTile, .ceramicTile, .cementTile:
            return ("штучное покрытие", "шаг обрешётки по размеру элемента", "у конька, ендов и вальм")
        }
    }

    /// Таблица соединений: что, чем, сколько
    static let joints: [(what: String, how: String, qty: String, tool: String)] = [
        ("Стойка → нижняя/верхняя обвязка", "гвоздь 4×100 (или ершёный 3.1×90) в торец через обвязку", "2 шт на конец", "молоток 600–800 г / гвоздезабивной пистолет"),
        ("Стойка, если торцом не прибить", "косой гвоздь 4×100 под 60° / уголок 50×50 + анкерные гвозди 4×40", "по 2 с каждой стороны", "молоток, шуруповёрт"),
        ("Двойная (угловая) стойка", "гвозди 4×100 вразбежку", "шаг 300, 2 ряда", "молоток"),
        ("Распорка 575 → стойка", "гвоздь 4×100 через стойку в торец (или косо)", "2 шт на конец", "молоток"),
        ("Верхняя обвязка: 2-й ряд на 1-й", "гвозди 4×100 вразбежку; в углах — перевязка", "шаг 400 + 2 на каждой перевязке", "молоток"),
        ("Нижняя обвязка → платформа пола", "гвоздь 4×100 / саморез 5×90 в балку и обвязочную доску", "шаг 400", "шуруповёрт"),
        ("Стены в углу между собой", "саморезы 5×90 / 6×120 конструкционные", "шаг 300 по высоте", "шуруповёрт с битой Torx"),
        ("Перемычка (2 доски) → опорные стойки", "гвозди 4×100 через полные стойки в торцы", "4 шт на конец", "молоток"),
        ("Балка перекрытия → обвязка", "опора балки или уголок 90×90×65 на анкерных гвоздях 4×40", "2 опоры/уголка на конец", "молоток"),
        ("Балки внахлёст над опорой", "4 гвоздя 4×100 или 2 болта М12", "нахлёст ≥ 300", "дрель Ø13, ключ 19"),
        ("Стропило → верхняя обвязка", "2 усиленных уголка 90×90×65 + ветровая скоба к стойке", "на каждую ногу", "молоток, шуруповёрт"),
        ("Стропило → затяжка (балка)", "гвозди 4×100 или шпилька М12", "6 гвоздей / 1 шпилька", "дрель Ø13"),
        ("Брус обвязки в углу", "соединение «в полдерева» + 2 самореза 8×120 / нагель Ø16", "в каждом углу", "циркулярка, стамеска, дрель"),
        ("Обвязка → фундамент", "шпилька М12 на химическом анкере", "≤ 2000 мм, ≤ 300 от углов", "перфоратор, пистолет для анкера"),
        ("ОСП 9 → каркас (стены)", "ершёные гвозди 2.5×50 / саморезы 3.5×45", "150 по краю, 300 в поле, отступ 10", "гвоздезабивной пистолет / шуруповёрт"),
        ("ОСП 22 → балки (пол)", "клей ПУ + саморезы 4.5×50", "150 по краю, 300 в поле", "шуруповёрт, пистолет для клея"),
        ("Контррейка → стойка", "гвоздь оцинк. 3×70 / саморез 4.5×70", "шаг 300", "молоток / шуруповёрт"),
        ("ГКЛ → обрешётка", "саморезы для ГКЛ 3.5×35", "250 по краю и в поле", "шуруповёрт с ограничителем"),
    ]
}
