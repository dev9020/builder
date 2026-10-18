import Foundation

struct WorkItem: Identifiable {
    let id = UUID()
    let name: String
    let qty: Double
    let unit: String
    var note = ""
    var digits = 1
    var price = 0.0     // цена за единицу до наценки, ₽
}

struct WorkSection: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    var steps: [String] = []
    var items: [WorkItem] = []
}

/// Геометрия для схемы разбивки
struct LayoutScheme {
    var obnoska: [V2] = []          // контур обноски
    var posts: [V2] = []            // столбики обноски
    var strings: [(V2, V2)] = []    // шнуры
    var footprint: [(V2, V2, Double)] = []   // оси лент/ростверка и ширина
    var slab: [[V2]] = []
    var beacons: [V2] = []          // маяки / метки верха
    var piles: [V2] = []
    var site: (lo: V2, hi: V2) = (V2(0, 0), V2(1, 1))
}

struct WorkPlan {
    var sections: [WorkSection] = []
    var purchase: [WorkItem] = []
    var scheme = LayoutScheme()
    var summary: [(String, String)] = []
}

/// Склонение: 1 доска, 2 доски, 5 досок
func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let m10 = n % 10, m100 = n % 100
    if m10 == 1 && m100 != 11 { return "\(n) \(one)" }
    if (2...4).contains(m10) && !(12...14).contains(m100) { return "\(n) \(few)" }
    return "\(n) \(many)"
}

enum Works {
    /// Цена за единицу по названию позиции (для позиций, где цена не задана при создании)
    static func unitPrice(_ it: WorkItem, _ p: Project) -> Double {
        let n = it.name
        if n.hasPrefix("Арматура Ø") {
            let parts = n.dropFirst("Арматура Ø".count).split(separator: " ")
            let d = Int(parts.first ?? "12") ?? 12
            return Price.rebarPerM(d, parts.count > 1 ? String(parts[1]) : "")
        }
        let table: [(String, Double)] = [
            ("Бетон B7.5", Price.concretePrep), ("Бетон ", Price.concrete(p.concrete)),
            ("Столбики обноски", Price.post), ("Доска обноски", Price.obnoskaBoardM), ("Шнур", Price.stringM),
            ("Песок к заказу", Price.sandM3), ("Геотекстиль", Price.geotextileM2),
            ("Доска обрезная", Price.board25x150x6), ("Брусок", Price.bar50x50M), ("Гвозди", Price.nailsKg),
            ("Плёнка", Price.filmM2), ("Шпилька", Price.tieSet), ("Трубка ПВХ", Price.pvcTubeM),
            ("Вязальная проволока", Price.wireKg), ("Фиксатор «стульчик»", Price.chair), ("Фиксатор «звёздочка»", Price.star),
            ("Точечные маяки", 60), ("Метки верха", Price.screwMark), ("Правило", Price.rule / 2), ("Маячная рейка", Price.slatM),
            ("Наплавляемая", Price.roofingM2), ("Битумная мастика", Price.masticKg), ("ЭППС 100", Price.eps100M2),
        ]
        return table.first { n.hasPrefix($0.0) }?.1 ?? 0
    }

    static let boardW = 0.15, boardT = 0.025, boardL = 6.0
    static let wireKgPerM = 0.0089   // вязальная проволока Ø1.2 мм

    static func boards(_ meters: Double) -> Int { Int((meters * 1.05 / boardL).rounded(.up)) }

    static func plan(_ p: Project, _ r: CalcResults, kind kindIn: FoundationKind? = nil) -> WorkPlan {
        var w = WorkPlan()
        let kind = kindIn ?? p.selectedFoundation
        let lines = r.loads.lines
        let totalL = lines.reduce(0) { $0 + $1.length }

        // --- Габарит фундамента ---
        var lo = V2(.infinity, .infinity), hi = -lo
        func grow(_ v: V2) { lo = pointwiseMin(lo, v); hi = pointwiseMax(hi, v) }
        switch kind {
        case .strip:
            for sl in r.strip.lines {
                let b = sl.b / 2, d = sl.line.dir, n = V2(-d.y, d.x)
                for e in [sl.line.a - d * b, sl.line.b + d * b] { grow(e + n * b); grow(e - n * b) }
                w.scheme.footprint.append((sl.line.a, sl.line.b, sl.b))
            }
        case .slab:
            for ring in r.slab.rings { for v in ring { grow(v) } }
            w.scheme.slab = r.slab.rings
        case .piles:
            for pl in r.piles.lines {
                let b = r.piles.bg / 2, d = pl.line.dir, n = V2(-d.y, d.x)
                for e in [pl.line.a - d * b, pl.line.b + d * b] { grow(e + n * b); grow(e - n * b) }
                w.scheme.footprint.append((pl.line.a, pl.line.b, r.piles.bg))
            }
            w.scheme.piles = r.piles.positions
        }
        if !lo.x.isFinite { return w }
        let fw = hi.x - lo.x, fh = hi.y - lo.y

        // --- 1. Площадка и разбивка ---
        let margin = kind == .slab ? 1.0 : 1.0
        let sLo = lo - V2(margin, margin), sHi = hi + V2(margin, margin)
        let siteA = (sHi.x - sLo.x) * (sHi.y - sLo.y)
        let topsoilV = siteA * p.topsoil
        let oOff = 1.5
        let oLo = lo - V2(oOff, oOff), oHi = hi + V2(oOff, oOff)
        w.scheme.obnoska = [oLo, V2(oHi.x, oLo.y), oHi, V2(oLo.x, oHi.y)]
        w.scheme.site = (sLo, sHi)
        let oPer = 2 * ((oHi.x - oLo.x) + (oHi.y - oLo.y))
        let nPosts = Int((oPer / 1.5).rounded(.up))
        for i in 0..<4 {
            let a = w.scheme.obnoska[i], b = w.scheme.obnoska[(i + 1) % 4]
            let n = Int(((b - a).len / 1.5).rounded(.up))
            for k in 0..<n { w.scheme.posts.append(a + (b - a) * (Double(k) / Double(n))) }
        }
        // шнуры по граням лент / контуру плиты — до обноски
        func extendToObnoska(_ a: V2, _ b: V2) -> (V2, V2) {
            let d = (b - a).unit
            if abs(d.x) > 0.5 { return (V2(oLo.x, a.y), V2(oHi.x, a.y)) }
            return (V2(a.x, oLo.y), V2(a.x, oHi.y))
        }
        var stringLen = 0.0
        switch kind {
        case .strip, .piles:
            for (a, b, wd) in w.scheme.footprint {
                let d = (b - a).unit, n = V2(-d.y, d.x)
                for s in [-wd / 2, wd / 2] {
                    let e = extendToObnoska(a + n * s, b + n * s)
                    if !w.scheme.strings.contains(where: { ($0.0 - e.0).len < 0.02 && ($0.1 - e.1).len < 0.02 }) {
                        w.scheme.strings.append(e); stringLen += (e.1 - e.0).len
                    }
                }
            }
        case .slab:
            for ring in r.slab.rings {
                for i in ring.indices {
                    let e = extendToObnoska(ring[i], ring[(i + 1) % ring.count])
                    if !w.scheme.strings.contains(where: { ($0.0 - e.0).len < 0.02 && ($0.1 - e.1).len < 0.02 }) {
                        w.scheme.strings.append(e); stringLen += (e.1 - e.0).len
                    }
                }
            }
        }
        var s1 = WorkSection(title: "Площадка и разбивка осей", icon: "map")
        s1.steps = [
            "Расчистить участок \(fmt(sHi.x - sLo.x, 1)) × \(fmt(sHi.y - sLo.y, 1)) м (габарит фундамента \(fmt(fw, 1)) × \(fmt(fh, 1)) м + по 1 м рабочей зоны).",
            "Снять растительный слой на глубину \(Int(p.topsoil * 100)) см (весь гумус и корни — до минерального грунта; если он глубже — снимать до него). Грунт сложить отдельно, на планировку участка.",
            "Вынести репер (неподвижную отметку) вне зоны работ: от него будут отсчитываться все высоты. Отметка «0.000» — уровень земли после планировки.",
            "Установить обноску в \(fmt(oOff, 1)) м от граней фундамента: столбики 50×50 через 1.5 м (\(nPosts) шт.), доска 25×150 по верху, выставленная по нивелиру в один уровень.",
            "Вынести оси лазерным нивелиром / рулеткой, натянуть шнуры по граням \(kind == .slab ? "плиты" : "лент") (\(w.scheme.strings.count) шт.). Проверить диагонали: разница не более 10 мм.",
        ]
        s1.items = [
            WorkItem(name: "Площадь расчистки", qty: siteA, unit: "м²"),
            WorkItem(name: "Объём снимаемого растительного слоя", qty: topsoilV, unit: "м³"),
            WorkItem(name: "Столбики обноски 50×50, L = 1.2 м", qty: Double(nPosts), unit: "шт", digits: 0),
            WorkItem(name: "Доска обноски 25×150", qty: oPer, unit: "м.п."),
            WorkItem(name: "Шнур разбивочный (капроновый)", qty: stringLen * 1.2, unit: "м", digits: 0),
        ]
        w.sections.append(s1)

        // --- 2. Земляные работы и подушка ---
        var s2 = WorkSection(title: "Земляные работы и подушка", icon: "shovel")
        var excav = 0.0, backfill = 0.0, sandV = 0.0, geotex = 0.0, prepV = 0.0
        switch kind {
        case .strip:
            let s = r.strip
            let dT = s.depth + s.cushion + (p.concretePrep ? 0.05 : 0) - p.topsoil
            var cBelow = 0.0
            for sl in s.lines {
                guard let sec = s.section(sl.line) else { continue }
                let bt = sec.b + 0.6
                excav += sl.line.length * bt * max(dT, 0)
                cBelow += sl.line.length * (sec.isT ? sec.b * sec.soleH + sec.stemW * max(0, s.depth - p.topsoil - sec.soleH) : sec.b * max(0, s.depth - p.topsoil))
                geotex += sl.line.length * bt
            }
            sandV = s.sand; prepV = s.prep
            backfill = max(0, excav - cBelow - sandV - prepV)
            s2.steps = [
                "Отрыть траншеи шириной b + 0.6 м (по 300 мм с каждой стороны под опалубку и гидроизоляцию) на глубину \(fmt(dT)) м от спланированного основания. Дно зачистить вручную, не перекапывать: перебор засыпается песком, а не грунтом.",
                "Проверить дно нивелиром: перепад не более ±20 мм. При появлении воды — водоотлив и дренаж.",
                "Уложить геотекстиль (плотность ≥ 150 г/м²) с нахлёстом 15–20 см.",
                "Песчаная подушка \(Int(s.cushion * 1000)) мм — песок средней крупности слоями по 100–150 мм с проливкой водой и трамбовкой виброплитой (Купл ≥ 0.95).",
                p.concretePrep ? "Бетонная подготовка 50 мм из B7.5 по подушке (защищает арматуру и даёт ровное основание под фиксаторы)." : "Подушку застелить плёнкой 200 мкм, чтобы цементное молоко не уходило в песок.",
                "Обратная засыпка пазух после набора прочности и гидроизоляции — песком (на пучинистом грунте — обязательно непучинистым), слоями с трамбовкой.",
            ]
        case .slab:
            let s = r.slab
            let cushA = s.area + s.perimeter * 0.3
            let pitD = max(0, p.slabCushion + max(0, s.t - 0.15) - p.topsoil)
            excav = cushA * pitD
            sandV = s.sand; geotex = cushA * 1.1
            backfill = 0
            s2.steps = [
                "Котлован под плиту и подушку: \(fmt(cushA, 1)) м² (плита + 0.3 м по периметру), глубина \(fmt(pitD)) м от спланированного основания.",
                "Дно спланировать и уплотнить, уложить геотекстиль ≥ 150 г/м².",
                "Подушка \(Int(p.slabCushion * 1000)) мм: песок средней крупности (или ПГС) слоями по 150 мм с трамбовкой виброплитой; верх подушки выводится в горизонт по нивелиру (±10 мм).",
                "Проложить коммуникации (вводы воды, канализация, гильзы под кабели) до утепления и армирования.",
                p.soil.heave != .none ? "Утепление ЭППС 100 мм (плотность ≥ 30 кг/м³) по подушке со сдвигом швов + утеплённая отмостка 1.2 м по периметру." : "По подушке — плёнка 200 мкм или подбетонка 50 мм.",
            ]
        case .piles:
            let s = r.piles
            let drill = Double(s.positions.count) * .pi * s.d * s.d / 4 * s.L
            excav = drill
            s2.steps = [
                "Разметить центры свай по шнурам (\(s.positions.count) шт.) и закрепить колышками.",
                s.type == .screw
                    ? "Завинтить сваи на глубину \(fmt(s.L)) м строго вертикально (контроль уровнем на двух гранях), не выкручивать обратно. Отклонение от вертикали ≤ 2°."
                    : "Пробурить скважины Ø\(Int(s.d * 1000)) мм на глубину \(fmt(s.L)) м\(s.type == .boredEnlarged ? " с уширением Ø\(Int(s.D * 1000)) мм (бур ТИСЭ)" : ""). Дно очистить от рыхлого грунта.",
                s.type == .screw ? "Заполнить стволы бетоном/ЦПР, отрезать оголовки в один уровень." : "Установить обсадную трубу из рубероида/ПВХ (снижает силы пучения), опустить арматурный каркас на фиксаторах.",
                "Под висячим ростверком оставить зазор 100–150 мм (пенополистирол / песок, удаляемый после бетонирования).",
            ]
        }
        s2.items = [WorkItem(name: kind == .piles ? "Объём выбуренного грунта" : "Разработка грунта", qty: excav, unit: "м³")]
        if kind == .piles {
            let s = r.piles
            if s.type == .screw {
                s2.items.append(WorkItem(name: "Сваи винтовые Ø\(Int(s.d * 1000))×\(fmt(s.L, 1)) м с оголовком", qty: Double(s.positions.count), unit: "шт", digits: 0, price: Price.screwPile(s.d)))
            } else {
                s2.items.append(WorkItem(name: "Рубероид (обсадка свай)", qty: Double(s.positions.count) * .pi * s.d * s.L * 1.15, unit: "м²", digits: 0, price: Price.ruberoidM2))
            }
        }
        if backfill > 0 { s2.items.append(WorkItem(name: "Песок для обратной засыпки", qty: backfill * 1.2, unit: "м³", note: "с учётом уплотнения", price: Price.sandM3)) }
        if sandV > 0 {
            s2.items.append(WorkItem(name: "Песок для подушки (в плотном теле)", qty: sandV, unit: "м³"))
            s2.items.append(WorkItem(name: "Песок к заказу (Купл 1.2)", qty: sandV * 1.2, unit: "м³", note: "≈ \(fmt(sandV * 1.2 * 1.5, 1)) т"))
        }
        if geotex > 0 { s2.items.append(WorkItem(name: "Геотекстиль ≥ 150 г/м²", qty: geotex * 1.15, unit: "м²", digits: 0)) }
        if prepV > 0 { s2.items.append(WorkItem(name: "Бетон B7.5 для подготовки", qty: prepV * 1.05, unit: "м³", digits: 2)) }
        w.sections.append(s2)

        // --- 3. Опалубка ---
        var s3 = WorkSection(title: "Опалубка", icon: "square.stack.3d.up")
        var faceLen = 0.0, height = 0.0, bottomDeck = 0.0, ties = 0, studs = 0.0
        switch kind {
        case .strip:
            height = r.strip.H + 0.05
            faceLen = 2 * totalL + Double(p.rings.reduce(0) { $0 + $1.count }) * 0.8
            let rowsTies = height <= 0.6 ? 1 : height <= 1.2 ? 2 : 3
            ties = Int((totalL / 0.8).rounded(.up)) * rowsTies
        case .slab:
            height = r.slab.t + 0.1
            faceLen = r.slab.perimeter + 1
        case .piles:
            height = r.piles.hg + 0.05
            faceLen = 2 * totalL + 4
            bottomDeck = totalL * (r.piles.bg + 0.1)
            let rowsTies = height <= 0.6 ? 1 : 2
            ties = Int((totalL / 0.8).rounded(.up)) * rowsTies
        }
        let rows = Int((height / boardW - 1e-9).rounded(.up))
        let boardM = faceLen * Double(rows) + bottomDeck / boardW
        let nBoards = boards(boardM)
        let boardVol = Double(nBoards) * boardW * boardT * boardL
        let formA = faceLen * height + bottomDeck
        let nStuds = Int((faceLen / 0.6).rounded(.up))
        studs = Double(nStuds) * (height + 0.1)
        let braces = Int((faceLen / 1.0).rounded(.up))
        let plywood = Int((formA / (1.22 * 2.44) * 1.1).rounded(.up))
        s3.steps = [
            "Щиты из обрезной доски 25×150 (\(plural(rows, "доска", "доски", "досок")) по высоте \(Int(height * 1000)) мм), сбитые брусками 50×50 через 600 мм. Альтернатива — ламинированная фанера 18 мм (\(plural(plywood, "лист", "листа", "листов")) 1220×2440).",
            "Внутреннюю поверхность щитов застелить плёнкой — бетон не теряет воду, доска остаётся чистой для повторного использования.",
            kind == .slab
                ? "Торцевые щиты по периметру плиты закрепить кольями через 600 мм и подкосами через 1 м. Верх щита выставить по нивелиру точно на отметку верха плиты — он будет маяком."
                : "Щиты установить по шнурам, расстояние между ними фиксировать шпильками М12 в ПВХ-трубках через 800 мм (\(ties) шт.) или распорками; подкосы 50×50 через 1 м с обеих сторон.",
            "Проверить вертикальность щитов уровнем (отклонение ≤ 5 мм на 1 м) и геометрию по диагоналям.",
            "Заложить гильзы под вводы коммуникаций и продухи (если пол по балкам), закладные под анкеры.",
        ]
        if kind == .piles { s3.steps.insert("Днище ростверка — настил из досок на временных опорах через 600 мм поверх зазора 100–150 мм (или несъёмный пенополистирол 100 мм).", at: 1) }
        s3.items = [
            WorkItem(name: "Площадь опалубки", qty: formA, unit: "м²"),
            WorkItem(name: "Доска обрезная 25×150×6000", qty: Double(nBoards), unit: "шт", note: "\(fmt(boardVol, 2)) м³", digits: 0),
            WorkItem(name: "Брусок 50×50 (стойки щитов)", qty: studs * 1.1, unit: "м.п.", digits: 0),
            WorkItem(name: "Брусок 50×50 (подкосы 1 м + колья 0.6 м)", qty: Double(braces) * 1.6, unit: "м.п.", digits: 0),
            WorkItem(name: "Гвозди 4×100 / саморезы", qty: formA * 0.25, unit: "кг"),
            WorkItem(name: "Плёнка 150–200 мкм", qty: (formA + (kind == .strip ? totalL * (r.strip.ext?.b ?? 0.4) : 0)) * 1.15, unit: "м²", digits: 0),
        ]
        if ties > 0 {
            s3.items.append(WorkItem(name: "Шпилька М12 + 2 гайки + 2 шайбы", qty: Double(ties), unit: "компл", digits: 0))
            let tieLen = (kind == .strip ? (r.strip.ext?.stemW ?? 0.4) : r.piles.bg) + 0.15
            s3.items.append(WorkItem(name: "Трубка ПВХ Ø20 под шпильки", qty: Double(ties) * tieLen, unit: "м", digits: 0))
        }
        w.sections.append(s3)

        // --- 4. Армирование ---
        var s4 = WorkSection(title: "Армирование", icon: "line.3.crossed.swirl.circle")
        let rebar: [RebarItem]
        var nTies = 0, chairs = 0, stars = 0
        switch kind {
        case .strip:
            rebar = r.strip.rebar
            for sl in r.strip.lines {
                guard let sec = r.strip.section(sl.line) else { continue }
                let nCl = Int((sl.line.length / sec.clampStep).rounded(.up)) + 1
                nTies += nCl * (sec.topN + sec.botN + sec.sideRows * 2)
                if sec.isT && sec.soleD > 0 { nTies += (Int((sl.line.length / sec.soleStep).rounded(.up)) + 1) * sec.botN }
                chairs += Int((sl.line.length / 0.8).rounded(.up)) * 2
                stars += Int((sl.line.length / 1.0).rounded(.up)) * 2
            }
        case .slab:
            rebar = r.slab.rebar
            let perFace = Int(r.slab.area / (r.slab.step * r.slab.step))
            nTies = perFace * 2 + Int((r.slab.area * 1.5).rounded()) * 4
            chairs = Int((r.slab.area * 4).rounded(.up))
            stars = Int((r.slab.perimeter / 1.0).rounded(.up))
        case .piles:
            rebar = r.piles.rebar
            let nSt = r.piles.lines.reduce(0) { $0 + Int(($1.line.length / r.piles.stirStep).rounded(.up)) + 1 }
            nTies = nSt * (r.piles.topN + r.piles.botN)
            if r.piles.type != .screw { nTies += r.piles.positions.count * (Int((r.piles.L / 0.4).rounded(.up)) + 1) * r.piles.cageN }
            chairs = Int((totalL / 0.8).rounded(.up)) * 2
            stars = Int((totalL / 1.0).rounded(.up)) * 2 + (r.piles.type == .screw ? 0 : r.piles.positions.count * 3 * Int((r.piles.L / 1.5).rounded(.up)))
        }
        nTies = Int(Double(nTies) * 1.1)
        let wireKg = Double(nTies) * 0.3 * wireKgPerM
        let byD = Dictionary(grouping: rebar, by: { "\($0.d)|\($0.cls)" }).sorted { ($0.value.first?.d ?? 0) < ($1.value.first?.d ?? 0) }
        let cover = kind == .strip ? (r.strip.ext?.cover ?? 0.04) : kind == .slab ? r.slab.cover : r.piles.cover
        s4.steps = [
            "Каркасы вязать вязальной проволокой Ø1.2 мм (крючком или пистолетом); сварка для А500С допустима, для А400 — не рекомендуется (пережог).",
            "Защитный слой \(Int(cover * 1000)) мм: снизу — пластиковые «стульчики» \(Int(cover * 1000)) мм, по бокам — «звёздочки» на хомутах. Арматура не должна касаться грунта, плёнки и щитов.",
            "Нахлёст стержней — не меньше расчётного (см. «Расчёт»), стыки разносить вразбежку: в одном сечении не более 50 % стержней.",
            kind == .slab
                ? "Нижняя сетка — на стульчики, верхняя — на поддерживающие каркасы «лягушки» (≈1.5 шт/м²). По торцам — П-образные стержни, связывающие сетки."
                : "В углах и примыканиях — Г-образные и П-образные стержни с полками на длину нахлёста, а не простое пересечение прямых стержней.",
            "Перед бетонированием проверить: шаг, диаметры, защитный слой, надёжность вязки (каркас не должен «гулять» при хождении).",
        ]
        for (_, items) in byD {
            guard let f = items.first else { continue }
            let len = items.reduce(0) { $0 + $1.length } * 1.05
            let n = Int((len / 11.7).rounded(.up))
            s4.items.append(WorkItem(name: "Арматура Ø\(f.d) \(f.cls)", qty: len, unit: "м", note: "\(plural(n, "пруток", "прутка", "прутков")) × 11.7 м ≈ \(fmt(len * Bar.mass(f.d), 0)) кг", digits: 0))
        }
        s4.items += [
            WorkItem(name: "Вязальная проволока Ø1.2 мм", qty: max(1, wireKg), unit: "кг", note: "\(nTies) узлов × 0.3 м"),
            WorkItem(name: "Фиксатор «стульчик» \(Int(cover * 1000)) мм", qty: Double(chairs), unit: "шт", digits: 0),
            WorkItem(name: "Фиксатор «звёздочка» \(Int(cover * 1000)) мм", qty: Double(stars), unit: "шт", digits: 0),
        ]
        w.sections.append(s4)

        // --- 5. Маяки и нивелировка ---
        var s5 = WorkSection(title: "Маяки и выравнивание верха", icon: "level")
        var beaconCount = 0
        switch kind {
        case .strip, .piles:
            for (a, b, wd) in w.scheme.footprint {
                let d = (b - a).unit, n = V2(-d.y, d.x), L = (b - a).len
                let k = max(1, Int((L / 1.2).rounded(.up)))
                for i in 0...k {
                    for s in [-wd / 2, wd / 2] { w.scheme.beacons.append(a + d * (L * Double(i) / Double(k)) + n * s) }
                }
            }
            beaconCount = w.scheme.beacons.count
            let topMark = kind == .strip ? p.plinth : 0.15 + r.piles.hg
            s5.steps = [
                "От репера лазерным нивелиром (или гидроуровнем) перенести отметку верха \(kind == .strip ? "ленты" : "ростверка") +\(fmt(topMark)) м на внутренние грани щитов.",
                "По отметкам вбить гвозди / вкрутить саморезы через каждые 1.0–1.2 м с обеих сторон (\(beaconCount) шт.) и отбить линию маркером или малярным шнуром.",
                "Удобный способ: прибить по линии рейку 20×40 мм (маячную рейку) — её верх и будет уровнем заливки, по ней ведут правило.",
                "Бетон подавать до линии с небольшим избытком, проработать глубинным вибратором, затем стянуть излишек правилом 1.5–2 м, опирая его на маячные рейки/верх щитов.",
                "Через 30–60 минут, когда уйдёт вода, затереть кельмой/тёркой. Проверить двухметровой рейкой: местные неровности ≤ 5 мм, отклонение верха от горизонтали на всю длину ≤ 10 мм (под кладку газобетона — чем точнее, тем тоньше клеевой шов).",
            ]
        case .slab:
            let step = 1.5
            let (blo, bhi) = Geo.bbox(r.slab.rings)
            var y = blo.y + 0.75
            while y < bhi.y {
                var x = blo.x + 0.75
                while x < bhi.x {
                    if Geo.contains(V2(x, y), r.slab.rings) { w.scheme.beacons.append(V2(x, y)) }
                    x += step
                }
                y += step
            }
            beaconCount = w.scheme.beacons.count
            s5.steps = [
                "Верх торцевой опалубки выставить по лазерному нивелиру точно на отметку верха плиты +0.150 — это краевые маяки.",
                "Внутри плиты — точечные маяки по сетке 1.5 × 1.5 м (\(beaconCount) шт.): стержни Ø12 с пластиковым колпачком (или регулируемые маяки на винтовых опорах), закреплённые к арматуре и выставленные лазером на отметку верха.",
                "Вариант для больших плит: маячные трубы/профили 20×40 на опорах через 1.5–2 м — по ним ведут виброрейку или правило 3 м, после стягивания трубы вынимают, борозды заделывают.",
                "Бетонировать полосами от дальнего края, уплотнять глубинным вибратором, стягивать правилом/виброрейкой по маякам.",
                "Затирка: через 3–6 ч (когда след ноги ≤ 3–4 мм) — затирочная машина «вертолёт» или вручную. Контроль рейкой 2 м: неровности ≤ 5 мм.",
            ]
        }
        s5.items = [
            WorkItem(name: kind == .slab ? "Точечные маяки" : "Метки верха (саморезы/гвозди)", qty: Double(beaconCount), unit: "шт", digits: 0),
            WorkItem(name: "Правило алюминиевое", qty: kind == .slab ? 3 : 2, unit: "м", note: "длина"),
        ]
        if kind != .slab { s5.items.append(WorkItem(name: "Маячная рейка 20×40", qty: faceLen * 1.05, unit: "м.п.", digits: 0)) }
        w.sections.append(s5)

        // --- 6. Бетонирование и уход ---
        var s6 = WorkSection(title: "Бетонирование и уход", icon: "drop")
        let vConcrete: Double
        switch kind {
        case .strip: vConcrete = r.strip.concrete
        case .slab: vConcrete = r.slab.concrete
        case .piles: vConcrete = r.piles.concrete + r.piles.grillageConcrete
        }
        let vOrder = vConcrete * 1.03
        let trucks = Int((vOrder / 7).rounded(.up))
        s6.steps = [
            "Заказать бетон \(p.concrete.title), подвижность П3–П4, \(fmt(vOrder, 1)) м³ (с запасом 3 %) — \(plural(trucks, "миксер", "миксера", "миксеров")) по 7 м³. Проверить накладную: класс, марка по морозостойкости F150, водонепроницаемости W6.",
            kind == .piles && r.piles.type != .screw
                ? "Сначала забетонировать сваи (с уплотнением вибратором или штыкованием), затем ростверк — не позже чем через 1–2 часа или с выпусками арматуры из свай."
                : "Заливать непрерывно, слоями 30–40 см по всему периметру, без холодных швов. Если перерыв неизбежен — шов делать вертикальным, вне углов.",
            "Каждый слой прорабатывать глубинным вибратором (шаг 30–40 см, до выхода цементного молока), не касаясь арматуры.",
            "Уход: первые 7 суток поддерживать влажность (поливать, укрыть плёнкой/мешковиной), защищать от солнца и мороза. При t < +5 °C — противоморозные добавки и прогрев.",
            "Распалубка боковых щитов — через 3–5 суток при +15…+20 °C. Нагружать стенами — после набора 70 % прочности (≈ 7–10 суток при +20 °C, при +10 °C — около 2–3 недель).",
            "Гидроизоляция: по верху — 2 слоя наплавляемого материала под стены; боковые поверхности — битумная мастика в 2 слоя, затем обратная засыпка.",
        ]
        s6.items = [
            WorkItem(name: "Бетон \(p.concrete.title)", qty: vOrder, unit: "м³", note: "\(trucks) × 7 м³", digits: 2),
            WorkItem(name: "Доставка бетона миксером", qty: Double(trucks), unit: "рейс", digits: 0, price: Price.mixerTrip),
            WorkItem(name: "Глубинный вибратор (аренда)", qty: 2, unit: "сут", digits: 0, price: Price.vibratorRent),
        ]
        var waterTop = 0.0, mastic = 0.0
        if kind == .strip {
            waterTop = r.strip.lines.reduce(0) { $0 + $1.line.length * (r.strip.section($1.line)?.stemW ?? 0.4) } * 2 * 1.15
            mastic = (r.strip.lines.filter { $0.line.isExterior }.reduce(0) { $0 + $1.line.length }) * r.strip.H * 2 * 1.5
        } else if kind == .piles {
            waterTop = totalL * r.piles.bg * 2 * 1.15
        }
        if waterTop > 0 { s6.items.append(WorkItem(name: "Наплавляемая гидроизоляция (2 слоя)", qty: waterTop, unit: "м²", note: "\(Int((waterTop / 10).rounded(.up))) рул. × 10 м²", digits: 0)) }
        if mastic > 0 { s6.items.append(WorkItem(name: "Битумная мастика", qty: mastic, unit: "кг", digits: 0)) }
        let eps = kind == .strip ? r.strip.eps : kind == .slab && p.soil.heave != .none ? r.slab.eps : 0
        if eps > 0 { s6.items.append(WorkItem(name: "ЭППС 100 мм", qty: eps, unit: "м²", note: "≈ \(fmt(eps * 0.1, 1)) м³", digits: 0)) }
        w.sections.append(s6)

        // --- 7. Отмостка и дренаж ---
        let dr = Drainage.make(p, r, kind: kind)
        var s7 = WorkSection(title: "Отмостка и дренаж (защита от пучения)", icon: "drop.triangle")
        s7.steps = dr.steps
        s7.items = dr.items
        w.sections.append(s7)

        // --- Цены ---
        for i in w.sections.indices {
            for j in w.sections[i].items.indices where w.sections[i].items[j].price == 0 {
                w.sections[i].items[j].price = unitPrice(w.sections[i].items[j], p)
            }
        }

        // --- Ведомость закупки ---
        for s in w.sections {
            for it in s.items where !["Площадь расчистки", "Объём снимаемого растительного слоя", "Разработка грунта", "Объём выбуренного грунта",
                                      "Песок для подушки (в плотном теле)", "Площадь опалубки", "Земляные работы под дренаж (объём)"].contains(it.name) {
                w.purchase.append(it)
            }
        }
        w.summary = [
            ("Габарит фундамента", "\(fmt(fw, 2)) × \(fmt(fh, 2)) м"),
            ("Площадка", "\(fmt(sHi.x - sLo.x, 1)) × \(fmt(sHi.y - sLo.y, 1)) м"),
            ("Снятие грунта", "\(Int(p.topsoil * 100)) см, \(fmt(topsoilV, 1)) м³"),
            ("Бетон", "\(fmt(vOrder, 1)) м³ (\(trucks) миксер.)"),
            ("Арматура", "\(fmt(rebar.reduce(0) { $0 + $1.mass } * 1.05, 0)) кг"),
            ("Доска 25×150×6", "\(nBoards) шт"),
            ("Отмостка", "\(Int(dr.width * 100)) см\(dr.insulated ? ", утеплённая" : ""), \(fmt(dr.blindArea, 0)) м²"),
            ("Дренаж", "\(dr.drainRequired ? "обязателен" : "рекомендуется"), \(fmt(dr.drainLength, 0)) м"),
            ("Материалы итого", "≈ " + rub(w.purchase.reduce(0) { $0 + $1.cost })),
        ]
        return w
    }
}
