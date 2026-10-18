import Foundation

/// Ориентировочные розничные цены, Московский регион (Леруа Мерлен, металлобазы, бетонные узлы).
/// Цены — до наценки; в расчёте добавляется запас `margin` (+8 %). Правьте здесь при изменении рынка.
enum Price {
    static let margin = 1.08
    static let note = "Цены ориентировочные (Московский регион, розница и бетонные узлы) с запасом +8 %. Работа не учтена."

    // Бетон на узле, ₽/м³
    static func concrete(_ c: ConcreteClass) -> Double {
        switch c {
        case .B15: return 5700
        case .B20: return 6100
        case .B25: return 6600
        case .B30: return 7000
        }
    }
    static let concretePrep = 5100.0        // B7.5 (М100), ₽/м³
    static let mixerTrip = 4500.0           // доставка миксером до 7 м³, ₽/рейс
    static let vibratorRent = 1500.0        // аренда глубинного вибратора, ₽/сутки

    // Арматура, ₽/т (металлобаза, резка в размер — отдельно)
    static func rebarPerTon(_ d: Int, _ cls: String) -> Double { d <= 8 || cls.contains("240") ? 82000 : 72000 }
    static func rebarPerM(_ d: Int, _ cls: String) -> Double { rebarPerTon(d, cls) / 1000 * Bar.mass(d) }
    static let wireKg = 260.0               // вязальная проволока Ø1.2, ₽/кг
    static let chair = 4.0                  // фиксатор «стульчик», ₽/шт
    static let star = 3.0                   // фиксатор «звёздочка», ₽/шт

    // Опалубка
    static let board25x150x6 = 450.0        // доска обрезная 25×150×6000, ₽/шт
    static let bar50x50M = 60.0             // брусок 50×50, ₽/м.п.
    static let nailsKg = 210.0              // гвозди 4×100, ₽/кг
    static let filmM2 = 25.0                // плёнка 150–200 мкм, ₽/м²
    static let tieSet = 110.0               // шпилька М12 + 2 гайки + 2 шайбы, ₽/компл
    static let pvcTubeM = 30.0              // трубка ПВХ Ø20, ₽/м
    static let post = 80.0                  // столбик обноски 50×50×1200, ₽/шт
    static let obnoskaBoardM = 75.0         // доска обноски, ₽/м.п.
    static let stringM = 3.0                // шнур разбивочный, ₽/м
    static let screwMark = 2.0              // саморез/гвоздь-метка, ₽/шт
    static let slatM = 30.0                 // маячная рейка 20×40, ₽/м.п.
    static let rule = 1300.0                // правило алюминиевое 2 м, ₽/шт

    // Сыпучие и изоляция
    static let sandM3 = 1100.0              // песок с доставкой, ₽/м³
    static let gravelM3 = 2500.0            // щебень гранитный 20–40 с доставкой, ₽/м³
    static let geotextileM2 = 40.0          // геотекстиль 150–200 г/м², ₽/м²
    static let roofingM2 = 250.0            // наплавляемая гидроизоляция, ₽/м²
    static let masticKg = 180.0             // битумная мастика, ₽/кг
    static let eps100M2 = 850.0             // ЭППС 100 мм, ₽/м²
    static let eps50M2 = 450.0              // ЭППС 50 мм, ₽/м²
    static let ruberoidM2 = 90.0            // рубероид (обсадная труба сваи), ₽/м²

    // Сваи
    static func screwPile(_ d: Double) -> Double { d < 0.1 ? 3000 : d < 0.12 ? 3800 : 5000 }

    // Отмостка
    static let pavingM2 = 800.0             // тротуарная плитка 60 мм, ₽/м²
    static let curbM = 250.0                // садовый бордюр, ₽/м.п.
    static let dryMixBag = 260.0            // ЦПС 40 кг, ₽/мешок
    static let damperTapeM = 40.0           // демпферная лента, ₽/м.п.

    // Дренаж и ливнёвка
    static let drainPipeM = 200.0           // дренажная труба Ø110 в геотекстиле, ₽/м
    static let stormPipeM = 250.0           // канализационная труба Ø110 (ливнёвка), ₽/м
    static let drainWell = 5500.0           // смотровой колодец Ø315 с днищем и крышкой
    static let collectorWell = 25000.0      // накопительный колодец Ø1000 / ж/б кольца
    static let rainInlet = 1500.0           // точечный дождеприёмник

    // Каркас: пиломатериалы, ₽/м³ (хвоя 2 сорт камерной сушки; брус обвязки — антисептированный)
    static func lumberM3(_ s: Lumber) -> Double { s.isBeam ? 26000 : s.t <= 25 ? 22000 : 25000 }
    static let osb9 = 780.0                 // ОСП-3 9 мм 2500×1250, ₽/лист
    static let osb12 = 980.0                // ОСП-3 12 мм
    static let osb22 = 1750.0               // ОСП-3 22 мм шпунт 2500×1250 (2440×590 — дороже)
    static let gkl = 480.0                  // ГКЛ 12.5 мм 2500×1200, ₽/лист
    static let woolM3 = 4200.0              // минвата 30–40 кг/м³, ₽/м³
    static let membraneM2 = 55.0            // супердиффузионная мембрана, ₽/м²
    static let vaporM2 = 22.0               // пароизоляционная плёнка, ₽/м²
    static let tapeButylM = 30.0            // бутилкаучуковая / акриловая лента, ₽/м
    static let sealTapeM = 45.0             // межвенцовый/уплотнительный ППЭ 5–8 мм под обвязку, ₽/м
    static let studM12 = 160.0              // шпилька резьбовая М12×1000 оц., ₽/шт
    static let nutWasherM12 = 18.0          // гайка М12 + шайба увелич. DIN 9021, ₽/компл
    static let chemAnchor = 950.0           // химический анкер 300 мл, ₽/картридж
    static let antisepticL = 120.0          // огнебиозащита, ₽/л
    static let nailsKgG = 230.0             // гвозди строительные 4×100 / 3.5×90, ₽/кг
    static let ringNailsKg = 380.0          // ершёные оцинк. 2.5×50 / 3.1×90, ₽/кг
    static let screwsKg = 650.0             // саморезы по дереву, ₽/кг
    static let anchorNailsKg = 520.0        // анкерные (ершёные) гвозди 4×40 оцинк., ₽/кг
    static let angle90 = 45.0               // уголок усиленный 90×90×65, ₽/шт
    static let joistHanger = 85.0           // опора балки 50×200, ₽/шт
    static let windStrap = 40.0             // ветровая скоба / перфолента на узел, ₽/шт
    static let boltM12 = 70.0               // болт/шпилька М12 с 2 гайками и шайбами, ₽/компл
    static let foamCan = 520.0              // пена монтажная 750 мл, ₽/баллон
    static let psulM = 70.0                 // ПСУЛ, ₽/м
    static let windowM2 = 9500.0            // окно ПВХ с монтажными материалами, ₽/м²
    static let doorInt = 9000.0             // межкомнатный блок с фурнитурой, ₽/шт
    static let doorExt = 32000.0            // стальная утеплённая входная, ₽/шт
    static let roofScrews = 1.6             // кровельный саморез 4.8×35, ₽/шт
    static func coveringM2(_ c: RoofCovering) -> Double {
        switch c {
        case .metalTile: return 680
        case .profiledSheet: return 560
        case .seam: return 1150
        case .slate: return 380
        case .ondulin: return 430
        case .softShingle: return 750
        case .compositeTile: return 1150
        case .ceramicTile: return 2600
        case .cementTile: return 1300
        }
    }
    static func facadeM2(_ f: FacadeFinish) -> Double {
        switch f {
        case .siding: return 380
        case .imitationTimber: return 950
        case .fiberCement: return 1600
        case .plaster: return 1700
        case .facingBrick: return 1900
        }
    }
    static let underlayM2 = 260.0           // подкладочный ковёр под мягкую черепицу, ₽/м²
    static let snowGuardM = 900.0           // трубчатый снегозадержатель, ₽/м.п.
    static let gutterM = 900.0              // водосточная система (желоб + доля трубы), ₽/м.п. карниза
}

extension WorkItem {
    var cost: Double { qty * price * Price.margin }
}

func rub(_ x: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = " "
    f.maximumFractionDigits = 0
    return (f.string(from: NSNumber(value: (x / 100).rounded() * 100)) ?? "\(Int(x))") + " ₽"
}
