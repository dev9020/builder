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
