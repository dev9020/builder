import Foundation

/// Схема/чертёж в проекте
enum FigKind: Hashable {
    case sitePlan, layout
    case stripSection, slabSection, pileSection
    case rebarCorner, rebarTee, rebarLap, slabEdge, pileCage
    case sillNode, anchorPlan
    case joistPlan(Int), floorPie
    case wallElevation(Int)
    case cornerNode, teeNode, bracing
    case openingNode, windowInstall
    case rafterPlan, eaveNode, ridgeNode, roofPie
    case wallPie
    case wallSection, wallPlan, sheetLayout(Int, Int), fasteners, sillSteps, rigidity
    case floorSection, heatingLoop
    case furniturePlan, plumbingPlan, siteNetworks, sewerProfile
}

/// Таблица в этапе (например, точки водоснабжения)
struct StageTable {
    let head: [String]
    let rows: [[String]]
}

/// Крепёж этапа: что крепим → чем (что купить) → чем закручивать/забивать
struct Fastener: Identifiable {
    let id = UUID()
    let what: String
    let item: String
    let how: String
}

struct Figure: Identifiable {
    let id = UUID()
    let kind: FigKind
    let title: String
    var aspect = 0.62          // высота / ширина
}

struct BuildStage: Identifiable {
    let id = UUID()
    var number = 0
    let title: String
    let icon: String
    let scene: Stage3D
    var goal = ""
    var steps: [String] = []
    var decisions: [Decision] = []
    var figures: [Figure] = []
    var items: [WorkItem] = []
    var tools: [String] = []
    var guides: [Guide] = []
    var fasteners: [Fastener] = []
    var when = ""              // когда делается / что решить заранее
    var table: StageTable? = nil
}

struct OpeningRow: Identifiable {
    let id = UUID()
    let wall: String
    let opening: Opening
    let block: StdBlock
    let header: Timber.BeamCheck?
    var standard: Bool { abs(block.roW - opening.width) < 0.015 && abs(block.roH - opening.height) < 0.015 }
}

struct BuildPlan {
    var frame = Framing()
    var works = WorkPlan()
    var stages: [BuildStage] = []
    var lumber: [FrameGen.TakeoffRow] = []
    var openings: [OpeningRow] = []
    var groups: [(title: String, items: [WorkItem])] = []
    var gsop = 0.0, rWall = 0.0, rRoof = 0.0, rFloor = 0.0, rWindow = 0.0
    var woolWall = 0.15, woolRoof = 0.2, woolFloor = 0.2
    var wallNet = 0.0, wallGross = 0.0, partitionArea = 0.0, openingArea = 0.0
    var kit: [KitRow] = []
    var layout = HouseLayout()
    var checks: [ModuleCheck] = []
    var total: Double { groups.reduce(0) { $0 + $1.items.reduce(0) { $0 + $1.cost } } }

    static func make(_ p: Project, _ r: CalcResults) -> BuildPlan {
        var b = BuildPlan()
        let F = FrameGen.make(p, r)
        b.frame = F
        b.layout = HouseLayout.make(p, r, F)
        b.works = Works.plan(p, r)
        b.lumber = FrameGen.takeoff(F.members)
        let kind = p.selectedFoundation
        let floors = max(p.floors, 1)
        let area = r.loads.floorArea
        let D = F.studExt.wm

        // --- теплозащита (СП 50.13330.2024, СП 131.13330.2020) ---
        b.gsop = p.climate.gsop
        b.rWall = Thermal.rWall(b.gsop); b.rRoof = Thermal.rRoof(b.gsop); b.rFloor = Thermal.rFloor(b.gsop); b.rWindow = Thermal.rWindow(b.gsop)
        b.woolWall = Thermal.woolThickness(b.rWall)
        b.woolRoof = Thermal.woolThickness(b.rRoof)
        b.woolFloor = Thermal.woolThickness(b.rFloor)

        // --- площади ---
        let perim = p.segments.reduce(0) { $0 + $1.length }
        let gables = r.loads.fronton.reduce(0, +)
        b.wallGross = perim * (F.wallHeights.reduce(0, +) + Double(floors - 1) * 0.25) + gables
        let ops = p.validOpenings
        for o in ops {
            if case .edge = o.host { b.openingArea += o.width * o.height * (o.kind.isDoor ? 1 : Double(floors)) }
        }
        b.wallNet = max(0, b.wallGross - b.openingArea)
        b.partitionArea = p.partitions.reduce(0) { $0 + $1.length } * F.wallHeights.reduce(0, +)

        // --- проёмы ---
        for o in ops {
            var wall = "", ext = false
            switch o.host {
            case .edge(let i): ext = true; wall = p.segments.firstIndex { $0.edge == i }.map { "Н\($0 + 1)" } ?? "Н"
            case .partition(let id): wall = p.partitions.firstIndex { $0.id == id }.map { "П\($0 + 1)" } ?? "П"
            }
            let h = F.headers.first { $0.opening.id == o.id }
            b.openings.append(OpeningRow(wall: wall, opening: o, block: StdBlock.nearest(o, exterior: ext), header: h?.check))
        }

        b.stages = stages(p, r, &b)
        for i in b.stages.indices {
            b.stages[i].number = i + 1
            for j in b.stages[i].items.indices where b.stages[i].items[j].price == 0 {
                b.stages[i].items[j].price = Works.unitPrice(b.stages[i].items[j], p)
            }
        }

        // --- сводная ведомость по отделам магазина ---
        let skip: Set<String> = ["Площадь расчистки", "Объём снимаемого растительного слоя", "Разработка грунта", "Объём выбуренного грунта",
                                 "Песок для подушки (в плотном теле)", "Площадь опалубки", "Земляные работы под дренаж (объём)"]
        var groups: [String: [WorkItem]] = [:]
        var order: [String] = []
        for s in b.stages {
            for it in s.items where !skip.contains(it.name) && it.qty > 0 {
                let g = group(it.name, kind: kind)
                if groups[g] == nil { order.append(g) }
                groups[g, default: []].append(it)
            }
        }
        let pref = ["Фундамент: бетон и арматура", "Сыпучие, гидро- и теплоизоляция фундамента", "Пиломатериалы", "Плиты ОСП, ГКЛ", "Утеплитель, мембраны, плёнки",
                    "Крепёж и метизы", "Окна и двери", "Кровля", "Фасад", "Инженерные сети (черновые)", "Водоснабжение и канализация", "Полы и тёплый пол", "Сантехприборы", "Внутренняя отделка", "Прочее"]
        b.groups = pref.compactMap { g in groups[g].map { (g, merge($0)) } } + order.filter { !pref.contains($0) }.map { ($0, merge(groups[$0]!)) }
        b.kit = Kit.make(p, r, b)
        b.checks = p.moduleChecks(b)
        _ = area; _ = D
        return b
    }

    /// Одинаковые позиции из разных этапов складываются
    static func merge(_ items: [WorkItem]) -> [WorkItem] {
        var out: [WorkItem] = []
        for it in items {
            if let i = out.firstIndex(where: { $0.name == it.name && $0.unit == it.unit }) {
                let o = out[i]
                out[i] = WorkItem(name: o.name, qty: o.qty + it.qty, unit: o.unit, note: o.note, digits: o.digits, price: o.price)
            } else { out.append(it) }
        }
        return out
    }

    static func group(_ n: String, kind: FoundationKind) -> String {
        let l = n.lowercased()
        if ["унитаз", "раковина с", "душевой", "ванна акрил", "кухонная мойка", "кран и сифон"].contains(where: { l.contains($0) }) { return "Сантехприборы" }
        if ["для водоснабжения", "pe-xa 25", "коллектор хв", "коллектор гв", "водорозетк", "теплоизоляция труб", "канализацион", "ревизия ø110", "аэратор", "фильтры:", "бойлер косв", "водонагреватель", "скважин", "кессон", "гидроаккумулятор", "пнд 32", "гильза ввода", "септик", "станция биол", "накопительная ёмкость", "инфильтратор", "греющий кабель для водопровода", "колодец ревизионный", "обсыпки труб"].contains(where: { l.contains($0) }) { return "Водоснабжение и канализация" }
        let floorKeys = ["ламинат", "кварцвинил", "инженерная доска", "керамогранит", "подложка 2", "подложка для", "1185×585", "плинтус", "pe-xa", "коллектор", "гвл элемент", "элементов пола", "стяжк", "фиброволокно", "маячный", "тёпл", "терморегулятор", "нагревательн", "инфракрасная", "плиточный", "затирка", "свп", "скоба-гарпун", "фитинги", "клей 2к", "кромочная"]
        if floorKeys.contains(where: { l.contains($0) }) { return "Полы и тёплый пол" }
        if ["кабель", "металлорукав", "подрозетник", "щит с автомат", "водоснабжения", "канализация пп"].contains(where: { l.contains($0) }) { return "Инженерные сети (черновые)" }
        if l.contains("вагонка") || l.contains("кляммер") || l.contains("масло-воск") || l.contains("шпаклёвка") { return "Внутренняя отделка" }
        if l.hasPrefix("бетон") || l.hasPrefix("арматура") || l.contains("миксер") || l.contains("вибратор") || l.contains("фиксатор") || l.contains("вязальная") { return "Фундамент: бетон и арматура" }
        if l.hasPrefix("песок") || l.hasPrefix("геотекстиль") || l.hasPrefix("щебень") || l.hasPrefix("эппс") || l.contains("наплавляем") || l.contains("мастика") || l.contains("дренаж") || l.contains("колодец") || l.contains("плитка") || l.contains("бордюр") || l.contains("цпс") || l.contains("рубероид") || l.contains("демпфер") || l.contains("ливн") || l.contains("дождеприём") || l.contains("канализац") { return "Сыпучие, гидро- и теплоизоляция фундамента" }
        if l.hasPrefix("доска") || l.hasPrefix("брус") || l.contains("рейка") || l.contains("столбики") || l.contains("имитация бруса") && false { return "Пиломатериалы" }
        if l.hasPrefix("осп") || l.hasPrefix("гкл") || l.hasPrefix("плита осп") || l.contains("гипсокартон") { return "Плиты ОСП, ГКЛ" }
        if l.contains("минерал") || l.contains("мембрана") || l.contains("пароизол") || l.contains("плёнка") || l.contains("лента") || l.contains("уплотн") || l.contains("антисептик") || l.contains("огнебио") { return "Утеплитель, мембраны, плёнки" }
        if l.contains("гвозд") || l.contains("саморез") || l.contains("шпильк") || l.contains("анкер") || l.contains("уголок") || l.contains("опора балки") || l.contains("скоба") || l.contains("болт") || l.contains("гайка") || l.contains("шнур") || l.contains("правило") || l.contains("метки") || l.contains("маяки") || l.contains("трубка") { return "Крепёж и метизы" }
        if l.contains("окон") || l.contains("дверн") || l.contains("портал") || l.contains("пена") || l.contains("псул") || l.contains("балконный") { return "Окна и двери" }
        if l.contains("кровел") || l.contains("покрытие") || l.contains("снегозадерж") || l.contains("водосточ") || l.contains("подкладочный") || l.contains("конёк") || l.contains("карниз") { return "Кровля" }
        if l.contains("фасад") || l.contains("сайдинг") || l.contains("имитац") || l.contains("кирпич") || l.contains("фиброцемент") || l.contains("штукатур") { return "Фасад" }
        return "Прочее"
    }

    // MARK: - Пиломатериалы этапа

    static func lumberItems(_ members: [Member], note: String = "") -> [WorkItem] {
        FrameGen.takeoff(members).map { row in
            let vol = row.volume
            return WorkItem(name: row.sec.shopName(row.stock) + (row.whole ? " — ставится целиком, без резки" : ""), qty: Double(row.pieces), unit: "шт",
                            note: "\(fmt(vol, 2)) м³; \(row.use)", digits: 0, price: Price.lumberM3(row.sec) * row.sec.tm * row.sec.wm * row.stock)
        }
    }

    // MARK: - Этапы

    static func stages(_ p: Project, _ r: CalcResults, _ b: inout BuildPlan) -> [BuildStage] {
        let F = b.frame
        let w = b.works
        let kind = p.selectedFoundation
        let floors = max(p.floors, 1)
        let D = F.studExt.wm
        let Dmm = F.studExt.w
        var out: [BuildStage] = []
        func sec(_ i: Int) -> WorkSection? { i < w.sections.count ? w.sections[i] : nil }
        func ms(_ f: (Member) -> Bool) -> [Member] { F.members.filter(f) }

        // 1. Документы и участок
        var s1 = BuildStage(title: "Документы, подготовка и разбивка участка", icon: "map", scene: .site)
        s1.goal = "Узаконить стройку, подготовить площадку, вынести оси дома на местность."
        s1.steps = [
            "До начала работ подать уведомление о планируемом строительстве ИЖС (Госуслуги / МФЦ / администрация). Через 7 рабочих дней придёт уведомление о соответствии. После окончания — уведомление об окончании строительства, затем технический план и регистрация.",
            "Заказать вынос границ участка в натуру у кадастрового инженера. Проверить в ПЗЗ/ГПЗУ отступы: обычно не менее 3 м до границы соседнего участка и 5 м до красной линии улицы.",
            "Противопожарное расстояние до дома на соседнем участке — по СП 4.13130.2013, табл. 1: для домов с деревянным каркасом (V степень огнестойкости) — 15 м; при меньшем — согласие соседей или блокировка с выполнением мер огнезащиты.",
            "Сделать инженерно-геологические изыскания (минимум 3 скважины/шурфа на 1.5–2 глубины заложения): грунт, УГВ, пучинистость. В программе приняты табличные значения — уточните их по изысканиям.",
            "Организовать подъезд для миксера и самосвала (ширина ≥ 3.5 м, твёрдое покрытие или щебень), временное электроснабжение 15 кВт, воду, бытовку, туалет, площадку складирования.",
            "Пиломатериал хранить под навесом на подкладках высотой ≥ 200 мм, с прокладками между рядами, не ближе 1 м к земле без защиты от влаги — чтобы не терял сушку и не грелся.",
        ] + (sec(0)?.steps ?? [])
        s1.decisions = [
            Decision(title: "Отступ дома от границы", value: "≥ 3 м", why: "минимум для жилого дома на участке, если ПЗЗ не устанавливают иное", ref: N.sp53.at("п. 6.7")),
            Decision(title: "Противопожарный разрыв", value: "15 м до соседнего дома", why: "дом V степени огнестойкости, класс С3", ref: N.sp4.at("п. 4.3, 4.13, табл. 1")),
            Decision(title: "Снятие растительного слоя", value: "\(Int(p.topsoil * 100)) см", why: "гумус сжимаем и пучинист, под фундамент не оставляется; складируется для благоустройства", ref: N.sp45.at("разд. «Подготовительные работы»")),
            Decision(title: "Уведомительный порядок", value: "уведомление ИЖС", why: "разрешение на строительство для ИЖС не требуется", ref: N.grk.code),
        ]
        s1.figures = [Figure(kind: .sitePlan, title: "Размещение дома на участке (отступы, противопожарные разрывы)", aspect: 0.62),
                      Figure(kind: .layout, title: "Схема разбивки: обноска, шнуры, маяки", aspect: 0.5)]
        s1.items = sec(0)?.items ?? []
        s1.tools = Guides.siteTools; s1.guides = Guides.site(p)
        s1.fasteners = Fasteners.site
        s1.steps.insert("Скважину лучше пробурить до начала стройки — будет вода для бетона, раствора и бытовки. Место — по схеме наружных сетей: в глубине участка, \(fmt(b.layout.wellToSeptic, 0)) м от будущего очистного сооружения (нужно ≥ \(Int(p.septic.wellDistance)) м), с подъездом буровой установки.", at: min(4, s1.steps.count))
        s1.figures.append(Figure(kind: .siteNetworks, title: "Скважина, септик и трассы на участке", aspect: 0.75))
        s1.when = "до начала стройки; изыскания и уведомление — за 1–2 месяца"
        s1.steps.append("Сразу решите, какой будет пол и отопление (\(p.floorSystemEff.short)\(p.floorHeating == .none ? "" : ", тёплый пол \(p.floorHeating == .water ? "водяной" : "электрический")")): \(p.floorSystemEff == .inSlab ? "трубы тёплого пола закладываются в плиту ДО бетонирования" : "от этого зависят гильзы под вводы в фундаменте и отметка пола") — см. раздел «Порядок строительства».")
        out.append(s1)

        // 2. Земляные работы
        var s2 = BuildStage(title: "Земляные работы и песчаная подушка", icon: "shovel", scene: .foundation)
        s2.goal = "Подготовить основание под фундамент без нарушения природной структуры грунта."
        s2.steps = sec(1)?.steps ?? []
        let dDepth = kind == .strip ? r.strip.depth : kind == .slab ? r.slab.t : r.piles.L
        s2.decisions = [
            Decision(title: kind == .piles ? "Длина свай" : "Глубина заложения", value: "\(fmt(dDepth)) м",
                     why: kind == .strip ? "dfn = \(fmt(r.strip.dfn)) м, df = \(fmt(r.strip.df)) м, грунт: \(p.soil.name.lowercased())" : "по расчёту несущей способности и пучения",
                     ref: kind == .piles ? N.sp24.at("разд. 7") : N.sp22.at("п. 5.5, табл. 5.3")),
            Decision(title: "Подушка", value: "песок средней крупности, Купл ≥ 0.95", why: "дренирующий непучинистый слой, послойное уплотнение 100–150 мм", ref: N.sp45.at("разд. «Уплотнение грунтов»")),
        ]
        switch kind {
        case .strip: s2.figures = [Figure(kind: .stripSection, title: "Сечение ленты с армированием", aspect: 0.9)]
        case .slab: s2.figures = [Figure(kind: .slabSection, title: "Разрез плиты и подушки", aspect: 0.5)]
        case .piles: s2.figures = [Figure(kind: .pileSection, title: "Свая и ростверк", aspect: 0.9)]
        }
        s2.items = sec(1)?.items ?? []
        s2.tools = Guides.earthTools; s2.guides = Guides.earth
        s2.when = "после разбивки и выноса осей на обноску"
        out.append(s2)

        // 3. Опалубка
        var s3 = BuildStage(title: "Опалубка", icon: "square.stack.3d.up", scene: .foundation)
        s3.goal = "Собрать щиты, которые выдержат давление бетона и дадут точную геометрию."
        s3.steps = sec(2)?.steps ?? []
        s3.decisions = [Decision(title: "Отклонение плоскостей опалубки", value: "≤ 5 мм на 1 м", why: "геометрия фундамента под обвязку каркаса", ref: N.sp70.at("разд. 5, опалубочные работы"))]
        s3.items = sec(2)?.items ?? []
        s3.tools = Guides.formTools; s3.guides = Guides.form
        s3.fasteners = Fasteners.form
        s3.when = "после подушки; до опалубки заказать арматуру и бетон"
        out.append(s3)

        // 4. Армирование
        var s4 = BuildStage(title: "Армирование фундамента (вязка каркасов)", icon: "line.3.crossed.swirl.circle", scene: .foundation)
        s4.goal = "Связать пространственный каркас, правильно выполнить углы, примыкания и нахлёсты."
        let lapMm = Int(r.strip.lap * 1000)
        s4.steps = (sec(3)?.steps ?? []) + {
            switch kind {
            case .strip: return [
                "Порядок вязки: на «стульчики» уложить нижние продольные стержни, надеть хомуты с шагом \(Int((r.strip.ext?.clampStep ?? 0.3) * 1000)) мм, подвязать верхние стержни, затем боковые. Хомут вяжется к каждому продольному стержню в каждом пересечении.",
                "Угол ленты: продольные стержни не обрываются в углу — устанавливаются Г-образные стержни того же диаметра с полками \(lapMm) мм в каждую сторону (наружный и внутренний ряды), см. схему.",
                "Т-образное примыкание: стержни примыкающей ленты заводятся в основную ленту П-образными или Г-образными элементами с анкеровкой \(lapMm) мм за ось.",
                "Нахлёст прямых стержней — \(lapMm) мм, вязка в 3 точках (по краям и в середине нахлёста). Стыки соседних стержней сдвигать на 1.3 длины нахлёста.",
            ]
            case .slab: return [
                "Нижняя сетка Ø\(r.slab.d) шаг \(Int(r.slab.step * 1000)) мм на «стульчиках» \(Int(r.slab.cover * 1000)) мм; вяжется каждое пересечение по периметру и через одно в поле.",
                "Верхняя сетка — на поддерживающих каркасах («лягушках») из Ø10–12 через 0.8–1 м.",
                "По торцам плиты — П-образные стержни, охватывающие обе сетки, с шагом основной сетки.",
                "Под несущими стенами — усиление дополнительными стержнями (если требуется по расчёту), в местах выпусков коммуникаций — обрамление отверстий.",
            ]
            case .piles: return [
                "Каркас сваи: \(r.piles.cageN)Ø\(r.piles.cageD) с кольцами Ø6–8 через 400 мм; выпуски над сваей — на длину анкеровки в ростверк (не менее 30d).",
                "Каркас ростверка вяжется как лента: нижние и верхние стержни, хомуты Ø\(r.piles.stirD) шаг \(Int(r.piles.stirStep * 1000)), Г-образные стержни в углах.",
            ]
            }
        }()
        s4.decisions = [
            Decision(title: "Арматура", value: "\(p.rebar.rawValue), бетон \(p.concrete.title)", why: "класс по расчёту на изгиб и поперечную силу", ref: "\(N.sp63.at("разд. 6, 8")), \(N.g34028.code)"),
            Decision(title: "Защитный слой", value: "\(Int((kind == .strip ? r.strip.ext?.cover ?? 0.04 : kind == .slab ? r.slab.cover : r.piles.cover) * 1000)) мм",
                     why: p.concretePrep ? "фундамент на бетонной подготовке" : "без подготовки защитный слой увеличен", ref: N.sp63.at("п. 10.3.1–10.3.2")),
            Decision(title: "Нахлёст и анкеровка", value: "\(lapMm) мм", why: "по ф. 10.1 с учётом η1, η2 для \(p.rebar.rawValue)", ref: N.sp63.at("п. 10.3.24–10.3.31")),
            Decision(title: "Минимальное армирование", value: "μ ≥ 0.1 %", why: "продольная арматура ленты", ref: N.sp63.at("п. 10.3.6")),
            Decision(title: "Соединение стержней", value: "вязка проволокой Ø1.2", why: "сварка ручной дугой прихватками ослабляет стержни, для А400 недопустима", ref: N.sp70.at("разд. 5, арматурные работы")),
        ]
        switch kind {
        case .strip: s4.figures = [Figure(kind: .rebarCorner, title: "Армирование угла ленты: Г-образные стержни", aspect: 0.75),
                                   Figure(kind: .rebarTee, title: "Армирование Т-образного примыкания", aspect: 0.75),
                                   Figure(kind: .rebarLap, title: "Нахлёст стержней и вязка", aspect: 0.32),
                                   Figure(kind: .stripSection, title: "Сечение ленты: хомуты, фиксаторы, защитный слой", aspect: 0.9)]
        case .slab: s4.figures = [Figure(kind: .slabEdge, title: "Край плиты: сетки, П-образные стержни, «лягушки»", aspect: 0.5),
                                  Figure(kind: .rebarLap, title: "Нахлёст стержней и вязка", aspect: 0.32)]
        case .piles: s4.figures = [Figure(kind: .pileCage, title: "Каркас сваи и выпуски в ростверк", aspect: 0.9),
                                   Figure(kind: .rebarCorner, title: "Угол ростверка: Г-образные стержни", aspect: 0.75)]
        }
        s4.items = sec(3)?.items ?? []
        s4.tools = Guides.rebarTools; s4.guides = Guides.rebar
        s4.fasteners = Fasteners.rebar
        s4.when = "внутри собранной опалубки; до заливки — гильзы под вводы и закладные"
        let L0 = b.layout
        s4.steps.append("Перед бетонированием заложить гильзы (труба ПВХ/ПНД Ø110–160) — сверлить фундамент потом трудно и опасно для арматуры: ввод воды — стена \(L0.entryWall), \(fmt(L0.entryOffset, 2)) м от начала стены, на глубине \(fmt(min(L0.waterDepth, 1.2), 2)) м; выпуск канализации — стена \(L0.outletWall), \(fmt(L0.outletOffset, 2)) м, низ на \(fmt(L0.outletDepth, 2)) м ниже земли; кабель — рядом с вводом воды.")
        if kind == .slab {
            s4.steps.append("Плита: канализация под плитой (Ø110 от унитазов, Ø50 от остальных приборов, уклоны 2 % и 3 %) укладывается в песчаную подушку ДО армирования, выводы — на 100–150 мм выше будущего чистого пола, заглушены; места выводов — точно по схеме разводки (±20 мм). Водопроводные трубы — в гофре через плиту в зоне коллектора.")
            s4.figures.append(Figure(kind: .plumbingPlan, title: "Разводка под плитой: выводы канализации и ввод воды", aspect: 0.75))
        }
        if p.floorSystemEff == .inSlab {
            let ha = FloorWorks.heatedArea(p, r), n = FloorWorks.loops(ha)
            s4.steps += ["Тёплый пол в плите (УШП): трубы PE-Xa 16 мм вяжутся к верхней сетке пластиковыми хомутами через 500 мм, «улиткой» шаг 150 у стен и 200 в центре, \(n) петель ≤ 15 м² каждая, выводы к коллектору — в гофре через плиту.",
                         "Опрессовать петли 6 бар 24 ч и бетонировать под давлением 3 бар. Схему петель сфотографировать с рулеткой — потом в плиту нельзя сверлить наугад."]
            s4.items += FloorWorks.baseItems(p, r, area: r.loads.floorArea, perim: 0).filter { !$0.name.contains("Коллектор") && !$0.name.contains("Шкаф") && !$0.name.contains("Фитинги") }
            s4.items.append(WorkItem(name: "Труба PE-Xa 16×2.0 с антидиффузионным слоем (в плиту)", qty: ha / 0.17 * 1.1 + Double(n) * 8, unit: "м", note: "\(n) петель", digits: 0, price: 75))
            s4.figures.append(Figure(kind: .heatingLoop, title: "Петля тёплого пола в плите «улиткой»", aspect: 0.62))
        }
        out.append(s4)

        // 5. Бетонирование
        var s5 = BuildStage(title: "Маяки, бетонирование, уход, гидроизоляция", icon: "drop", scene: .foundation)
        s5.goal = "Залить без холодных швов, вывести верх в горизонт, дать бетону набрать прочность."
        s5.steps = (sec(4)?.steps ?? []) + (sec(5)?.steps ?? [])
        s5.decisions = [
            Decision(title: "Бетонная смесь", value: "\(p.concrete.title), П3–П4, F150, W6", why: "класс по расчёту, морозостойкость для фундаментов в зоне промерзания", ref: "\(N.g7473.code), \(N.g26633.code)"),
            Decision(title: "Распалубка и загрузка", value: "≥ 70 % прочности", why: "до нагружения каркасом", ref: N.sp70.at("разд. 5, бетонные работы")),
            Decision(title: "Горизонтальность верха", value: "±10 мм на длину стены", why: "обвязка каркаса ложится без подкладок", ref: N.sp70.at("разд. 5, допуски")),
        ]
        s5.items = (sec(4)?.items ?? []) + (sec(5)?.items ?? [])
        s5.tools = Guides.concreteTools; s5.guides = Guides.concrete
        s5.when = "сразу после приёмки армирования; уход 7 суток, каркас — после 70 % прочности"
        out.append(s5)

        // 6. Отмостка, дренаж
        var s6 = BuildStage(title: "Отмостка и дренаж", icon: "drop.triangle", scene: .foundation)
        s6.goal = "Отвести воду от фундамента и защитить грунт от промерзания и пучения."
        s6.steps = sec(6)?.steps ?? []
        let dr = Drainage.make(p, r)
        s6.decisions = dr.requirements.map { Decision(title: $0.title, value: $0.value, why: $0.ok ? "выполняется" : "требуется", ref: $0.ref) }
        s6.items = sec(6)?.items ?? []
        s6.tools = Guides.drainTools; s6.guides = Guides.drain

        // 7. Обвязка
        var s7 = BuildStage(title: kind == .slab ? "Гидроизоляция и нижняя обвязка на плите" : "Обвязка по фундаменту и анкеровка", icon: "rectangle.split.3x1", scene: .floor)
        s7.goal = "Отсечь каркас от влаги бетона и надёжно закрепить его к фундаменту."
        let sillM = ms { $0.kind == .sill }
        let anchors = F.anchors.count
        let sillLen = F.sillLines.reduce(0) { $0 + ($1.1 - $1.0).len }
        let sillName = kind == .slab ? "нижняя обвязка стены \(F.studExt.label)" : (p.sillType == .timber ? "обвязочный брус \(F.sillSec.label)" : "лежень \(F.sillSec.label)")
        s7.steps = [
            "Проверить верх фундамента нивелиром: перепад не более ±10 мм на длину стены, местные неровности ≤ 5 мм на 2 м. Неровности выровнять ремонтным составом, не подкладками из щепы.",
            "Отсечная гидроизоляция: по верху \(kind == .slab ? "плиты под стенами" : "ленты") — праймер и 2 слоя наплавляемого материала (ТПП/ХПП, \(N.g30547.code)) полосой на 50–100 мм шире обвязки с выпуском по бокам. Дерево не должно касаться бетона.",
            "Поверх гидроизоляции — уплотнительная лента из вспененного полиэтилена 5–8 мм (герметизирует зазор под обвязкой от продувания).",
            "Пиломатериал обвязки — антисептированный (огнебиозащитный состав I–II группы, 2 слоя, торцы — 3 слоя) или лиственница. Все запилы и отверстия после обработки — повторно прокрасить.",
            "Разложить \(sillName) по осям так, чтобы наружная грань совпала с гранью фундамента (или со свесом ≤ 1/3 ширины). Углы — соединение «в полдерева» с саморезами 8×120 / нагелем Ø16, стыки по длине — «косой замок» над анкером.",
            "Анкеры: \(anchors) шт. — шпилька М12 (класс прочности 5.8) на химическом анкере в отверстии Ø14 глубиной 150 мм или Г-образная шпилька, заложенная при бетонировании. Не далее 300 мм от углов и стыков, шаг ≤ 2.0 м; ось анкера — посередине обвязки.",
            "Отверстия в обвязке Ø14–16 сверлить по разметке с фундамента; гайка с увеличенной шайбой (DIN 9021) затягивается после выдержки химического анкера; головку гайки утопить, если на обвязку ложится доска.",
        ]
        if kind == .slab {
            s7.steps.append("На плите отдельный обвязочный брус не нужен: нижняя обвязка стены \(F.studExt.label) крепится к плите теми же анкерами (с шагом ≤ 2 м), а пол выполняется по плите (утеплитель ЭППС под плитой, финишная стяжка/лаги).")
        }
        s7.decisions = [
            Decision(title: "Между бетоном и деревом", value: "2 слоя наплавляемой гидроизоляции + уплотнительная лента", why: "капиллярный подсос влаги из бетона — главная причина гниения нижнего венца", ref: "\(N.sp352.at("разд. «Фундаменты»")), \(N.sp64.at("разд. 11 «Защита от биоповреждения»"))"),
            Decision(title: "Обвязка", value: kind == .slab ? F.studExt.label : F.sillSec.label, why: "ширина не меньше ширины стойки каркаса (\(Dmm) мм), сорт 2, влажность ≤ 20 %", ref: "\(N.g8486.code), \(N.g24454.code)"),
            Decision(title: "Анкеровка", value: "М12, шаг ≤ 2.0 м, ≤ 300 мм от концов, \(anchors) шт.", why: "восприятие ветрового отрыва и сдвига; не менее 2 анкеров на каждый элемент", ref: N.sp352.at("разд. «Крепление каркаса к фундаменту»")),
            Decision(title: "Защита древесины", value: "огнебиозащита I–II группы", why: "элементы в контакте с фундаментом — класс условий эксплуатации с периодическим увлажнением", ref: "\(N.g20022.code), \(N.g53292.code)"),
        ]
        s7.tools = Guides.sillTools; s7.guides = Guides.sill(p, F)
        s7.fasteners = Fasteners.sill
        s7.when = "через 7–14 суток после бетонирования (≥ 70 % прочности)"
        s7.figures = [Figure(kind: .sillSteps, title: "Как стелить гидроизоляцию под брус: 4 шага", aspect: 0.42),
                      Figure(kind: .sillNode, title: "Узел опирания обвязки на фундамент (что между бетоном и брусом)", aspect: 0.8),
                      Figure(kind: .anchorPlan, title: "План обвязки и расстановка анкеров", aspect: 0.62)]
        var lumberArea = 0.0
        for m in F.members where m.stage == .floor || m.kind == .bottomPlate { lumberArea += m.length * 2 * (m.sec.tm + m.sec.wm) }
        s7.items = lumberItems(sillM) + [
            WorkItem(name: "Шпилька резьбовая М12×1000 оцинкованная (DIN 975), класс 5.8", qty: Double((anchors + 1) / 2), unit: "шт", note: "из 1 шпильки — 2 анкера по 0.45 м", digits: 0, price: Price.studM12),
            WorkItem(name: "Гайка М12 + шайба увеличенная М12 DIN 9021", qty: Double(anchors), unit: "компл", digits: 0, price: Price.nutWasherM12),
            WorkItem(name: "Химический анкер (полиэфирный, 300 мл) с насадками", qty: Double(Int((Double(anchors) / 12).rounded(.up))), unit: "шт", note: "≈ 12 отверстий Ø14×150 на картридж", digits: 0, price: Price.chemAnchor),
            WorkItem(name: "Лента уплотнительная ППЭ 8 мм под обвязку", qty: sillLen * 1.1, unit: "м", digits: 0, price: Price.sealTapeM),
            WorkItem(name: "Огнебиозащитный состав I–II группы (концентрат/готовый)", qty: max(5, lumberArea * 0.25 * 2), unit: "л",
                     note: "обвязка, балки пола, нижняя обвязка стен: 0.25 л/м² × 2 слоя; остальной сухой каркас — по желанию", digits: 0, price: Price.antisepticL),
        ]
        if kind == .slab {
            s7.items.insert(WorkItem(name: "Наплавляемая гидроизоляция ХПП/ТПП под обвязку (2 слоя)", qty: sillLen * (D + 0.1) * 2 * 1.15, unit: "м²", digits: 0, price: Price.roofingM2), at: 0)
        }
        out.append(s7)

        // 8. Перекрытие 1-го этажа
        if let g = F.floors.first, kind != .slab && p.groundFloor == .wood {
            var s8 = BuildStage(title: "Перекрытие 1-го этажа (балки пола)", icon: "square.grid.3x3", scene: .floor)
            s8.goal = "Собрать платформу пола, на которой будут собираться стены."
            let ck = g.check
            let joistM = ms { ($0.kind == .joist || $0.kind == .rim || $0.kind == .blocking) && $0.stage == .floor }
            let nJ = ms { $0.kind == .joist && $0.stage == .floor }.count
            let osbFloor = Int((r.loads.floorArea / 3.125 * 1.07).rounded(.up))
            s8.steps = [
                "По наружному контуру на обвязку ставится обвязочная доска \(ck.sec.label) на ребро (заподлицо с наружной гранью), крепится косыми гвоздями 4×100 через 400 мм.",
                "Балки \(ck.title) шаг \(Int(ck.step * 1000)) мм \(g.alongX ? "вдоль оси X" : "вдоль оси Y") (\(nJ) шт.), максимальный пролёт \(fmt(g.maxSpan)) м. Разметить шаг шаблоном \(Int(ck.step * 1000)) мм от наружного угла — балки встают над стойками стен, а торцы ОСП 2500 ложатся ровно на балки (4 пролёта).",
                "Балки опираются на обвязку и промежуточные ленты не менее чем на 100 мм; крепление — оцинкованные опоры/уголки по 2 на конец на анкерных гвоздях 4×40, торцы через обвязочную доску — 3 гвоздя 4×100.",
                "Над промежуточной опорой балки стыкуются внахлёст (≥ 300 мм, 4 гвоздя 4×100 или 2 болта М12) или в торец с накладками.",
                g.maxSpan > 2.5 ? "Распорки (блокинг) из той же доски между балками не реже чем через 2 м — против потери устойчивости и для передачи нагрузки соседним балкам." : "Пролёт короткий, распорки достаточно поставить по опорам.",
                "Снизу на черепные бруски 50×50 уложить черновой подшив (доска 25×100 / ОСП 9), сверху него — ветро-влагозащитную мембрану; утеплитель \(Int(b.woolFloor * 1000)) мм между балками без зазоров; сверху — пароизоляция с проклейкой швов.",
                "Настил: ОСП-3 22 мм шпунт (\(osbFloor) листов 2500×1250), длинной стороной поперёк балок, стыки вразбежку, зазор 3 мм между плитами и 10–12 мм у стен; клей ПУ + саморезы 4.5×50 шаг 150 мм по краю, 300 мм в поле.",
                "Подполье проветривается продухами в цоколе (площадь ≈ 1/400 площади пола, сетка от грызунов) или делается утеплённым закрытым с пароизоляцией по грунту.",
            ]
            s8.decisions = [
                Decision(title: "Балки пола", value: "\(ck.title) шаг \(Int(ck.step * 1000)) мм, пролёт \(fmt(g.maxSpan)) м",
                         why: "σ = \(fmt(ck.sigma, 1)) ≤ Rи = \(fmt(Timber.Ri, 1)) МПа; f = \(fmt(ck.f * 1000, 0)) ≤ fu = \(fmt(ck.fu * 1000, 0)) мм" + (ck.ok ? "" : " — НЕ ПРОХОДИТ, нужна промежуточная опора"),
                         ref: "\(N.sp64.at("разд. 7, изгибаемые элементы, табл. 3")), \(N.sp20.at("табл. Д.1"))"),
                Decision(title: "Нагрузка", value: "qн = \(fmt(g.qn, 2)), qр = \(fmt(g.qd, 2)) кПа", why: "пол 0.7 + перегородки 0.5 + полезная 1.5 кПа (γf 1.2/1.3)", ref: N.sp20.at("табл. 7.1, 8.3, п. 8.2.2")),
                Decision(title: "Утепление пола", value: "\(Int(b.woolFloor * 1000)) мм", why: "Rтр = \(fmt(b.rFloor, 2)) м²·°C/Вт при ГСОП \(Int(b.gsop))", ref: "\(N.sp50.at("табл. базовых значений Rтр")), \(N.sp131.at("табл. 3.1"))"),
                Decision(title: "Настил", value: "ОСП-3 22 мм шпунт", why: "шаг балок 600 мм, класс влагостойкости OSB-3", ref: N.g32567.code),
            ]
            if !g.beams.isEmpty {
                s8.steps.insert("⚠︎ Пролёт без промежуточной опоры превышает 4.8 м: под балки нужен прогон (ригель) — пакет 3×(50×\(ck.sec.w)) / клееный брус в уровне балок на кронштейнах, на кирпичных или бетонных столбиках через 1.5–2 м (линии прогонов — на плане), либо несущая перегородка с лентой (вкладка «План»).", at: 1)
                s8.decisions.append(Decision(title: "Прогоны", value: "\(g.beams.count) линии", why: "пролёт балок ограничен 4.8 м", ref: N.sp64.at("разд. 7, изгибаемые элементы")))
            }
            s8.tools = Guides.floorTools; s8.guides = Guides.floor
            s8.fasteners = Fasteners.floor
            s8.when = "сразу после обвязки — платформа нужна для сборки стен; утеплитель снизу — сейчас, пока доступ сверху"
            if p.floorSystemEff != .osbJoists || p.floorFinish == .tile {
                s8.steps.append("Пол в этом проекте — \(p.floorSystemEff.short): нагрузка от него (\(fmt(p.floorExtraDead, 2)) кПа сверх ОСП) уже учтена в подборе балок. Само основание пола делается позже, на этапе «Пол».")
            }
            s8.figures = [Figure(kind: .joistPlan(0), title: "План раскладки балок пола 1-го этажа", aspect: 0.62),
                          Figure(kind: .floorPie, title: "Пирог пола по балкам", aspect: 0.45)]
            s8.items = lumberItems(joistM) + [
                WorkItem(name: "Опора балки оцинкованная 50×\(ck.sec.w) (или уголок усиленный 90×90×65)", qty: Double(nJ * 2 * ck.count), unit: "шт", digits: 0, price: Price.joistHanger),
                WorkItem(name: "Гвозди анкерные (ершёные) оцинкованные 4×40", qty: max(1, Double(nJ * 2) * 10 * 0.004), unit: "кг", digits: 1, price: Price.anchorNailsKg),
                WorkItem(name: "Гвозди строительные 4×100 (ГОСТ 4028-63)", qty: max(1, Double(nJ) * 8 / 105), unit: "кг", digits: 1, price: Price.nailsKgG),
                WorkItem(name: "Брусок 50×50×3000 (черепной)", qty: Double(Int((Double(nJ) * g.maxSpan * 2 / 3 * 1.1).rounded(.up))), unit: "шт", digits: 0, price: 120),
                WorkItem(name: "ОСП-3 9 мм 2500×1250 (черновой подшив снизу)", qty: Double(Int((r.loads.floorArea / 3.125 * 1.08).rounded(.up))), unit: "лист", digits: 0, price: Price.osb9),
                WorkItem(name: "ОСП-3 22 мм шпунт 2500×1250 (настил)", qty: Double(osbFloor), unit: "лист", digits: 0, price: Price.osb22),
                WorkItem(name: "Мембрана ветро-влагозащитная супердиффузионная (рулон 75 м²)", qty: r.loads.floorArea * 1.15, unit: "м²", digits: 0, price: Price.membraneM2),
                WorkItem(name: "Минераловатные плиты 1200×600 ρ 30–40 кг/м³, λ ≤ 0.040 (\(Int(b.woolFloor * 1000)) мм)", qty: r.loads.floorArea * b.woolFloor * 0.92 * 1.05, unit: "м³",
                         note: "≈ \(Int((r.loads.floorArea * b.woolFloor * 0.92 * 1.05 / 0.288).rounded(.up))) уп. по 0.288 м³", digits: 2, price: Price.woolM3),
                WorkItem(name: "Пароизоляционная плёнка (рулон 70 м²)", qty: r.loads.floorArea * 1.15, unit: "м²", digits: 0, price: Price.vaporM2),
                WorkItem(name: "Саморезы по дереву 4.5×50 (ОСП к балкам)", qty: Double(osbFloor) * 45 * 0.006, unit: "кг", digits: 1, price: Price.screwsKg),
                WorkItem(name: "Клей монтажный полиуретановый для ОСП (баллон 750 мл)", qty: Double(Int((Double(osbFloor) / 4).rounded(.up))), unit: "шт", digits: 0, price: 650),
            ]
            out.append(s8)
        }

        // 9. Каркас наружных стен
        var s9 = BuildStage(title: "Каркас наружных стен", icon: "square.split.bottomrightquarter", scene: .walls)
        s9.goal = "Собрать и поднять стены, выставить их по вертикали, связать между собой."
        let extM = ms { $0.role == 0 && [.bottomPlate, .stud, .cornerStud, .king, .jack, .header, .sillPiece, .cripple, .topPlate, .capPlate, .brace, .nogging].contains($0.kind) }
        let temp = ms { $0.kind == .tempBrace && $0.stage == .walls }
        let wallsExt0 = F.walls.indices.filter { F.walls[$0].exterior && F.walls[$0].storey == 0 }
        let st = F.stud
        s9.steps = [
            "Стены собираются лёжа на платформе пола щитами длиной до 6 м: нижняя обвязка \(F.studExt.label), стойки \(F.studExt.label)\(p.modular ? "×3000 — целые доски без подрезки" : "") с шагом \(Int(p.studStep * 1000)) мм по осям, верхняя обвязка \(F.studExt.label) (второй ряд кладётся после подъёма).",
            "Разметка: нижнюю и верхнюю обвязку положить рядом, отметить оси стоек одновременно на обеих (от наружного угла, с шагом \(Int(p.studStep * 1000))) — стойки будут строго вертикальны, а стыки ОСП попадут на стойки.",
            "Стойка к обвязке — 2 гвоздя 4×100 (или ершёных 3.1×90) в торец через обвязку; двойные стойки и пакеты сшиваются гвоздями 4×100 через 300 мм в шахматном порядке.",
            "Угол — «тёплый»: у проходной стены дополнительная стойка на расстоянии толщины стены (под обшивку изнутри), утеплитель закладывается в угол до сборки. Примыкание перегородки — две стойки по краям перегородки.",
            "Проверить щит по диагоналям (разница ≤ 5 мм), \(p.sheathing.hasOSB ? "обшить ОСП-3 9 мм лёжа: гвозди ершёные 2.5×50 / саморезы 3.5×45 шаг 150 мм по краям листа и 300 мм на промежуточных стойках, отступ от кромки 10 мм, зазор между листами 3 мм; стык листов — только на стойке" : "врезать раскосы 25×100 под 45–60° от углов (запил в стойки на толщину доски, по 2 гвоздя 4×100 в каждую стойку)").",
            "Подъём стены — вдвоём-втроём; сразу выставить по отвесу/уровню 2 м и закрепить временными укосинами из доски 25×100 (\(temp.count) шт. на этаж, через 2.4 м) к платформе. Укосины снимаются только после обшивки и установки перекрытия.",
            "Нижнюю обвязку прибить к платформе гвоздями 4×100 / саморезами 5×90 через 400 мм в балки и обвязочную доску. Соседние стены в углу стянуть саморезами 5×90 через 300 мм.",
            "Второй ряд верхней обвязки уложить с перевязкой: в углах и на примыканиях он перекрывает стык нижнего ряда; стыки по длине разнести не менее чем на 600 мм; гвозди 4×100 через 400 мм в шахматном порядке.",
        ]
        s9.decisions = [
            Decision(title: "Стойки", value: "\(F.studExt.label)\(p.modular ? "×3000" : "") шаг \(Int(p.studStep * 1000)) мм", why: "\(abs(p.studStep - Module.step) < 1e-6 ? "ОСП 1250 = 2 шага, утеплитель 600 в просвет 575 без подрезки" : "шаг задан вручную"); N = \(fmt(st.N, 1)) кН, φ = \(fmt(st.phi, 2)), σ = \(fmt(st.sigma, 2)) ≤ Rс = \(fmt(Timber.Rc, 1)) МПа" + (st.ok ? "" : " — НЕ ПРОХОДИТ, уменьшить шаг"),
                     ref: "\(N.sp64.at("разд. 7, центрально-сжатые элементы")), \(N.sp352.at("разд. «Стены»"))"),
            Decision(title: "Пространственная жёсткость", value: p.sheathing == .osb ? "ОСП-3 9 мм снаружи по всем стенам (диафрагма)" : p.sheathing == .osbBraces ? "ОСП-3 9 мм + врезные раскосы 25×100 в углах" : "врезные раскосы 25×100 в углах и простенках ≥ 1.2 м",
                     why: "восприятие ветровой нагрузки; без диагональных связей каркас «складывается». Прибитая по контуру ОСП работает как раскос по всей площади стены; до обшивки — временные укосины" + (p.interiorFinish.isDiaphragm ? "" : ". Изнутри — \(p.interiorFinish.short): она жёсткости не даёт, поэтому во внутренних стенах — врезные раскосы"), ref: "\(N.sp352.at("разд. «Обеспечение пространственной жёсткости»")), \(N.g32567.code)"),
            Decision(title: "Верхняя обвязка", value: "2 ряда \(F.studExt.label) с перевязкой", why: "связывает стены в углах, распределяет нагрузку от балок между стойками", ref: N.sp352.at("разд. «Стены»")),
            Decision(title: "Пиломатериал", value: "сосна/ель 2 сорт, W ≤ 20 %", why: "класс прочности К24; сырая доска при усушке «ведёт» каркас и раскрывает швы", ref: "\(N.g8486.code), \(N.g33080.code)"),
            Decision(title: "Гвозди", value: "4×100, 2.5×50 ершёные", why: "размеры и сортамент гвоздей", ref: N.g4028.code),
        ]
        s9.figures = [Figure(kind: .cornerNode, title: "Угол каркаса («тёплый угол») — план", aspect: 0.62),
                      Figure(kind: .teeNode, title: "Примыкание перегородки — план", aspect: 0.5),
                      Figure(kind: .rigidity, title: "Откуда жёсткость стены: укосины, раскосы, ОСП", aspect: 0.42),
                      Figure(kind: .bracing, title: p.sheathing == .osb ? "Временные укосины при подъёме стены" : "Раскосы и временные укосины", aspect: 0.5),
                      Figure(kind: .fasteners, title: "Соединения элементов каркаса: чем и сколько", aspect: 0.62),
                      Figure(kind: .wallPlan, title: "Стена в плане: стойки, утеплитель, листы — размеры по модулю 625", aspect: 0.4)]
            + (wallsExt0.first.map { [Figure(kind: .sheetLayout($0, 0), title: "Раскладка ОСП на стене \(F.walls[$0].name) (снаружи): целые листы и полосы-половинки", aspect: 0.42)] } ?? [])
            + wallsExt0.prefix(12).map { Figure(kind: .wallElevation($0), title: "Развёртка стены \(F.walls[$0].name) (вид изнутри), длина \(fmt(F.walls[$0].length, 2)) м", aspect: 0.42) }
        s9.tools = Guides.wallTools; s9.guides = [Fasteners.rule] + Guides.walls(p, F)
        s9.fasteners = Fasteners.walls
        s9.when = "на готовой платформе пола / плите; все стены этажа — до перекрытия"
        s9.items = lumberItems(extM) + [
            WorkItem(name: "Доска обрезная 25×100×6000 (временные укосины)", qty: Double(Int((Double(temp.count) * 2.2 / 6 + 1).rounded(.up))), unit: "шт", note: "используется повторно на всех этажах", digits: 0, price: Price.lumberM3(Lumber(25, 100)) * 0.025 * 0.1 * 6),
            WorkItem(name: "Гвозди строительные 4×100 (ГОСТ 4028-63)", qty: Double(extM.count) * 6 / 105, unit: "кг", digits: 1, price: Price.nailsKgG),
            WorkItem(name: "Саморезы по дереву 5×90 (углы, обвязка к платформе)", qty: max(1, Double(extM.count) * 0.4 * 0.012), unit: "кг", digits: 1, price: Price.screwsKg),
        ]
        if p.sheathing.hasOSB {
            let sheets = Int((b.wallNet / 3.125 * 1.08).rounded(.up))
            s9.items += [
                WorkItem(name: "ОСП-3 9 мм 2500×1250 (обшивка стен снаружи)", qty: Double(sheets), unit: "лист", digits: 0, price: Price.osb9),
                WorkItem(name: "Гвозди ершёные оцинкованные 2.5×50 (ОСП к каркасу)", qty: Double(sheets) * 70 * 0.002, unit: "кг", digits: 1, price: Price.ringNailsKg),
            ]
        }
        out.append(s9)

        // 10. Проёмы
        var s10 = BuildStage(title: "Проёмы: окна, двери, перемычки", icon: "window.casement", scene: .walls)
        s10.goal = "Собрать обрамление проёмов под стандартные блоки и смонтировать окна по ГОСТ."
        let nonStd = b.openings.filter { !$0.standard }.count
        s10.steps = [
            "Черновой проём = размер блока + монтажный зазор: 20 мм по бокам и сверху, 30 мм снизу (под подставочный профиль). Для дверей — 30 мм по бокам и сверху.",
            "Обрамление: полные стойки (от обвязки до обвязки) + опорные укороченные стойки, на которые ложится перемычка из 2 досок на ребро (между ними — утеплитель), подоконный ригель, укороченные стойки над перемычкой и под ригелем — по шагу основных стоек.",
            "Перемычки подобраны расчётом по каждому проёму (таблица ниже). Перемычку не врезать в полные стойки — она должна опираться на опорные стойки по всей ширине.",
            "Окна ПВХ ставятся после устройства кровли, в плоскость утеплителя (ближе к наружной трети стены). Крепление рамы — анкерные пластины или конструкционные саморезы: от угла 150–180 мм, шаг ≤ 700 мм.",
            "Монтажный шов — 3 слоя: изнутри пароизоляционная лента, в середине монтажная пена (заполнение ≥ 90 % глубины), снаружи паропроницаемая лента ПСУЛ/диффузионная. Отлив — под раму с уклоном ≥ 10°, подоконник — с зазором 5–10 мм под утеплитель.",
            "Входную дверь ставят на опорные бруски по уровню; порог — на гидроизоляции, коробка крепится анкерами через петлевые выступы.",
            nonStd > 0 ? "⚠︎ \(plural(nonStd, "проём не совпадает", "проёма не совпадают", "проёмов не совпадают")) со стандартными блоками — в программе есть кнопка «Подогнать под стандартные», иначе окна будут изготавливаться под заказ." : "Все проёмы соответствуют стандартным блокам.",
        ]
        let wr = b.rWindow
        s10.decisions = [
            Decision(title: "Окна", value: wr <= 0.55 ? "ПВХ, 2-камерный стеклопакет 4-14-4-14-4" : "ПВХ, 2-камерный с энергосберегающим стеклом и аргоном",
                     why: "Rтр окон = \(fmt(wr, 2)) м²·°C/Вт при ГСОП \(Int(b.gsop))", ref: "\(N.sp50.at("табл. базовых значений Rтр")), \(N.g24866.code)"),
            Decision(title: "Размеры блоков", value: "стандартные ряды производителей", why: "блоки по ГОСТ 23166-2024 / 30674-99, двери по ГОСТ 475-2016 / 31173-2016", ref: "\(N.g23166.code), \(N.g475.code), \(N.g31173.code)"),
            Decision(title: "Монтажный шов", value: "3 слоя, крепёж ≤ 700 мм", why: "долговечность шва и отсутствие промерзания", ref: N.g30971.code),
            Decision(title: "Перемычки", value: "пакет 2–4 доски на ребро, прогиб ≤ l/200" + (F.headers.contains { !$0.check.ok } ? "; ⚠︎ для широких проёмов — LVL/клееный брус по расчёту" : ""), why: "нагрузка от перекрытий и кровли над проёмом", ref: "\(N.sp64.at("разд. 7, изгибаемые элементы")), \(N.sp20.at("табл. Д.1"))"),
            Decision(title: "Остекление в пол", value: "закалённое стекло / триплекс в нижнем поле", why: "безопасность при остеклении ниже 0.6–0.8 м от пола", ref: N.g23166.code),
        ]
        s10.tools = Guides.openingTools; s10.guides = Guides.opening
        s10.fasteners = Fasteners.openings
        s10.when = "обрамление — вместе со стенами; окна заказать сразу по таблице (изготовление 2–3 недели), ставить после кровли"
        s10.figures = [Figure(kind: .openingNode, title: "Обрамление оконного проёма (вид изнутри)", aspect: 0.75),
                       Figure(kind: .windowInstall, title: "Монтажный шов окна в каркасной стене (разрез)", aspect: 0.75)]
        var byBlock: [String: (StdBlock, Int)] = [:]
        for o in b.openings {
            let n = o.opening.kind.isDoor || o.wall.hasPrefix("П") ? 1 : floors
            byBlock[o.block.id, default: (o.block, 0)].1 += n
        }
        for (_, (blk, n)) in byBlock.sorted(by: { $0.key < $1.key }) {
            let price = blk.kind == .door ? (blk.id.hasPrefix("s") ? Price.doorExt : Price.doorInt) : Price.windowM2 * blk.w * blk.h
            s10.items.append(WorkItem(name: blk.name, qty: Double(n), unit: "шт", note: "проём в каркасе \(Int((blk.roW * 1000).rounded()))×\(Int((blk.roH * 1000).rounded())) мм", digits: 0, price: price))
        }
        let winPer = b.openings.filter { !$0.opening.kind.isDoor }.reduce(0.0) { $0 + 2 * ($1.block.w + $1.block.h) * Double($1.wall.hasPrefix("П") ? 1 : floors) }
        let allPer = b.openings.reduce(0.0) { $0 + 2 * ($1.block.w + $1.block.h) }
        s10.items += [
            WorkItem(name: "Пена монтажная профессиональная 750 мл", qty: Double(Int((allPer / 3.5).rounded(.up))), unit: "шт", digits: 0, price: Price.foamCan),
            WorkItem(name: "ПСУЛ / паропроницаемая лента наружного слоя шва", qty: winPer * 1.1, unit: "м", digits: 0, price: Price.psulM),
            WorkItem(name: "Лента пароизоляционная бутиловая внутреннего слоя шва", qty: winPer * 1.1, unit: "м", digits: 0, price: Price.tapeButylM),
        ]
        out.append(s10)

        // 11. Внутренние стены
        if !p.partitions.isEmpty {
            var s11 = BuildStage(title: "Внутренние несущие стены и перегородки", icon: "rectangle.split.2x1", scene: .walls)
            s11.goal = "Поставить несущие стены (опора перекрытия) и перегородки, связать их с наружными."
            let intM = ms { $0.role > 0 && $0.kind != .tempBrace }
            let bearing = p.partitions.filter(\.onFoundation).count
            s11.steps = [
                "Несущие внутренние стены (\(bearing) шт.) — из стоек \(F.studInt.label) шаг \(Int(p.studStep * 1000)) с двойной верхней обвязкой; стоят над лентой фундамента/балкой и собираются вместе с наружными, до перекрытия.",
                "Ненесущие перегородки — стойки \(F.studPart.label) шаг \(Int(p.studStep * 1000)) мм; можно ставить после устройства кровли. Верх перегородки к перекрытию — через упругую ленту, без жёсткого защемления (прогиб перекрытия не должен давить на перегородку).",
                "Узел примыкания: в наружной стене — две стойки по краям перегородки (или поперечные бруски через 600 мм по высоте), перегородка притягивается саморезами 5×90 шаг 400 мм.",
                "В перегородки санузлов и спален — звукоизоляционная минвата 50–100 мм; во влажных зонах — ГКЛВ и обмазочная гидроизоляция.",
                "Дверные проёмы: перемычка в несущих стенах — пара досок на ребро по расчёту, в перегородках — доска 50×100 плашмя.",
            ]
            s11.decisions = [
                Decision(title: "Несущие стены", value: "\(F.studInt.label) шаг \(Int(p.studStep * 1000))", why: "опора балок перекрытия, сокращает пролёт", ref: N.sp352.at("разд. «Стены»")),
                Decision(title: "Перегородки", value: "\(F.studPart.label) шаг \(Int(p.studStep * 1000))", why: "нагрузка учтена в перекрытии как 0.5 кПа", ref: N.sp20.at("п. 8.2.2")),
            ]
            s11.tools = Guides.wallTools; s11.guides = [Guides.walls(p, F)[0]]
            s11.fasteners = Fasteners.partitions + (p.interiorFinish.isDiaphragm ? [] : [Fastener(what: "Раскос врезной во внутренних стенах", item: "доска 25×100, гвозди 4×100 по 2 в каждую стойку", how: "молоток, пазы — циркулярка + стамеска")])
            s11.when = "несущие — вместе с наружными, до перекрытия; ненесущие — можно после кровли"
            if !p.interiorFinish.isDiaphragm {
                s11.steps.insert("⚠︎ Изнутри стены обшиваются \(p.interiorFinish.short) — декоративные доски на кляммерах не держат стену от перекоса (в отличие от ГКЛ/ОСП, прибитых по контуру). Поэтому в каждой внутренней стене длиной ≥ 2 м врезаются раскосы 25×100 под 45–60° от углов к верхней обвязке (показаны на развёртках). Без них стены «гуляют», трескаются углы и заклинивает двери.", at: 0)
                s11.decisions.append(Decision(title: "Жёсткость внутренних стен", value: "врезные раскосы 25×100", why: "обшивка вагонкой — не диафрагма; без листа по контуру нужна диагональная связь", ref: N.sp352.at("разд. «Обеспечение пространственной жёсткости»")))
            }
            s11.figures = [Figure(kind: .teeNode, title: "Примыкание перегородки к наружной стене", aspect: 0.5)]
                + F.walls.indices.filter { !F.walls[$0].exterior && F.walls[$0].storey == 0 }.prefix(6).map {
                    Figure(kind: .wallElevation($0), title: "Развёртка \(F.walls[$0].name), длина \(fmt(F.walls[$0].length, 2)) м", aspect: 0.42)
                }
            s11.items = lumberItems(intM) + [
                WorkItem(name: "Минераловатные плиты акустические 1200×600×50 мм", qty: b.partitionArea * 0.05 * 1.05, unit: "м³", digits: 2, price: Price.woolM3),
                WorkItem(name: "Гвозди строительные 4×100 (ГОСТ 4028-63)", qty: Double(intM.count) * 5 / 105, unit: "кг", digits: 1, price: Price.nailsKgG),
            ]
            out.append(s11)
        }

        // 12. Межэтажное перекрытие и верхние этажи
        if floors > 1 {
            var s12 = BuildStage(title: "Межэтажное перекрытие и стены верхних этажей", icon: "square.stack", scene: .upper)
            s12.goal = "Собрать перекрытие-платформу над 1-м этажом и повторить сборку стен."
            let upM = ms { $0.stage == .upper && $0.kind != .tempBrace }
            let j = F.floors.count > 1 ? F.floors[1] : F.floors.first
            s12.steps = [
                "Балки межэтажного перекрытия \(j.map { "\($0.check.title) шаг \(Int($0.check.step * 1000)) мм, пролёт \(fmt($0.maxSpan)) м" } ?? "") опираются на верхнюю обвязку стен (≥ 100 мм), по контуру — обвязочная доска; над несущими стенами — стык внахлёст.",
                "Проём под лестницу: двойные балки по контуру проёма, ригели на опорах балок, стык — на 4 болтах/гвоздях.",
                "Звукоизоляция: минвата 100–150 мм между балками, по балкам — звукоизоляционная лента; настил ОСП-3 22 мм на клей и саморезы.",
                "Стены 2-го этажа собираются так же, как 1-го, стойки — строго над стойками нижнего этажа.",
            ]
            if let j {
                s12.decisions = [Decision(title: "Балки перекрытия", value: "\(j.check.title) шаг \(Int(j.check.step * 1000)) мм",
                                          why: "σ = \(fmt(j.check.sigma, 1)) МПа, f = \(fmt(j.check.f * 1000, 0)) / \(fmt(j.check.fu * 1000, 0)) мм", ref: "\(N.sp64.at("разд. 7, изгибаемые элементы")), \(N.sp20.at("табл. Д.1, 8.3"))")]
                s12.figures = [Figure(kind: .joistPlan(F.floors.count > 1 ? 1 : 0), title: "План раскладки балок межэтажного перекрытия", aspect: 0.62)]
            }
            if let j, !j.beams.isEmpty {
                s12.steps.insert("⚠︎ Пролёт межэтажных балок > 4.8 м: прогон (ригель) из клееного бруса или пакета досок в уровне балок, опирающийся на стойки/несущие стены нижнего этажа (линии — на плане). Нагрузку от стоек нужно довести до фундамента.", at: 1)
            }
            s12.fasteners = Fasteners.upper
            s12.when = "после стен 1-го этажа и несущих перегородок"
            s12.items = lumberItems(upM) + [
                WorkItem(name: "ОСП-3 22 мм шпунт 2500×1250 (настил)", qty: Double(Int((r.loads.floorArea * Double(floors - 1) / 3.125 * 1.07).rounded(.up))), unit: "лист", digits: 0, price: Price.osb22),
                WorkItem(name: "Минераловатные плиты акустические 1200×600×50 мм", qty: r.loads.floorArea * Double(floors - 1) * 0.15 * 1.05, unit: "м³", digits: 2, price: Price.woolM3),
            ]
            if p.sheathing.hasOSB {
                s12.items.append(WorkItem(name: "ОСП-3 9 мм 2500×1250 (обшивка стен снаружи)", qty: 0, unit: "лист", note: "учтено в этапе «Каркас наружных стен»", digits: 0))
            }
            out.append(s12)
        }

        // 13. Стропильная система
        if p.roofType != .flat, let rf = F.rafter {
            var s13 = BuildStage(title: "Чердачное перекрытие и стропильная система", icon: "triangle", scene: .roof)
            s13.goal = "Поставить затяжки и стропила, связать их с каркасом, обеспечить жёсткость кровли."
            let roofM = ms { $0.stage == .roof }
            let nR = ms { $0.kind == .rafter }.count
            let nHip = ms { $0.kind == .hip }.count / 2
            let cosA = cos(p.roofAngleEff * .pi / 180)
            s13.steps = [
                F.separateTies
                    ? "Балки чердачного перекрытия \(F.attic.map { "\($0.check.title) шаг \(Int($0.check.step * 1000)), пролёт \(fmt($0.maxSpan)) м" } ?? "") идут по короткому пролёту (поперёк стропил), поэтому распор стропил воспринимают отдельные затяжки 50×150 на каждой паре ног, уложенные по балкам и прибитые к стропилам 6 гвоздями 4×100 / шпилькой М12."
                    : "Балки чердачного перекрытия \(F.attic.map { "\($0.check.title) шаг \(Int($0.check.step * 1000)), пролёт \(fmt($0.maxSpan)) м" } ?? "") — одновременно затяжки стропил: ставить в плоскости стропильных ног, концы — на верхнюю обвязку.",
                "Стропила \(rf.title) шаг \(Int(rf.step * 1000)) мм (\(nR) шт.), горизонтальная проекция пролёта \(fmt(F.rafterRun)) м, уклон \(Int(p.roofAngleEff))°. Изготовить шаблон стропила по первой паре, остальные — по шаблону.",
                "Опорный узел: запил под обвязку глубиной не более 1/3 высоты стропила; крепление — 2 усиленных уголка 90×90×65 на анкерных гвоздях 4×40 / саморезах 5×50 и гвоздями 4×100 к затяжке (4–6 шт.) или болтом М12. Каждую 2-ю ногу дополнительно — ветровой скобой/перфолентой к стойке каркаса.",
                p.roofType == .gable ? "Коньковый узел: стропила стыкуются торцами по коньковой доске, с двух сторон — накладки из доски 25×150 длиной 600 мм на гвоздях 4×100 (по 6 шт.). Ригели (схватки) 50×150 на 1/3 высоты от конька — на гвоздях/болтах М12." : "Коньковый прогон/доска — сечение больше стропила на 50 мм; стропила на нём крепятся уголками.",
                nHip > 0 ? "Диагональные (накосные/ендовые) ноги — сдвоенная доска \(rf.sec.label) (\(nHip) шт.), к ним крепятся укороченные стропила (нарожники) уголками." : "",
                F.rafterStrut ? "⚠︎ Пролёт велик для одиночного стропила: под середину ноги ставятся подкосы/стойки на несущую внутреннюю стену через лежень 50×150." : "Промежуточные опоры не требуются.",
                "Фронтоны: стойки фронтона \(F.studExt.label) по шагу стоек стены, от верхней обвязки до крайнего стропила; верх — наклонная обвязка.",
                p.roofType == .gable ? "Ветровые связи: диагональные доски 25×150 по нижней грани стропил на каждом скате (от карниза у одного фронтона к коньку у другого)." : "",
                "Свес \(fmt(p.overhang, 1)) м: стропила выпускаются за стену (или наращиваются «кобылками» 50×100 внахлёст 1 м); подшива свеса — софиты/вагонка по каркасу из бруска 50×50.",
            ].filter { !$0.isEmpty }
            if let a = F.attic, !a.beams.isEmpty {
                s13.steps.insert("⚠︎ Пролёт чердачных балок > 4.8 м: прогон в уровне балок на стойках с опорой на несущие стены 1-го этажа (линии — на плане раскладки).", at: 1)
            }
            s13.decisions = [
                Decision(title: "Стропила", value: "\(rf.title) шаг \(Int(rf.step * 1000)) мм",
                         why: "σ = \(fmt(rf.sigma, 1)) ≤ \(fmt(Timber.Ri, 1)) МПа; f = \(fmt(rf.f * 1000, 0)) ≤ \(fmt(rf.fu * 1000, 0)) мм" + (rf.ok ? "" : " — НЕ ПРОХОДИТ"),
                         ref: "\(N.sp64.at("разд. 7, изгибаемые элементы, табл. 3")), \(N.sp20.at("табл. Д.1"))"),
                Decision(title: "Снег", value: "район \(p.snowRegion.roman): S0 = \(fmt(p.snowRegion.s0, 1)) кПа, μ = \(fmt(r.loads.snowMu, 2))", why: "S = \(fmt(r.loads.snowS, 2)) кПа на горизонтальную проекцию, γf = 1.4", ref: N.sp20.at("п. 10.1, табл. 10.1, прил. Б")),
                Decision(title: "Нагрузка на стропило", value: "qр = \(fmt(F.roofQd, 2)) кПа (план)", why: "покрытие + обрешётка + утеплитель \(fmt(r.loads.roofDead, 2)) кПа, снег", ref: N.sp20.at("табл. 7.1")),
                Decision(title: "Длина ноги", value: "\(fmt(F.rafterRun / cosA + p.overhang / cosA, 2)) м", why: "проекция \(fmt(F.rafterRun, 2)) м + свес; доска 6 м", ref: N.g24454.code),
                Decision(title: "Крепление к каркасу", value: "уголки + ветровые скобы", why: "восприятие распора и ветрового отрыва", ref: "\(N.sp64.at("разд. 8 «Соединения»")), \(N.sp17.at("разд. 5"))"),
            ]
            s13.tools = Guides.roofTools; s13.guides = Guides.rafters(p, F)
            s13.fasteners = Fasteners.rafters
            s13.when = "после стен верхнего этажа и чердачных балок; укосины стен ещё стоят"
            s13.figures = [Figure(kind: .joistPlan(99), title: "План раскладки балок чердачного перекрытия", aspect: 0.62),
                           Figure(kind: .rafterPlan, title: "План стропильной системы", aspect: 0.62),
                           Figure(kind: .eaveNode, title: "Опорный (карнизный) узел стропила", aspect: 0.7)]
            if p.roofType == .gable || p.roofType == .hip { s13.figures.append(Figure(kind: .ridgeNode, title: "Коньковый узел", aspect: 0.6)) }
            s13.items = lumberItems(roofM) + [
                WorkItem(name: "Уголок крепёжный усиленный 90×90×65×2 оцинкованный", qty: Double(nR * 2 + (F.attic.map { $0.lines.count * 2 } ?? 0)), unit: "шт", digits: 0, price: Price.angle90),
                WorkItem(name: "Скоба ветровая / перфолента оцинкованная (крепление к стойке)", qty: Double((nR + 1) / 2), unit: "шт", digits: 0, price: Price.windStrap),
                WorkItem(name: "Гвозди анкерные (ершёные) оцинкованные 4×40", qty: max(1, Double(nR * 2) * 10 * 0.004), unit: "кг", digits: 1, price: Price.anchorNailsKg),
                WorkItem(name: "Гвозди строительные 4×100 (ГОСТ 4028-63)", qty: Double(roofM.count) * 6 / 105, unit: "кг", digits: 1, price: Price.nailsKgG),
                WorkItem(name: "Шпилька М12 с гайками и шайбами (узлы стропило–затяжка, ригели)", qty: Double(nR), unit: "компл", digits: 0, price: Price.boltM12),
            ]
            if p.roofType == .gable {
                s13.items.append(WorkItem(name: "Доска обрезная 25×150×6000 (накладки конька, ветровые связи)", qty: Double(Int((Double(nR) * 0.6 / 6 + Double(p.wings.count) * 4).rounded(.up))), unit: "шт", digits: 0, price: Price.lumberM3(Lumber(25, 150)) * 0.025 * 0.15 * 6))
            }
            out.append(s13)

            // 14. Кровля
            var s14 = BuildStage(title: "Кровельный пирог и покрытие", icon: "house", scene: .battens)
            s14.goal = "Сделать кровлю водонепроницаемой и вентилируемой, утеплить её."
            let bt = FrameGen.batten(p.covering, angle: p.roofAngleEff)
            let roofA = r.loads.roofArea
            let batM = ms { $0.stage == .battens }
            let eaveLen = RoofModel.of(p).edges.filter(\.eave).reduce(0) { $0 + ($1.b - $1.a).len }
            let waste: Double = [.metalTile, .compositeTile, .ceramicTile, .cementTile].contains(p.covering) ? 1.15 : 1.1
            s14.steps = [
                "По стропилам — супердиффузионная ветро-влагозащитная мембрана горизонтальными полосами снизу вверх, нахлёст 150 мм, провис 10–20 мм между стропилами; на коньке — с перехлёстом (или вентиляционный зазор под коньком).",
                "Контробрешётка — брусок \(F.counterSec.label) по стропилам поверх мембраны: создаёт вентиляционный зазор \(F.counterSec.w) мм от карниза к коньку.",
                "Обрешётка — \(bt.2). Крепление — оцинкованные гвозди 3.5×90 / саморезы, по 2 в каждое пересечение с контробрешёткой. Ровность — ±5 мм на 3 м (проверять шнуром).",
                "Покрытие: \(p.covering.title.lowercased()), минимальный уклон \(Int(p.covering.minSlope))° (принят \(Int(p.roofAngleEff))°). Монтаж по инструкции производителя, от карниза к коньку; доборные элементы: карнизная и ветровая планки, конёк с уплотнителем, ендовы, примыкания к трубам.",
                p.roofInsulated ? "Утепление мансарды: минвата \(Int(b.woolRoof * 1000)) мм (Rтр = \(fmt(b.rRoof, 2))) между стропилами\(b.woolRoof > (F.rafter?.sec.wm ?? 0.2) - 0.05 ? " и дополнительным слоем поперёк по брускам 50×50 изнутри" : ""), снизу — пароизоляция с проклейкой швов, обрешётка 25×50 под отделку." :
                    "Холодный чердак: утеплитель \(Int(b.woolRoof * 1000)) мм на чердачном перекрытии (Rтр = \(fmt(b.rRoof, 2))) по пароизоляции, сверху — ветрозащита; продухи в карнизах и на коньке.",
                "Снегозадержатели над входами и по карнизу при уклоне ≥ \(Int(p.covering.snowSlideSlope))°; водосток: желоб с уклоном 3–5 мм/м, трубы не реже чем через 24 м и сечением ≈ 1.5 см² на 1 м² кровли.",
            ]
            s14.decisions = [
                Decision(title: "Покрытие", value: p.covering.title, why: "уклон \(Int(p.roofAngleEff))° ≥ минимального \(Int(p.covering.minSlope))°", ref: N.sp17.at("разд. 4, уклоны кровель")),
                Decision(title: "Вентзазор", value: "\(F.counterSec.w) мм (контробрешётка)", why: "удаление влаги из подкровельного пространства", ref: N.sp17.at("разд. 6–7")),
                Decision(title: "Обрешётка", value: bt.2, why: "шаг по типу покрытия", ref: N.sp17.at("разд. 6")),
                Decision(title: "Утепление кровли", value: "\(Int(b.woolRoof * 1000)) мм минваты", why: "Rтр = \(fmt(b.rRoof, 2)) м²·°C/Вт (покрытия), ГСОП \(Int(b.gsop))", ref: N.sp50.at("табл. базовых значений Rтр")),
                Decision(title: "Водосток и снег", value: "наружный организованный, снегозадержатели", why: "защита отмостки и входов", ref: N.sp17.at("разд. 9")),
            ]
            s14.tools = Guides.roofTools; s14.guides = Guides.roofing(p)
            s14.fasteners = Fasteners.roofing(p.covering)
            s14.when = "сразу за стропилами — дом закрывается от дождя; потом окна"
            s14.figures = [Figure(kind: .roofPie, title: "Кровельный пирог (разрез по скату)", aspect: 0.6)]
            let woolRoofArea = p.roofInsulated ? roofA : r.loads.floorArea
            s14.items = lumberItems(batM) + [
                WorkItem(name: "Мембрана ветро-влагозащитная супердиффузионная (рулон 75 м²)", qty: roofA * 1.15, unit: "м²", digits: 0, price: Price.membraneM2),
                WorkItem(name: "Кровельное покрытие: \(p.covering.title.lowercased())", qty: roofA * waste, unit: "м²", note: "с запасом \(Int((waste - 1) * 100)) % на подрезку", digits: 0, price: Price.coveringM2(p.covering)),
                WorkItem(name: "Минераловатные плиты 1200×600 ρ 30–40 кг/м³ (\(Int(b.woolRoof * 1000)) мм)", qty: woolRoofArea * b.woolRoof * 0.9 * 1.05, unit: "м³",
                         note: "≈ \(Int((woolRoofArea * b.woolRoof * 0.9 * 1.05 / 0.288).rounded(.up))) уп. по 0.288 м³", digits: 2, price: Price.woolM3),
                WorkItem(name: "Пароизоляционная плёнка (рулон 70 м²)", qty: woolRoofArea * 1.15, unit: "м²", digits: 0, price: Price.vaporM2),
                WorkItem(name: "Лента соединительная бутилкаучуковая/акриловая для плёнок", qty: woolRoofArea * 0.8, unit: "м", digits: 0, price: Price.tapeButylM),
                WorkItem(name: "Карнизные и ветровые планки, конёк (доборные элементы кровли)", qty: eaveLen * 1.6, unit: "м.п.", digits: 0, price: 450),
                WorkItem(name: "Снегозадержатель трубчатый", qty: eaveLen * 0.5, unit: "м.п.", digits: 0, price: Price.snowGuardM),
                WorkItem(name: "Водосточная система (желоб, трубы, воронки, кронштейны)", qty: eaveLen, unit: "м.п.", digits: 0, price: Price.gutterM),
            ]
            if [.metalTile, .profiledSheet, .seam].contains(p.covering) {
                s14.items.append(WorkItem(name: "Саморез кровельный 4.8×35 с ЭПДМ-шайбой в цвет", qty: roofA * 8, unit: "шт", digits: 0, price: Price.roofScrews))
            }
            if p.covering == .softShingle {
                s14.items += [WorkItem(name: "ОСП-3 12 мм 2500×1250 (сплошной настил)", qty: Double(Int((roofA / 3.125 * 1.08).rounded(.up))), unit: "лист", digits: 0, price: Price.osb12),
                              WorkItem(name: "Подкладочный ковёр под мягкую черепицу", qty: roofA * 1.15, unit: "м²", digits: 0, price: Price.underlayM2)]
            }
            out.append(s14)
        }

        // 13–14 для плоской кровли
        if p.roofType == .flat, let a = F.attic {
            var sf = BuildStage(title: "Плоская кровля: балки, уклон, мембрана", icon: "rectangle.roundedtop", scene: .roof)
            sf.goal = "Собрать несущий настил плоской кровли с уклоном к воронкам и надёжной гидроизоляцией."
            let ck = a.check
            let roofM = ms { $0.stage == .roof }
            let roofA = r.loads.floorArea * 1.08
            sf.steps = [
                "Балки покрытия \(ck.title) шаг \(Int(ck.step * 1000)) мм, пролёт \(fmt(a.maxSpan)) м — на верхнюю обвязку, крепление уголками 90×90×65 и ветровыми скобами к стойкам (отрыв ветром для плоской кровли критичен).",
                a.beams.isEmpty ? "Промежуточные прогоны не требуются." : "⚠︎ Пролёт > 4.8 м — прогоны в уровне балок на стойках (линии — на плане).",
                "Уклон 2–3 % к водосборным воронкам: клиновидные бруски (кобылки) по балкам или переменная высота опор. Застой воды на кровле не допускается.",
                "Сплошной настил ОСП-3 18 мм с зазором 3 мм, стыки — на балках; парапет — каркас 50×150 с обшивкой ОСП, верх — оцинкованный парапетный фартук с уклоном внутрь.",
                "Утепление \(Int(b.woolRoof * 1000)) мм: между балками (с вентзазором ≥ 50 мм над утеплителем и продухами в парапете) или сверху по настилу — плиты минваты/PIR для плоских кровель; снизу — пароизоляция с проклейкой швов.",
                "Гидроизоляция: полимерная мембрана ПВХ/ТПО 1.2–1.5 мм механическим креплением или 2 слоя наплавляемого материала; заведение на парапет ≥ 300 мм, примыкания — по технологической карте производителя.",
                "Водосток: воронки с обогревом или парапетные воронки с наружными трубами; не менее 2 воронок на кровлю.",
            ]
            sf.decisions = [
                Decision(title: "Балки покрытия", value: "\(ck.title) шаг \(Int(ck.step * 1000)) мм", why: "σ = \(fmt(ck.sigma, 1)) МПа, f = \(fmt(ck.f * 1000, 0)) / \(fmt(ck.fu * 1000, 0)) мм; снег S = \(fmt(r.loads.snowS, 2)) кПа (μ = 1)" + (ck.ok ? "" : " — НЕ ПРОХОДИТ"),
                         ref: "\(N.sp64.at("разд. 7, изгибаемые элементы")), \(N.sp20.at("табл. 10.1, прил. Б"))"),
                Decision(title: "Уклон", value: "2–3 % к воронкам", why: "исключить застой воды", ref: N.sp17.at("разд. 4, уклоны кровель")),
                Decision(title: "Утепление", value: "\(Int(b.woolRoof * 1000)) мм", why: "Rтр = \(fmt(b.rRoof, 2)) м²·°C/Вт", ref: N.sp50.at("табл. базовых значений Rтр")),
            ]
            sf.figures = [Figure(kind: .joistPlan(99), title: "План раскладки балок плоской кровли", aspect: 0.62)]
            sf.items = lumberItems(roofM) + [
                WorkItem(name: "ОСП-3 18 мм 2500×1250 (сплошной настил)", qty: Double(Int((roofA / 3.125 * 1.08).rounded(.up))), unit: "лист", digits: 0, price: 1300),
                WorkItem(name: "Мембрана кровельная ПВХ 1.2 мм с крепежом", qty: roofA * 1.2, unit: "м²", digits: 0, price: 650),
                WorkItem(name: "Минераловатные плиты 1200×600 ρ 30–40 кг/м³ (\(Int(b.woolRoof * 1000)) мм)", qty: roofA * b.woolRoof * 1.05, unit: "м³", digits: 2, price: Price.woolM3),
                WorkItem(name: "Пароизоляционная плёнка (рулон 70 м²)", qty: roofA * 1.15, unit: "м²", digits: 0, price: Price.vaporM2),
                WorkItem(name: "Уголок крепёжный усиленный 90×90×65×2 оцинкованный", qty: Double(a.lines.count * 2), unit: "шт", digits: 0, price: Price.angle90),
                WorkItem(name: "Водосточная воронка кровельная с надставкой", qty: max(2, (roofA / 100).rounded(.up)), unit: "шт", digits: 0, price: 6500),
            ]
            out.append(sf)
        }

        // 14½. Черновая инженерия — до утеплителя
        out.append(StagesExtra.engineering(p, r, b.layout))

        // 15. Утепление стен и фасад
        var s15 = BuildStage(title: "Утепление стен, мембраны, фасад", icon: "square.3.layers.3d", scene: .finish)
        s15.goal = "Закрыть каркас от ветра и пара, утеплить стены, смонтировать фасад."
        let extra = b.woolWall > D + 0.001
        s15.steps = [
            "Утеплитель \(Int(b.woolWall * 1000)) мм (требуется по расчёту) — плиты 600 мм в распор между стойками, без щелей, со смещением швов слоёв\(extra ? "; каркас \(Dmm) мм недостаточен — добавить перекрёстный слой 50 мм по горизонтальным брускам 50×50 изнутри или снаружи" : "").",
            "Снаружи (по ОСП) — ветро-влагозащитная мембрана горизонтальными полосами снизу вверх, нахлёст 100–150 мм, проклейка у проёмов; мембрану заводят в откосы.",
            "Вентилируемый зазор 20–40 мм: вертикальные рейки/контррейки по стойкам, внизу и вверху зазор открыт и закрыт сеткой от насекомых.",
            facadeStep(p.facade),
            "Изнутри — пароизоляционная плёнка с нахлёстом 100 мм и проклейкой всех швов и примыканий; поверх — обрешётка 25×50 (инсталляционный зазор под проводку).",
        ]
        s15.decisions = [
            Decision(title: "Утеплитель стен", value: "\(Int(b.woolWall * 1000)) мм минваты λ ≤ 0.040", why: "Rтр = \(fmt(b.rWall, 2)) м²·°C/Вт при ГСОП = (20 − (\(fmt(p.tHeat, 1)))) × \(Int(p.zHeat)) = \(Int(b.gsop)); r = 0.85", ref: "\(N.sp50.at("табл. базовых значений Rтр")), \(N.sp131.at("табл. 3.1")), \(N.g9573.code)"),
            Decision(title: "Порядок слоёв", value: "паропроницаемость растёт наружу", why: "пароизоляция изнутри, ветрозащита снаружи — влага не конденсируется в утеплителе", ref: N.sp50.at("разд. «Защита от переувлажнения»")),
            Decision(title: "Фасад", value: p.facade.title, why: "навесной с вентзазором", ref: p.facade == .plaster ? N.g55943.code : p.facade == .facingBrick ? N.sp15.code : N.g8242.code),
        ]
        s15.tools = Guides.insulTools; s15.guides = Guides.insul(Kit.woolLayers(b.woolWall, depth: D))
        s15.fasteners = Fasteners.facade(p.facade)
        s15.when = "снаружи (мембрана, фасад) — сразу после окон; изнутри (утеплитель, пароизоляция) — после черновой инженерки"
        s15.figures = [Figure(kind: .wallSection, title: "Разрез наружной стены: брус, утеплитель, наружная и внутренняя отделка с размерами", aspect: 0.95),
                       Figure(kind: .wallPie, title: "Пирог наружной стены (слои)", aspect: 0.6)]
            + (wallsExt0First(F).map { [Figure(kind: .sheetLayout($0, 1), title: "Раскладка утеплителя на стене \(F.walls[$0].name): плиты 1200×600 без подрезки", aspect: 0.42)] } ?? [])
        let facadeArea = b.wallNet + (p.facade == .facingBrick ? 0 : 0)
        s15.items = [
            WorkItem(name: "Минераловатные плиты 1200×600 ρ 30–40 кг/м³ (\(Int(b.woolWall * 1000)) мм)", qty: b.wallNet * b.woolWall * 0.88 * 1.05, unit: "м³",
                     note: "≈ \(Int((b.wallNet * b.woolWall * 0.88 * 1.05 / 0.288).rounded(.up))) уп. по 0.288 м³", digits: 2, price: Price.woolM3),
            WorkItem(name: "Мембрана ветро-влагозащитная супердиффузионная (рулон 75 м²)", qty: b.wallNet * 1.15, unit: "м²", digits: 0, price: Price.membraneM2),
            WorkItem(name: "Пароизоляционная плёнка (рулон 70 м²)", qty: b.wallNet * 1.15, unit: "м²", digits: 0, price: Price.vaporM2),
            WorkItem(name: "Лента соединительная бутилкаучуковая/акриловая для плёнок", qty: b.wallNet * 0.6, unit: "м", digits: 0, price: Price.tapeButylM),
            WorkItem(name: "Брусок строганый 25×50×3000 (контррейка фасада и обрешётка изнутри)", qty: Double(Int((b.wallNet / 0.6 * 2 / 3 * 1.1).rounded(.up))), unit: "шт", digits: 0, price: 75),
            WorkItem(name: "Фасадная отделка: \(p.facade.title.lowercased())", qty: facadeArea * 1.1, unit: "м²", note: "с запасом 10 %, плюс доборные элементы", digits: 0, price: Price.facadeM2(p.facade)),
        ]
        if extra {
            s15.items.append(WorkItem(name: "Брусок 50×50×3000 (перекрёстное утепление)", qty: Double(Int((b.wallNet / 0.6 / 3 * 1.1).rounded(.up))), unit: "шт", digits: 0, price: 120))
        }
        out.append(s15)

        // 16. Основание пола и тёплый пол — после утепления стен, до обшивки
        let roomPerim = p.segments.reduce(0) { $0 + $1.length } + p.partitions.reduce(0) { $0 + $1.length } * 2
        var sFloor = FloorWorks.baseStage(p, r, area: r.loads.floorArea, perim: roomPerim)
        sFloor.when = p.floorSystemEff == .semiDry ? "после черновой инженерки, утепления и пароизоляции стен; до обшивки стен" : "после утепления стен, до обшивки"
        out.append(sFloor)

        // 17. Внутренняя обшивка
        out.append(StagesExtra.interior(p, r, b))

        // Наружные сети — до отмостки
        out.append(PlumbingWorks.externalStage(p, r, b.layout))

        // 18. Отмостка и дренаж — когда фасад и водосток готовы
        s6.when = "дренажную трубу удобно уложить сразу после фундамента, пока открыта пазуха; отмостку — после фасада и водостоков, чтобы не испачкать и не разбить"
        out.append(s6)

        // 19. Чистовой пол
        var sFin = FloorWorks.finishStage(p, r, area: r.loads.floorArea, perim: roomPerim)
        sFin.when = "последним: после покраски стен и установки дверных коробок"
        out.append(sFin)
        out.append(PlumbingWorks.fixturesStage(p, b.layout))
        return out
    }

    /// Что нужно решить до начала стройки
    static func decideEarly(_ p: Project) -> [String] {
        var d = [
            "Фундамент и тип пола: \(p.selectedFoundation.title.lowercased()), пол — \(p.floorSystemEff.short)\(p.floorHeating == .none ? "" : ", тёплый пол \(p.floorHeating == .water ? "водяной" : "электрический")"). От этого зависят отметки, гильзы вводов и подбор балок.",
            "Вводы коммуникаций: где заходят вода, канализация, кабель — гильзы закладываются в фундамент до бетонирования.",
            "Окна и двери: все проёмы — стандартные блоки, их можно заказать сразу после фундамента (2–3 недели изготовления) и поставить после кровли.",
            "Отопление: \(p.floorHeating == .water ? "котёл/тепловой насос и коллектор — место под котельную и шкаф коллектора" : p.floorHeating == .electric ? "мощность ввода под электрический тёплый пол (≈ 150 Вт/м²)" : "радиаторы — закладные под кронштейны в стенах до обшивки").",
            "Внутренняя обшивка: \(p.interiorFinish.short)\(p.interiorFinish.isDiaphragm ? "" : " — внутренним стенам нужны раскосы, они врезаются при сборке стен"). Под тяжёлые шкафы и бойлер — закладные до обшивки.",
        ]
        d.insert("Расстановка мебели и сантехники (раздел «Планировка, мебель, сантехника»): по ней выводятся точки воды и канализации и закладываются гильзы ввода и выпуска — менять её после фундамента и стяжки дорого.", at: 1)
        d.insert("Скважина и \(p.septic.short): место на участке — скважина ≥ \(Int(p.septic.wellDistance)) м от очистного сооружения; скважину лучше пробурить первой — вода нужна для стройки.", at: 2)
        if p.floorSystemEff == .inSlab { d.insert("Тёплый пол в плите: схема петель и коллектор — до армирования плиты, трубы укладываются вместе с арматурой.", at: 1) }
        return d
    }

    /// Пол по этапам: что делается и когда
    static func floorTimeline(_ p: Project, _ b: BuildPlan) -> [(String, String)] {
        func n(_ t: String) -> String { b.stages.first { $0.title.hasPrefix(t) }.map { "Этап \($0.number)" } ?? "—" }
        var t: [(String, String)] = []
        switch p.floorBase {
        case .slab:
            t.append((n("Армирование") + ": плита", p.floorSystemEff == .inSlab ? "трубы тёплого пола вяжутся к верхней сетке, опрессовка, бетон под давлением" : "плита — несущее основание пола; верх в горизонт ±10 мм"))
        case .joists:
            t.append((n("Перекрытие 1-го") + ": балки пола", "балки шаг 625, утеплитель \(Drawings.mm(b.woolFloor)) мм снизу на черепных брусках, ОСП-22 — это платформа для сборки стен"))
        case .ground:
            t.append(("Фундамент: пол по грунту", "песок с уплотнением внутри ленты — сразу после фундамента"))
        }
        t.append((n("Инженерные") + ": выводы", p.floorHeating == .water ? "подача от котла к коллектору, выводы воды и канализации в полу" : p.floorHeating == .electric ? "выводы воды и канализации, отдельная линия с УЗО под тёплый пол" : "выводы воды и канализации в полу до основания пола"))
        t.append((n("Пол:") + ": основание", "\(p.floorSystemEff.title) — до обшивки стен"))
        t.append((n("Чистовой пол") + ": покрытие", "\(p.floorFinish.title) — последним, после покраски стен"))
        return t
    }

    static func wallsExt0First(_ F: Framing) -> Int? { F.walls.indices.first { F.walls[$0].exterior && F.walls[$0].storey == 0 } }

    static func facadeStep(_ f: FacadeFinish) -> String {
        switch f {
        case .siding: return "Сайдинг: вертикальная обрешётка 25×50 шаг 400 мм, стартовая планка по уровню, J-профили у проёмов, внешние/внутренние углы; панели крепятся саморезами в центр перфорации с зазором 1–2 мм (температурное расширение)."
        case .imitationTimber: return "Имитация бруса / планкен (ГОСТ 8242-88): вертикальная контррейка 25×50×3000 по каждой стойке (шаг 625), доска 6000 → 5625 (стык на рейке), шипом вверх, крепление кляммерами или финишными гвоздями в шип; торцы и запилы — антисептик, лицевая сторона — лессирующий состав в 2 слоя."
        case .fiberCement: return "Фиброцементные панели: подсистема из оцинкованного профиля или бруска 50×50 по стойкам (шаг 625), панели — на кляммерах по инструкции производителя, стыки — на профиле."
        case .plaster: return "Штукатурный фасад: по ОСП — фасадная минвата ρ ≥ 130 кг/м³ или ЭППС на клей и дюбели, армирующий слой с сеткой, грунт и декоративная штукатурка (СФТК, ГОСТ Р 55943-2014)."
        case .facingBrick: return "Облицовочный кирпич 120 мм на отдельном выступе фундамента, вентзазор 30–40 мм, гибкие связи из нержавеющей стали/базальтопластика 4–5 шт/м² к стойкам каркаса, продухи внизу и вверху кладки (СП 15.13330.2020)."
        }
    }
}
