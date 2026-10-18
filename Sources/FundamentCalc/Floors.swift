import AppKit

/// На чём лежит пол 1-го этажа
enum FloorBase { case joists, slab, ground }

/// Основание пола (то, что между конструкцией и чистовым покрытием)
enum FloorSystem: String, CaseIterable, Identifiable {
    case osbJoists, dryScreed, semiDry, inSlab
    var id: String { rawValue }
    var title: String {
        switch self {
        case .osbJoists: return "ОСП-22 по балкам — сразу под чистовое покрытие"
        case .dryScreed: return "Сухая сборная стяжка: ГВЛ 2×10 мм по ОСП"
        case .semiDry: return "Полусухая стяжка 65 мм по ЭППС 50"
        case .inSlab: return "Трубы тёплого пола в плите фундамента (УШП)"
        }
    }
    var short: String {
        switch self {
        case .osbJoists: return "ОСП по балкам"
        case .dryScreed: return "сухая стяжка ГВЛ"
        case .semiDry: return "полусухая стяжка"
        case .inSlab: return "тёплый пол в плите"
        }
    }
    func allowed(_ b: FloorBase) -> Bool {
        switch self {
        case .osbJoists, .dryScreed: return b == .joists
        case .semiDry: return b != .joists
        case .inSlab: return b == .slab
        }
    }
}

enum FloorHeating: String, CaseIterable, Identifiable {
    case none, water, electric
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "Без тёплого пола (радиаторы)"
        case .water: return "Водяной тёплый пол (от котла/теплового насоса)"
        case .electric: return "Электрический тёплый пол"
        }
    }
}

enum FloorFinish: String, CaseIterable, Identifiable {
    case laminate, spc, engineered, tile
    var id: String { rawValue }
    var title: String {
        switch self {
        case .laminate: return "Ламинат 33 класса"
        case .spc: return "Кварцвинил SPC (замковый)"
        case .engineered: return "Инженерная доска"
        case .tile: return "Керамогранит"
        }
    }
    /// толщина покрытия с подложкой/клеем, м
    var t: Double {
        switch self {
        case .laminate: return 0.010
        case .spc: return 0.0065
        case .engineered: return 0.016
        case .tile: return 0.015
        }
    }
    var price: Double {
        switch self {
        case .laminate: return 1100
        case .spc: return 1600
        case .engineered: return 3500
        case .tile: return 1300
        }
    }
}

/// Внутренняя обшивка стен
enum InteriorFinish: String, CaseIterable, Identifiable {
    case gkl, boards, osb
    var id: String { rawValue }
    var title: String {
        switch self {
        case .gkl: return "ГКЛ 12.5 мм под покраску/обои"
        case .boards: return "Вагонка / имитация бруса 14×96×3000 (декоративные доски)"
        case .osb: return "ОСП-3 12 мм шлифованная (лофт, под навесное)"
        }
    }
    var short: String { self == .gkl ? "ГКЛ" : self == .boards ? "вагонка" : "ОСП 12" }
    var t: Double { self == .gkl ? 0.0125 : self == .boards ? 0.014 : 0.012 }
    /// Обшивка работает как диафрагма жёсткости (лист, прибитый по контуру)
    var isDiaphragm: Bool { self != .boards }
}

struct FloorLayer {
    let name: String
    let t: Double
    let h: Sk.Hatch
    var fill: NSColor? = nil
}

extension Project {
    var floorBase: FloorBase {
        if selectedFoundation == .slab { return .slab }
        return groundFloor == .wood ? .joists : .ground
    }
    /// Основание пола с учётом совместимости: водяной тёплый пол и плитка на балках — только по сухой стяжке
    var floorSystemEff: FloorSystem {
        let b = floorBase
        var s = floorSystem.allowed(b) ? floorSystem : (b == .joists ? .osbJoists : .semiDry)
        if b == .joists && s == .osbJoists && (floorHeating == .water || floorFinish == .tile) { s = .dryScreed }
        if s == .inSlab && floorHeating != .water { s = .semiDry }
        return s
    }
    /// Почему система изменена автоматически (пусто — выбрана как есть)
    var floorSystemNote: String {
        let b = floorBase, s = floorSystemEff
        if s == floorSystem { return "" }
        if !floorSystem.allowed(b) { return "«\(floorSystem.short)» не подходит для \(b == .joists ? "пола по балкам" : b == .slab ? "плиты" : "пола по грунту") — принято: \(s.short)." }
        if floorSystem == .inSlab { return "Трубы в плите — только для водяного тёплого пола; принято: \(s.short)." }
        return "На деревянных балках \(floorHeating == .water ? "водяной тёплый пол" : "плитка") требует жёсткого основания — принята сухая стяжка ГВЛ."
    }
    /// Дополнительная постоянная нагрузка от пола сверх ОСП, кПа (нормативная)
    var floorExtraDead: Double {
        var g = 0.0
        switch floorSystemEff {
        case .semiDry: g += 1.35
        case .dryScreed: g += 0.25 + (floorHeating == .water ? 0.12 : 0)
        default: break
        }
        g += floorFinish == .tile ? 0.3 : 0.1
        return g
    }

    /// Слои пола снизу вверх от несущего основания (балки/плита)
    var floorLayers: [FloorLayer] {
        var l: [FloorLayer] = []
        let blue = NSColor.systemBlue, red = NSColor(srgbRed: 0.85, green: 0.2, blue: 0.15, alpha: 1)
        switch floorSystemEff {
        case .osbJoists:
            l.append(FloorLayer(name: "ОСП-3 22 мм шпунт на клей + саморезы", t: 0.022, h: .board))
            if floorHeating == .electric { l.append(FloorLayer(name: "Теплоотражающая подложка + инфракрасная плёнка", t: 0.003, h: .none, fill: red)) }
        case .dryScreed:
            l.append(FloorLayer(name: "ОСП-3 22 мм шпунт", t: 0.022, h: .board))
            if floorHeating == .water {
                l.append(FloorLayer(name: "Панели с пазами 30 мм + Al пластины, трубы PE-Xa 16", t: 0.03, h: .insulation))
            }
            l.append(FloorLayer(name: "ГВЛ элементы пола 2×10 мм (клей + шурупы 3.9×19)", t: 0.02, h: .none, fill: NSColor(white: 0.88, alpha: 1)))
            if floorHeating == .electric { l.append(FloorLayer(name: "Нагревательный мат в слое плиточного клея", t: 0.005, h: .none, fill: red)) }
        case .semiDry:
            if floorBase == .ground {
                l.append(FloorLayer(name: "Бетонная подготовка B7.5 60 мм по песку", t: 0.06, h: .concrete))
                l.append(FloorLayer(name: "Гидроизоляция (наплавляемая 1 слой)", t: 0.004, h: .none, fill: .black))
            }
            l.append(FloorLayer(name: "ЭППС \(floorBase == .ground ? 100 : 50) мм, 1185×585, вразбежку", t: floorBase == .ground ? 0.1 : 0.05, h: .insulation, fill: NSColor(srgbRed: 0.75, green: 0.88, blue: 1, alpha: 1)))
            l.append(FloorLayer(name: "Плёнка 200 мкм внахлёст, на стены до верха стяжки", t: 0.002, h: .none, fill: blue))
            l.append(FloorLayer(name: floorHeating == .none ? "Полусухая стяжка ЦПС М150 + фибра" : "Полусухая стяжка ЦПС М150 + фибра, \(floorHeating == .water ? "трубы PE-Xa 16 шаг 150/200" : "кабель тёплого пола"), над трубой ≥ 45", t: 0.065, h: .sand, fill: NSColor(white: 0.82, alpha: 1)))
        case .inSlab:
            l.append(FloorLayer(name: "Выравнивающий наливной пол 3–10 мм по шлифованной плите", t: 0.005, h: .none, fill: NSColor(white: 0.86, alpha: 1)))
        }
        switch floorFinish {
        case .tile: l.append(FloorLayer(name: "Клей С2\(floorHeating == .none ? "" : "S1") 5 мм + керамогранит 600×600×10", t: 0.015, h: .none, fill: NSColor(srgbRed: 0.85, green: 0.82, blue: 0.76, alpha: 1)))
        case .laminate: l.append(FloorLayer(name: "Подложка 2 мм + ламинат 33 кл. 8 мм", t: 0.010, h: .board))
        case .spc: l.append(FloorLayer(name: "Подложка 1.5 мм + SPC 5 мм", t: 0.0065, h: .none, fill: NSColor(srgbRed: 0.72, green: 0.62, blue: 0.5, alpha: 1)))
        case .engineered: l.append(FloorLayer(name: "Инженерная доска 14 мм на клей / подложке", t: 0.016, h: .board))
        }
        return l
    }
    /// Толщина пола над несущим основанием, м
    var floorBuildUp: Double { floorLayers.reduce(0) { $0 + $1.t } }
    /// Насколько основание пола поднимается до монтажа ГКЛ (стяжка делается раньше обшивки стен)
    var gklBase: Double { floorSystemEff == .semiDry ? floorLayers.filter { !$0.name.contains("подготовка") && !$0.name.contains("Гидроизоляция") }.dropLast().reduce(0) { $0 + $1.t } : 0 }
}

/// Пол и тёплый пол: этапы, материалы, инструкции
enum FloorWorks {
    static func heatedArea(_ p: Project, _ r: CalcResults) -> Double { p.floorHeating == .none ? 0 : r.loads.floorArea * 0.8 }
    static func loops(_ area: Double) -> Int { max(1, Int((area / 15).rounded(.up))) }

    /// Этап «Основание пола и тёплый пол»
    static func baseStage(_ p: Project, _ r: CalcResults, area: Double, perim: Double) -> BuildStage {
        let s = p.floorSystemEff
        var st = BuildStage(title: s == .osbJoists && p.floorHeating == .none ? "Пол: подготовка основания" : "Пол: \(s.short)\(p.floorHeating == .none ? "" : " и тёплый пол")", icon: "square.grid.4x3.fill", scene: .screed)
        st.goal = "Сделать ровное основание под чистовой пол\(p.floorHeating == .none ? "" : " с тёплым полом"). Этап — после кровли, окон, черновой инженерки и утепления стен, но до обшивки стен."
        let ha = heatedArea(p, r)
        let n = loops(ha)
        let pipe = ha / 0.17 * 1.1 + Double(n) * 8
        var steps: [String] = []
        switch s {
        case .osbJoists:
            steps = ["Проверить ОСП-22 правилом 2 м: просвет ≤ 2 мм. Выступающие кромки прошлифовать, саморезы утопить, щели в стыках — не заделывать (температурный зазор 3 мм).",
                     "Пропылесосить основание. Чистовой пол кладётся в самом конце (последний этап), после покраски стен."]
            if p.floorHeating == .electric { steps.append("Электрический тёплый пол по дереву — только инфракрасная плёнка под ламинат/SPC по теплоотражающей подложке, с терморегулятором и ограничением +27 °C на поверхности. Кабель в стяжку по дереву не делают.") }
        case .dryScreed:
            steps = ["Основание: ОСП-22 ровное (≤ 2 мм на 2 м). По периметру — кромочная лента 10 мм на высоту пола.",
                     p.floorHeating == .water ? "Водяной тёплый пол по дереву: панели с пазами 30 мм (ДСП/ЭППС) на клей, в пазы — алюминиевые теплораспределительные пластины, в них — трубы PE-Xa 16 мм. Петли: \(n) шт., всего ≈ \(Int(pipe)) м трубы, длина петли ≤ 80 м." : "",
                     "ГВЛ элементы пола 1200×600×20 (2 слоя по 10 со смещённым фальцем). Укладка от дальней стены к двери; на фальц — клей ПВА/«для элементов пола» змейкой, шурупы 3.9×19 через 300 мм в фальц.",
                     "Швы — со смещением ≥ 250 мм, крестовые стыки не допускаются. Через 24 ч — шпаклёвка шурупов и швов.",
                     p.floorHeating == .electric ? "Электрический тёплый пол — нагревательный мат в слое плиточного клея поверх ГВЛ (только под плитку), датчик пола в гофре между витками." : "",
            ].filter { !$0.isEmpty }
        case .semiDry:
            steps = ["До стяжки: окна стоят, отопление/ввод воды и канализационные выпуски выведены, утеплитель и пароизоляция стен смонтированы, на стенах лазером отбит «нулевой» уровень +1000 от будущего чистого пола.",
                     p.floorBase == .ground ? "Пол по грунту: песок 200–300 мм с послойным уплотнением, бетонная подготовка 60 мм, гидроизоляция 1 слой наплавляемая с заведением на ленту." : "Плиту очистить от наплывов, перепады > 10 мм на 2 м — сбить.",
                     "По периметру стен, колонн и труб — демпферная лента 8–10 мм на высоту стяжки + 20 мм.",
                     "ЭППС \(p.floorBase == .ground ? "100" : "50") мм плотно, вразбежку, без щелей; сверху плёнка 200 мкм внахлёст 150 мм с заведением на стены.",
                     p.floorHeating == .water ? "Трубы PE-Xa 16 мм «улиткой»: шаг 150 мм у наружных стен (краевая зона 1 м) и 200 мм в центре. \(n) петель (≤ 15 м² и ≤ 80–100 м трубы каждая), всего ≈ \(Int(pipe)) м. Крепление — скобы-гарпуны в ЭППС через 500 мм. Каждую петлю подписать на коллекторе." : "",
                     p.floorHeating == .water ? "Опрессовка: давление 6 бар на 24 ч, падение ≤ 0.2 бар. Стяжку делают, не сбрасывая давление (3 бар) — так видно, если трубу повредили." : "",
                     p.floorHeating == .electric ? "Нагревательный кабель 18–20 Вт/м по монтажной ленте с шагом 80–120 мм (150 Вт/м²), холодный конец — в гофре до терморегулятора, датчик пола — в гофре с заглушкой. Измерить сопротивление до и после стяжки." : "",
                     "Маяки или реперы по лазеру; стяжка \(Int(0.065 * 1000)) мм, полусухая ЦПС М150 (песок:цемент ≈ 3:1) с фиброволокном 0.6–0.9 кг/м³, влажность — «держит форму в кулаке, не течёт».",
                     "Укладка картами, уплотнение и правило по маякам, через 30–60 мин — затирка затирочной машиной («вертолётом») до гладкой поверхности. Маяки удалить, борозды затереть.",
                     "Деформационные швы: нарезать на 1/3 толщины в дверных проёмах, на площадях > 30 м² и длинах > 8 м; трубы через шов — в гильзе 300 мм.",
                     "Уход: укрыть плёнкой на 3–7 суток, без сквозняков и солнца. Ходить — через 12–24 ч, обшивать стены — через 3 суток, нагружать и класть покрытие — через 28 суток (влажность ≤ 2 %, ламинат — ≤ 1.8 %).",
                     p.floorHeating == .none ? "" : "Первый запуск тёплого пола — не раньше 28 суток: начать с +20 °C в подаче и поднимать на 5 °C в сутки до рабочей температуры (≤ 45 °C в подаче, ≤ 27–29 °C на поверхности).",
            ].filter { !$0.isEmpty }
        case .inSlab:
            steps = ["Трубы уложены в плиту на этапе армирования (см. этап «Армирование»): этот этап — проверка и подготовка поверхности.",
                     "Проверить давление в петлях (оставлялось 3 бар после опрессовки) и подписи петель на коллекторе.",
                     "Плиту прошлифовать или выровнять наливным полом 3–10 мм по грунтовке. Плитка кладётся прямо на плиту, ламинат/SPC — по подложке.",
                     "Первый запуск — плавно, на 5 °C в сутки, не раньше 28 суток после бетонирования."]
        }
        st.steps = steps
        st.decisions = [
            Decision(title: "Основание пола", value: s.title, why: p.floorSystemNote.isEmpty ? reason(s, p) : p.floorSystemNote, ref: s == .semiDry || s == .inSlab ? N.sp29.at("разд. 8 «Стяжки»") : N.sp29.at("разд. 8, сборные стяжки")),
            Decision(title: "Толщина пола", value: "\(Drawings.mm(p.floorBuildUp)) мм от \(p.floorBase == .joists ? "верха балок" : "верха плиты")", why: "суммарная толщина слоёв с покрытием — учтена в чистой высоте помещения", ref: N.sp29.code),
        ]
        if p.floorHeating != .none {
            st.decisions.append(Decision(title: "Тёплый пол", value: p.floorHeating == .water ? "\(n) петель, ≈ \(Int(pipe)) м трубы PE-Xa 16" : "≈ \(fmt(ha, 0)) м² обогрева, 150 Вт/м²", why: "обогревается ≈ 80 % площади (без мест под мебелью и кухней); температура поверхности ≤ 26 °C в жилых, ≤ 31 °C в ванных", ref: N.sp60.at("разд. 6, напольное отопление")))
        }
        if p.floorBase == .joists && s == .dryScreed {
            st.decisions.append(Decision(title: "Почему не мокрая стяжка по балкам", value: "сухая ГВЛ", why: "полусухая стяжка 65 мм добавляет ≈ 1.35 кПа и вносит влагу в деревянное перекрытие; сухая — 0.25 кПа, без воды, ходить сразу", ref: N.sp29.at("разд. 8")))
        }
        st.figures = [Figure(kind: .floorSection, title: "Пирог пола у наружной стены: слои и размеры", aspect: 0.55)]
        if p.floorHeating == .water { st.figures.append(Figure(kind: .heatingLoop, title: "Раскладка петли водяного тёплого пола «улиткой» (комната ≈ 15 м²)", aspect: 0.62)) }
        st.items = baseItems(p, r, area: area, perim: perim)
        st.tools = tools(s, p.floorHeating)
        st.guides = guides(s, p.floorHeating)
        st.fasteners = fasteners(s, p.floorHeating)
        return st
    }

    static func reason(_ s: FloorSystem, _ p: Project) -> String {
        switch s {
        case .osbJoists: return "самый быстрый и лёгкий вариант для пола по балкам: ламинат/SPC/доска кладутся прямо на ОСП-22"
        case .dryScreed: return "жёсткое ровное основание по дереву без воды: под плитку и тёплый пол"
        case .semiDry: return p.floorBase == .slab ? "стандарт для дома на плите: ЭППС + стяжка 65 мм, в ней удобно делать тёплый пол" : "пол по грунту: подготовка, утепление, стяжка"
        case .inSlab: return "трубы в самой плите (УШП): плита — аккумулятор тепла, нет отдельной стяжки, ниже пирог пола"
        }
    }

    static func baseItems(_ p: Project, _ r: CalcResults, area: Double, perim: Double) -> [WorkItem] {
        var it: [WorkItem] = []
        let ha = heatedArea(p, r)
        let n = loops(ha)
        switch p.floorSystemEff {
        case .osbJoists: break
        case .dryScreed:
            it += [WorkItem(name: "ГВЛ элемент пола 1200×600×20 мм (2×10, фальц)", qty: Double(Int((area / 0.72 * 1.05).rounded(.up))), unit: "шт", note: "1 элемент = 0.72 м²", digits: 0, price: 520),
                   WorkItem(name: "Шурупы для элементов пола 3.9×19 (уп. 1000)", qty: max(1, (area * 18 / 1000).rounded(.up)), unit: "уп", digits: 0, price: 450),
                   WorkItem(name: "Клей для элементов пола / ПВА строительный 10 кг", qty: max(1, (area / 40).rounded(.up)), unit: "шт", digits: 0, price: 900),
                   WorkItem(name: "Кромочная лента 10 мм", qty: perim * 1.1, unit: "м", digits: 0, price: Price.damperTapeM)]
            if p.floorHeating == .water {
                it.append(WorkItem(name: "Панели для тёплого пола по дереву (паз под трубу 16) + Al пластины", qty: ha, unit: "м²", note: "обогреваемая площадь", digits: 0, price: 1800))
            }
        case .semiDry:
            let eps = p.floorBase == .ground ? 0.1 : 0.05
            let bags = area * 0.065 * 1900 / 40 * 1.05
            if p.floorBase == .ground {
                it += [WorkItem(name: "Бетон B7.5 (подготовка 60 мм)", qty: area * 0.06 * 1.05, unit: "м³", digits: 1, price: Price.concretePrep),
                       WorkItem(name: "Наплавляемая гидроизоляция ТПП (1 слой)", qty: area * 1.15, unit: "м²", digits: 0, price: Price.roofingM2)]
            }
            it += [WorkItem(name: "ЭППС \(Int(eps * 1000)) мм 1185×585 (плотность ≥ 30)", qty: area * 1.05, unit: "м²", note: "≈ \(Int((area * 1.05 / 0.693).rounded(.up))) плит", digits: 0, price: eps > 0.06 ? Price.eps100M2 : Price.eps50M2),
                   WorkItem(name: "Плёнка полиэтиленовая 200 мкм", qty: area * 1.25, unit: "м²", digits: 0, price: Price.filmM2),
                   WorkItem(name: "Демпферная лента 8–10 мм", qty: perim * 1.1, unit: "м", digits: 0, price: Price.damperTapeM),
                   WorkItem(name: "ЦПС М150 (пескобетон) 40 кг для полусухой стяжки 65 мм", qty: bags.rounded(.up), unit: "мешок", note: "или песок + цемент М500 3:1 при механизированной стяжке", digits: 0, price: Price.dryMixBag),
                   WorkItem(name: "Фиброволокно полипропиленовое 0.9 кг", qty: max(1, (area * 0.065 * 0.8 / 0.9).rounded(.up)), unit: "уп", digits: 0, price: 350),
                   WorkItem(name: "Маячный профиль 10 мм 3 м", qty: (area / 3).rounded(.up), unit: "шт", digits: 0, price: 70)]
        case .inSlab: break
        }
        switch p.floorHeating {
        case .water:
            let pipe = ha / 0.17 * 1.1 + Double(n) * 8
            if p.floorSystemEff != .inSlab {
                it.append(WorkItem(name: "Труба PE-Xa 16×2.0 с антидиффузионным слоем", qty: pipe, unit: "м", note: "\(n) петель", digits: 0, price: 75))
                if p.floorSystemEff == .semiDry { it.append(WorkItem(name: "Скоба-гарпун для ЭППС (уп. 100)", qty: max(1, (pipe / 0.5 / 100).rounded(.up)), unit: "уп", digits: 0, price: 450)) }
            }
            it += [WorkItem(name: "Коллектор тёплого пола на \(n) выход(ов) с расходомерами + насосно-смесительный узел", qty: 1, unit: "компл", digits: 0, price: 16000 + Double(n) * 2500),
                   WorkItem(name: "Шкаф коллекторный встраиваемый", qty: 1, unit: "шт", digits: 0, price: 4500),
                   WorkItem(name: "Фитинги для PE-Xa 16 (евроконус) на коллектор", qty: Double(n * 2), unit: "шт", digits: 0, price: 350)]
        case .electric:
            let zones = max(1, Int((ha / 15).rounded(.up)))
            if p.floorSystemEff == .osbJoists {
                it.append(WorkItem(name: "Инфракрасная плёнка тёплого пола 150 Вт/м² с комплектом подключения", qty: ha, unit: "м²", digits: 0, price: 900))
            } else {
                it.append(WorkItem(name: "Нагревательный кабель/мат 150 Вт/м²", qty: ha, unit: "м²", digits: 0, price: 2300))
            }
            it.append(WorkItem(name: "Терморегулятор с датчиком пола", qty: Double(zones), unit: "шт", note: "по зоне на комнату ≈ 15 м²", digits: 0, price: 3500))
        case .none: break
        }
        return it
    }

    /// Финальный этап — чистовой пол
    static func finishStage(_ p: Project, _ r: CalcResults, area: Double, perim: Double) -> BuildStage {
        let f = p.floorFinish
        var st = BuildStage(title: "Чистовой пол: " + f.title.prefix(1).lowercased() + f.title.dropFirst(), icon: "square.grid.3x3.topleft.filled", scene: .finish)
        st.goal = "Последний «грязный» этап закончен — кладём покрытие пола и плинтус."
        let total = area * Double(max(p.floors, 1))
        var steps = ["Когда: после шпаклёвки и покраски стен и потолков, после установки межкомнатных коробок. Влажность основания: стяжка ≤ 2 %, ГВЛ/ОСП ≤ 12 %.",
                     "Акклиматизация покрытия — 48 ч в помещении при +18…+25 °C в закрытых пачках.",
                     p.floorHeating == .none ? "" : "Тёплый пол выключить за 2–3 суток до укладки; включать после — плавно, с +18 °C на 2 °C в сутки. Покрытие — с маркировкой «для тёплого пола», ≤ 27 °C на поверхности."]
        switch f {
        case .laminate, .spc:
            steps += ["Подложка \(f == .spc ? "1.5 мм (или встроенная)" : "2 мм") встык, швы на скотч; поверх стяжки на грунте/плите — под подложку плёнка 200 мкм внахлёст 200 мм.",
                      "Первый ряд — гребнем к стене, клинья 8–10 мм по периметру. Обрезок последней панели (≥ 300 мм) начинает следующий ряд — отходов почти нет.",
                      "Ряды со смещением торцов ≥ 300 мм; панели защёлкиваются под углом, торцы — добойником через брусок. На проёмах шириной > 8 м и в дверях — порог (компенсационный шов).",
                      "Плинтус крепится к стене (клипсы/саморезы 4×40 через 400–500 мм), не к полу — пол плавающий."]
        case .engineered:
            steps += ["По стяжке/ГВЛ — грунт и 2К-клей (полиуретан) зубчатым шпателем, доска прижимается и подбивается; по ОСП — плавающим способом на подложке или на клей.",
                      "Зазор 10 мм у стен, ряды со смещением ≥ 500 мм. Ходить — через 24 ч, плинтус — к стене."]
        case .tile:
            steps += ["Раскладка: от входа или центра комнаты, целая плитка — на видном месте, подрезка — у стен под мебелью. Разметка лазером.",
                      "Клей С2\(p.floorHeating == .none ? "" : "S1 (эластичный)") зубчатым шпателем 10 мм на основание и тонким слоем на плитку (600×600 — обязательно на обе поверхности), система выравнивания СВП.",
                      "Шов 2–3 мм, затирка через 24 ч. Деформационные швы стяжки повторить в плитке (эластичный герметик).",
                      p.floorSystemEff == .dryScreed ? "На ГВЛ — грунт глубокого проникновения, в санузлах — обмазочная гидроизоляция с лентой в углах." : "В санузлах — обмазочная гидроизоляция с заведением на стены 200 мм."]
        }
        st.steps = steps.filter { !$0.isEmpty }
        st.figures = [Figure(kind: .floorSection, title: "Пирог пола с покрытием и плинтусом, размеры в мм", aspect: 0.55)]
        st.decisions = [Decision(title: "Покрытие", value: f.title, why: p.floorHeating == .none ? "износостойкость и простота укладки своими руками" : "совместимо с тёплым полом (теплопроводность, термостойкость)", ref: N.sp29.at("разд. 9 «Покрытия»"))]
        let plinth = perim * Double(max(p.floors, 1)) * 1.05
        switch f {
        case .tile:
            st.items = [WorkItem(name: "Керамогранит 600×600×10", qty: total * 1.1, unit: "м²", note: "+10 % на подрезку", digits: 0, price: f.price),
                        WorkItem(name: "Клей плиточный С2\(p.floorHeating == .none ? "" : "S1") 25 кг", qty: (total / 4).rounded(.up), unit: "мешок", digits: 0, price: 650),
                        WorkItem(name: "Затирка цементная 2 кг", qty: (total / 10).rounded(.up), unit: "уп", digits: 0, price: 450),
                        WorkItem(name: "Система выравнивания плитки СВП (зажимы + клинья)", qty: 1, unit: "компл", digits: 0, price: 2500)]
        default:
            st.items = [WorkItem(name: f.title, qty: total * 1.05, unit: "м²", note: "+5 % на подрезку", digits: 0, price: f.price)]
            if f != .engineered || p.floorSystemEff == .osbJoists { st.items.append(WorkItem(name: p.floorHeating == .none ? "Подложка 2 мм" : "Подложка для тёплого пола", qty: total * 1.05, unit: "м²", digits: 0, price: 150)) }
            if f == .engineered && p.floorSystemEff != .osbJoists { st.items.append(WorkItem(name: "Клей 2К полиуретановый для паркета 10 кг", qty: (total / 10).rounded(.up), unit: "шт", digits: 0, price: 4500)) }
        }
        st.items.append(WorkItem(name: "Плинтус МДФ/дюрополимер 80 мм 2.4 м с клипсами", qty: (plinth / 2.4).rounded(.up), unit: "шт", note: "\(fmt(plinth, 0)) м по периметру комнат", digits: 0, price: 600))
        st.tools = f == .tile ? ["Лазерный уровень", "Плиткорез ручной 600+ мм / мокрый", "Болгарка с алмазным диском", "Миксер-насадка для клея", "Шпатели зубчатые 8–10 мм", "СВП, резиновая киянка", "Резиновый шпатель для затирки"]
                              : ["Торцовочная пила или лобзик", "Добойник и брусок, монтажка для последнего ряда", "Клинья 10 мм", "Рулетка, угольник, карандаш", "Нож", "Шуруповёрт (плинтус)"]
        st.guides = [Guide(title: f == .tile ? "Как положить керамогранит на тёплый пол" : "Как уложить \(f.title.lowercased()) без отходов", steps: Array(st.steps.dropFirst(2)))]
        st.fasteners = [Fastener(what: "Плинтус", item: "клипсы + саморез 4×40 с дюбелем / по дереву (ГКЛ — в стойку или закладную)", how: "шуруповёрт, бита PH2"),
                        Fastener(what: "Порог / стыковочный профиль", item: "саморезы 3.5×25 в комплекте", how: "шуруповёрт")]
        return st
    }

    static func tools(_ s: FloorSystem, _ h: FloorHeating) -> [String] {
        var t: [String]
        switch s {
        case .semiDry: t = ["Лазерный нивелир (построитель плоскостей)", "Правило 2–3 м, маячный профиль", "Пневмонагнетатель + затирочная машина — обычно у бригады; руками — бетономешалка 160 л и тёрка", "Нож для ЭППС, ножовка", "Кельма, ведро, лопата", "Плёнка для ухода"]
        case .dryScreed: t = ["Шуруповёрт с ограничителем, бита PH2", "Ножовка/лобзик для ГВЛ", "Правило 2 м, уровень", "Шпатель для клея", "Пылесос строительный"]
        case .osbJoists: t = ["Правило 2 м", "Шлифмашина (кромки ОСП)", "Шуруповёрт", "Пылесос"]
        case .inSlab: t = ["Шлифмашина по бетону (аренда) или валик и раклей для наливного пола", "Миксер-насадка", "Манометр (давление в петлях)"]
        }
        switch h {
        case .water: t += ["Труборез и калибратор для PE-Xa", "Ручной расширитель + пресс-инструмент (или аренда)", "Опрессовщик ручной до 10 бар", "Такер для скоб-гарпунов"]
        case .electric: t += ["Мультиметр (сопротивление кабеля/плёнки и изоляции)", "Отвёртка-индикатор, клещи для гильз"]
        case .none: break
        }
        return t
    }

    static func guides(_ s: FloorSystem, _ h: FloorHeating) -> [Guide] {
        var g: [Guide] = []
        if h == .water && s != .inSlab {
            g.append(Guide(title: "Как уложить водяной тёплый пол «улиткой»", steps: [
                "Коллектор — в шкафу в центре дома или у котельной, выше уровня петель (для удаления воздуха).",
                "Разметить петли маркером по комнатам: каждая петля ≤ 15 м² и ≤ 80–100 м трубы, одна комната — одна или несколько петель, петли не пересекают деформационные швы.",
                "От коллектора довести подачу до дальнего угла комнаты и укладывать двойной спиралью к центру: подача и обратка идут рядом через одну, в центре — разворот «петлёй» диаметром ≥ 5 диаметров трубы, затем обратно к выходу.",
                "Шаг 150 мм у наружных стен и окон (краевая зона ~1 м), 200 мм в остальной части. Трубу разматывать с бухты вращением, без перегибов; скобы — через 500 мм и на каждом повороте.",
                "Подключить к коллектору (евроконус), подписать петли, опрессовать 6 бар на 24 ч. Схему с фото и рулеткой сохранить — потом не сверлите пол наугад.",
            ], tip: "Не экономьте на трубе: PE-Xa с кислородным барьером — 50 лет. Стыки труб внутри стяжки недопустимы."))
        }
        switch s {
        case .semiDry:
            g.append(Guide(title: "Как сделать полусухую стяжку своими руками", steps: [
                "Выставить маяки по лазеру на растворные «лепёшки» через 1.2–1.5 м (правило 2 м должно лечь на 2 маяка). Отметка верха = чистый пол − толщина покрытия.",
                "Смесь: на 1 мешок цемента М500 — 3 мешка песка (или готовый пескобетон М150), фибра, воды немного: смесь сыпучая, при сжатии в кулаке держит форму без выделения воды.",
                "Раскладывать картами 2–3 м² от дальней стены к выходу, уплотнить лопатой/трамбовкой, протянуть правилом по маякам.",
                "Через 30–60 мин, когда поверхность «схватилась» (след от пальца 1–2 мм), — затереть тёркой или затирочной машиной круговыми движениями, удалить маяки, заполнить борозды той же смесью.",
                "Сразу нарезать деформационные швы (в дверях и на больших площадях) кельмой на 1/3 толщины, укрыть плёнкой.",
            ], tip: "Полусухую стяжку больших площадей выгоднее заказать бригаде с пневмонагнетателем: за день — 100–150 м², ровнее и плотнее, чем вручную."))
        case .dryScreed:
            g.append(Guide(title: "Как собрать сухую стяжку из ГВЛ-элементов", steps: [
                "Проверить ОСП: ровность ≤ 2 мм на 2 м; если хуже — тонкая выравнивающая засыпка или шлифовка.",
                "Кромочная лента по периметру. Первый ряд — от дальней стены, у элементов у стены отрезать фальц.",
                "На фальц уложенного элемента — 2 полосы клея, наложить следующий, прижать, сразу шурупы 3.9×19 через 300 мм (не дальше 15 мм от кромки фальца).",
                "Следующий ряд — со сдвигом ≥ 250 мм. Обрезок последнего элемента ряда начинает новый ряд.",
                "Через 24 ч — срезать выдавленный клей, зашпаклевать шурупы и стыки.",
            ]))
        default: break
        }
        if h == .electric {
            g.append(Guide(title: "Как подключить электрический тёплый пол безопасно", steps: [
                "Отдельная линия от щита: автомат + УЗО/дифавтомат 30 мА, кабель по мощности (до 3 кВт — 3×2.5 мм²).",
                "Сопротивление нагревателя — измерить мультиметром и сверить с паспортом до укладки, после укладки и после стяжки/клея; записать в паспорт.",
                "Датчик температуры пола — в гофротрубке с заглушкой между витками, на 0.5 м от стены (можно будет заменить).",
                "Под мебелью без ножек, шкафами и сантехникой нагреватель не укладывать.",
            ]))
        }
        return g
    }

    static func fasteners(_ s: FloorSystem, _ h: FloorHeating) -> [Fastener] {
        var f: [Fastener] = []
        switch s {
        case .dryScreed: f.append(Fastener(what: "ГВЛ элементы пола по фальцу", item: "шурупы для элементов пола 3.9×19 (с двойной заходкой)", how: "шуруповёрт с ограничителем, бита PH2, шаг 300"))
        case .semiDry: f.append(Fastener(what: "Демпферная лента", item: "самоклеящаяся / степлер, скобы 10 мм", how: "вручную"))
        case .osbJoists: f.append(Fastener(what: "ОСП-22 к балкам (уже на этапе пола)", item: "саморезы по дереву 4.5×50 жёлтые + клей ПУ", how: "шуруповёрт, бита PZ2; утопить на 1–2 мм"))
        case .inSlab: break
        }
        if h == .water { f.append(Fastener(what: "Трубы тёплого пола", item: s == .semiDry ? "скобы-гарпуны 40–60 мм" : "в пазах панелей, без крепежа", how: s == .semiDry ? "такер, через 500 мм и на поворотах" : "—")) }
        if h == .electric { f.append(Fastener(what: "Кабель / плёнка", item: "монтажная лента / скотч", how: "вручную, без металлических скоб через нагреватель")) }
        return f
    }
}

// MARK: - Схемы пола

extension Drawings {
    static func floorSection(_ c: Ctx, _ cg: CGContext, _ rect: CGRect) {
        let p = c.p
        let F = c.b.frame
        let D = F.studExt.wm
        let layers = p.floorLayers
        let bu = p.floorBuildUp
        let joists = p.floorBase == .joists
        let k = 2.5                                  // по высоте ×2.5
        func Z(_ z: Double) -> Double { z * k }
        let W = 0.62
        let top = bu + 0.12
        let lo = V2(-D - 0.12, Z(-0.08)), hi = V2(W + 0.05, Z(top))
        let s = Sk(cg, rect, lo: lo, hi: hi, pad: 12, right: 250, top: 14)
        Sk.text("По высоте масштаб ×2.5, размеры — в мм. Пол: \(p.floorSystemEff.short), \(p.floorFinish.title)\(p.floorHeating == .none ? "" : ", тёплый пол \(p.floorHeating == .water ? "водяной" : "электрический")").",
                CGPoint(x: rect.minX + 8, y: rect.minY + 9), size: 7, color: .darkGray, maxW: rect.width - 16)
        if joists {
            s.box(-D, Z(-0.08), W, 0, .insulation)
            s.box(-D, 0, 0.012, Z(0.022), .board)
            s.label("балки \(F.floors.first?.check.sec.label ?? "") шаг 625 + утеплитель", V2(0.02, Z(-0.04)), size: 6.5, bg: true)
        } else {
            s.box(-D - 0.1, Z(-0.08), W, 0, .concrete)
            s.label(p.floorBase == .slab ? "плита фундамента" : "основание", V2(0.15, Z(-0.04)), size: 6.5, bg: true)
        }
        // стена
        let wb = joists ? 0.022 : 0.0
        s.box(-D, Z(wb), 0, Z(wb + 0.05), .timberCut)
        s.box(-D, Z(wb + 0.05), 0, Z(top), .insulation)
        s.box(-D - 0.009, joists ? Z(-0.08) : Z(wb), -D, Z(top), .board)
        // слои пола
        var z = 0.0
        var pipeZ: Double? = nil
        for l in layers {
            let t = max(l.t, 0.002)
            s.box(0.012, Z(z), W, Z(z + t), l.h, fill: l.fill)
            if l.name.contains("PE-Xa") || l.name.contains("кабель") { pipeZ = p.floorSystemEff == .semiDry ? z + 0.014 : z + t / 2 }
            z += t
        }
        if p.floorSystemEff == .semiDry || p.floorSystemEff == .dryScreed { s.box(0, Z(0), 0.01, Z(bu - p.floorFinish.t), fill: NSColor(srgbRed: 0.6, green: 0.8, blue: 0.95, alpha: 1)) }
        let gb = p.gklBase
        s.box(0.0, Z(gb + 0.01), 0.025, Z(top), fill: Sk.fillFor(.wood))
        s.box(0.025, Z(gb + 0.01), 0.025 + p.interiorFinish.t, Z(top), fill: p.interiorFinish == .gkl ? gklFill : Sk.fillFor(.board))
        s.box(0.04, Z(bu), 0.052, Z(bu + 0.06), fill: .white, stroke: .darkGray)
        if let zc = pipeZ, p.floorHeating == .water {
            var x = 0.1, i = 0
            while x < W - 0.04 { s.dot(V2(x, Z(zc)), max(2.5, CGFloat(0.008) * s.sc), i % 2 == 0 ? red : blue); x += 0.15; i += 1 }
            s.dim(V2(0.1, Z(zc) + 0.03), V2(0.25, Z(zc) + 0.03), off: 0.02, "150", size: 6.5)
        }
        // размеры: цепочка слоёв справа
        z = 0
        let xd = W + 0.015
        for l in layers where l.t >= 0.004 {
            s.dim(V2(xd, Z(z)), V2(xd, Z(z + l.t)), off: -0.01, "", size: 6)
            z += l.t
        }
        s.dim(V2(xd + 0.05, 0), V2(xd + 0.05, Z(bu)), off: -0.01, mm(bu), size: 6.5)
        s.line(V2(-D - 0.1, Z(bu)), V2(W + 0.05, Z(bu)), 0.8, green, dash: [5, 3])
        s.label("чистый пол = +\(mm(bu)) от \(joists ? "верха балок" : "плиты")", V2(0.08, Z(bu) + 0.06), size: 7, ay: 1, color: green, bg: true)
        // выноски: слои снизу вверх
        let lx = W + 0.22
        let n = Double(layers.count + 2)
        z = 0
        for (i, l) in layers.enumerated() {
            let t = max(l.t, 0.002)
            let ly = lo.y + (hi.y - lo.y) * (Double(i) + 0.5) / n
            s.leader(V2(0.12 + Double(i) * 0.07, Z(z + t / 2)), V2(lx, ly), l.name + " — \(fmt(l.t * 1000, l.t * 1000 == (l.t * 1000).rounded() ? 0 : 1))", size: 6.5)
            z += t
        }
        s.leader(V2(0.005, Z(0.02)), V2(lx, lo.y + (hi.y - lo.y) * (Double(layers.count) + 0.5) / n), p.floorSystemEff == .semiDry ? "Демпферная лента 10 мм" : "Кромочная лента / зазор 10 мм", size: 6.5)
        s.leader(V2(0.03, Z(top) - 0.05), V2(lx, lo.y + (hi.y - lo.y) * (Double(layers.count) + 1.4) / n), "\(p.interiorFinish.short) по обрешётке — \(gb > 0 ? "после стяжки, " : "")зазор 10 мм над полом", size: 6.5)
    }

    static func heatingLoop(_ c: Ctx, _ cg: CGContext, _ rect: CGRect) {
        let Wr = 4.0, Hr = 3.75
        let s = Sk(cg, rect, lo: V2(-0.6, -0.5), hi: V2(Wr + 0.3, Hr + 0.3), pad: 12, right: 200)
        s.box(-0.1, -0.1, Wr + 0.1, Hr + 0.1, fill: NSColor(white: 0.6, alpha: 1))
        s.box(0, 0, Wr, Hr, fill: NSColor(white: 0.97, alpha: 1))
        // двойная улитка: кольца с шагом 2s, подача и обратка чередуются
        var off = 0.15
        var k = 0
        while off < min(Wr, Hr) / 2 - 0.1 {
            let step = off < 1.0 ? 0.15 : 0.2
            let col = k % 2 == 0 ? red : blue
            s.poly([V2(off, off), V2(Wr - off, off), V2(Wr - off, Hr - off), V2(off, Hr - off)], fill: nil, stroke: col, w: 1.6)
            off += step; k += 1
        }
        // коллектор
        s.box(-0.55, 0.2, -0.2, 0.9, fill: NSColor(white: 0.85, alpha: 1), stroke: .black)
        s.label("коллектор", V2(-0.55, 1.0), size: 6.5, ay: 1)
        s.line(V2(-0.2, 0.4), V2(0.15, 0.4), 1.6, red); s.line(V2(-0.2, 0.6), V2(0.3, 0.6), 1.6, blue)
        s.dim(V2(0.15, Hr / 2), V2(0.3, Hr / 2), off: 0, "150", size: 6)
        s.dim(V2(1.2, Hr / 2), V2(1.4, Hr / 2), off: 0, "200", size: 6)
        s.dim(V2(0, -0.1), V2(Wr, -0.1), off: -0.25, "\(mm(Wr))", size: 7)
        s.dim(V2(Wr + 0.1, 0), V2(Wr + 0.1, Hr), off: -0.1, "\(mm(Hr))", size: 7)
        let lx = Wr + 0.35
        s.leader(V2(Wr - 0.15, Hr * 0.8), V2(lx, Hr * 0.9), "Подача (красная) и обратка (синяя) идут рядом через одну — пол прогревается равномерно", size: 6.5)
        s.leader(V2(Wr - 0.3, Hr * 0.5), V2(lx, Hr * 0.6), "Краевая зона у наружных стен: шаг 150 мм", size: 6.5)
        s.leader(V2(Wr / 2, Hr / 2), V2(lx, Hr * 0.35), "Центр: шаг 200 мм; разворот в центре — петля ≥ 5 Ø трубы", size: 6.5)
        s.leader(V2(-0.2, 0.5), V2(lx, Hr * 0.1), "Петля ≤ 15 м² и ≤ 80–100 м трубы PE-Xa 16; стыков в стяжке нет", size: 6.5)
        _ = c
    }
}
