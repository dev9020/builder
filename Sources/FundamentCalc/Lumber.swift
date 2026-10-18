import Foundation

/// Сечение пиломатериала, мм (t — толщина, w — ширина) по ГОСТ 24454-80
struct Lumber: Hashable, Comparable {
    let t: Int, w: Int
    init(_ t: Int, _ w: Int) { self.t = t; self.w = w }
    var tm: Double { Double(t) / 1000 }
    var wm: Double { Double(w) / 1000 }
    var label: String { "\(t)×\(w)" }
    var isBeam: Bool { t >= 100 }
    static func < (a: Lumber, b: Lumber) -> Bool { (a.t, a.w) < (b.t, b.w) }

    /// Название для магазина
    var shopName: String { shopName(6.0) }
    func shopName(_ stock: Double) -> String {
        let L = Int((stock * 1000).rounded())
        if t <= 32 { return "Доска обрезная \(label)×\(L), хвойные породы, 2 сорт, камерной сушки" }
        if isBeam { return "Брус \(label)×\(L), хвойные породы, 2 сорт, камерной сушки" }
        return t <= 50 && w <= 50 ? "Брусок \(label)×3000, хвойные, строганый, сухой"
                                  : "Доска обрезная \(label)×\(L), хвойные породы, 2 сорт, камерной сушки (W ≤ 20 %)"
    }
}

/// Расчёт деревянных элементов по СП 64.13330.2017 (сосна/ель, 2 сорт, класс К24)
enum Timber {
    /// Расчётное сопротивление изгибу/сжатию с учётом mдл = 0.66, МПа (табл. 3 и 4)
    static let Ri = 19.5 * 0.66
    static let Rc = 19.5 * 0.66
    /// Модуль упругости вдоль волокон, МПа
    static let E = 10000.0
    /// Предельный прогиб по СП 20.13330.2016, табл. Д.1 (балки перекрытий, стропила) — 1/n
    static func deflLimit(_ l: Double) -> Double {
        let pts: [(Double, Double)] = [(1, 120), (3, 150), (6, 200), (24, 250)]
        if l <= 1 { return 120 }
        for i in 1..<pts.count where l <= pts[i].0 {
            let (l0, n0) = pts[i - 1], (l1, n1) = pts[i]
            return n0 + (n1 - n0) * (l - l0) / (l1 - l0)
        }
        return 250
    }

    struct BeamCheck {
        var sec: Lumber
        var count: Int = 1          // сколько досок в пакете
        var step: Double
        var span: Double
        var M = 0.0, sigma = 0.0, f = 0.0, fu = 0.0
        var ok = false
        var title: String { count > 1 ? "\(count)×(\(sec.label))" : sec.label }
    }

    /// Подбор балки: qd, qn — расчётная и нормативная нагрузка, кПа (на горизонтальную проекцию);
    /// span — пролёт, м; cosA — для стропил (прогиб по длине ската)
    static func pickBeam(span: Double, qd: Double, qn: Double, steps: [Double], cosA: Double = 1,
                         sizes: [Lumber] = [Lumber(50, 150), Lumber(50, 200), Lumber(50, 250)], counts: [Int] = [1, 2]) -> BeamCheck {
        var last: BeamCheck?
        for c in counts {
            for st in steps {
                for s in sizes {
                    let r = check(s, count: c, step: st, span: span, qd: qd, qn: qn, cosA: cosA)
                    if r.ok { return r }
                    last = r
                }
            }
        }
        return last ?? check(sizes.last!, count: counts.last!, step: steps.last!, span: span, qd: qd, qn: qn, cosA: cosA)
    }

    static func check(_ s: Lumber, count: Int, step: Double, span: Double, qd: Double, qn: Double, cosA: Double = 1) -> BeamCheck {
        var r = BeamCheck(sec: s, count: count, step: step, span: span)
        let b = s.tm * Double(count), h = s.wm
        let W = b * h * h / 6, I = b * h * h * h / 12
        r.M = qd * step * span * span / 8                          // кН·м
        r.sigma = r.M / W / 1000                                   // МПа
        let L = span / cosA
        let qperp = qn * step * cosA * cosA                        // нормальная к оси составляющая на 1 м длины элемента
        r.f = 5 * qperp * pow(L, 4) / (384 * E * 1000 * I)         // м
        r.fu = L / deflLimit(L)
        r.ok = r.sigma <= Ri && r.f <= r.fu
        return r
    }

    /// Устойчивость стойки (СП 64.13330.2017, разд. 7 — центрально-сжатые элементы): N — кН на стойку, l — расчётная длина, м
    static func studCheck(_ s: Lumber, N: Double, l: Double) -> (phi: Double, sigma: Double, ok: Bool) {
        // из плоскости стены стойку раскрепляет обшивка/распорки, расчёт — в плоскости наибольшей гибкости вдоль высоты сечения
        let h = s.wm, b = s.tm
        let i = 0.289 * h
        let lam = l / i
        let phi = lam <= 70 ? 1 - 0.8 * pow(lam / 100, 2) : 3000 / (lam * lam)
        let sigma = N / (phi * b * h) / 1000
        return (phi, sigma, sigma <= Rc)
    }

    /// Раскрой элементов по стандартной длине (6 м): первая подходящая по убыванию.
    /// Элементы длиннее хлыста режутся на части (стык — на опоре / с накладками).
    static func pack(_ lengths: [Double], stock: Double = 6.0, kerf: Double = 0.005) -> Int {
        var parts: [Double] = []
        for l in lengths {
            var rest = l
            while rest > stock { parts.append(stock); rest -= stock - 0.3 }   // 0.3 — нахлёст/запас на стык
            if rest > 0.01 { parts.append(rest) }
        }
        parts.sort(by: >)
        var bins: [Double] = []
        for p in parts {
            if let i = bins.firstIndex(where: { $0 >= p + kerf }) { bins[i] -= p + kerf } else { bins.append(stock - p - kerf) }
        }
        return bins.count
    }
}

// MARK: - Климат и теплозащита

struct HeatClimate {
    let tHeat: Double      // средняя температура отопительного периода (t ≤ 8 °C), °C
    let zHeat: Double      // продолжительность, сут
    var gsop: Double { (20 - tHeat) * zHeat }
}

enum Thermal {
    /// Требуемое сопротивление теплопередаче R = a·ГСОП + b, м²·°C/Вт (СП 50.13330, табл. базовых значений, жилые здания)
    static func rWall(_ g: Double) -> Double { 0.00035 * g + 1.4 }
    static func rRoof(_ g: Double) -> Double { 0.0005 * g + 2.2 }
    static func rFloor(_ g: Double) -> Double { 0.00045 * g + 1.9 }
    static func rWindow(_ g: Double) -> Double { 0.000075 * g + 0.15 }
    /// Теплопроводность минеральной ваты (условия Б), Вт/(м·°C)
    static let lambdaWool = 0.040
    /// Коэффициент теплотехнической однородности каркасной стены (деревянные стойки шаг 600)
    static let rFrame = 0.85

    /// Требуемая толщина утеплителя, кратная 50 мм
    static func woolThickness(_ R: Double) -> Double {
        let rs = 1 / 8.7 + 1 / 12.0 + 0.03     // сопротивления поверхностей + обшивки
        return roundUp(max(0.05, (R - rs) * lambdaWool / rFrame), 0.05)
    }
    static func rOf(_ d: Double) -> Double { d / lambdaWool * rFrame + 1 / 8.7 + 1 / 12.0 + 0.03 }
}

// MARK: - Стандартные оконные и дверные блоки

struct StdBlock: Identifiable, Hashable {
    let id: String
    let kind: OpeningKind
    let w: Double, h: Double              // размер блока, м
    let name: String                      // название в магазине/на заводе
    let ref: String
    /// Черновой проём в каркасе: монтажный зазор 20 мм по бокам и сверху, 30 мм снизу (подставочный профиль)
    var roW: Double { w + (kind.isDoor ? 0.06 : 0.04) }
    var roH: Double { h + (kind.isDoor ? 0.03 : 0.05) }
    var mm: String { "\(Int((w * 1000).rounded()))×\(Int((h * 1000).rounded()))" }

    static func window(_ w: Int, _ h: Int, _ sash: String) -> StdBlock {
        StdBlock(id: "w\(w)x\(h)", kind: .window, w: Double(w) / 1000, h: Double(h) / 1000,
                 name: "Блок оконный ПВХ \(w)×\(h) мм, \(sash), профиль 70 мм, стеклопакет 2-камерный",
                 ref: "\(N.g23166.code), \(N.g30674.code)")
    }

    static let catalog: [StdBlock] = [
        window(600, 600, "1 створка поворотно-откидная"),
        window(600, 900, "1 створка поворотно-откидная"),
        window(900, 1200, "1 створка поворотно-откидная"),
        window(900, 1400, "1 створка поворотно-откидная"),
        window(1200, 1200, "2 створки (глухая + поворотно-откидная)"),
        window(1200, 1400, "2 створки (поворотная + поворотно-откидная)"),
        window(1300, 1400, "2 створки (поворотная + поворотно-откидная)"),
        window(1450, 1400, "2 створки (поворотная + поворотно-откидная)"),
        window(1500, 1500, "2 створки (поворотная + поворотно-откидная)"),
        window(1800, 1400, "3 створки (поворотно-откидная + глухая + поворотная)"),
        window(2050, 1400, "3 створки (поворотно-откидная + глухая + поворотная)"),
        StdBlock(id: "p900", kind: .panoramic, w: 0.9, h: 2.1, name: "Блок оконный ПВХ 900×2100 мм в пол, 1 створка, нижнее поле — закалённое стекло", ref: "\(N.g23166.code), \(N.g30674.code)"),
        StdBlock(id: "p1500", kind: .panoramic, w: 1.5, h: 2.1, name: "Блок оконный ПВХ 1500×2100 мм в пол, 2 створки, закалённое/триплекс внизу", ref: "\(N.g23166.code), \(N.g30674.code)"),
        StdBlock(id: "p2000", kind: .panoramic, w: 2.0, h: 2.35, name: "Блок оконный ПВХ 2000×2350 мм в пол, глухая + поворотная, триплекс внизу", ref: "\(N.g23166.code), \(N.g30674.code)"),
        StdBlock(id: "p2500", kind: .panoramic, w: 2.5, h: 2.35, name: "Блок оконный ПВХ 2500×2350 мм в пол, 3 поля, триплекс внизу", ref: "\(N.g23166.code), \(N.g30674.code)"),
        StdBlock(id: "g800", kind: .glassDoor, w: 0.8, h: 2.1, name: "Блок балконный (дверь) ПВХ 800×2100 мм, поворотно-откидная, низкий порог", ref: "\(N.g23166.code), \(N.g30674.code)"),
        StdBlock(id: "g900", kind: .glassDoor, w: 0.9, h: 2.2, name: "Блок балконный (дверь) ПВХ 900×2200 мм, поворотно-откидная", ref: "\(N.g23166.code), \(N.g30674.code)"),
        StdBlock(id: "g1800", kind: .glassDoor, w: 1.8, h: 2.2, name: "Портал раздвижной (PSK) ПВХ 1800×2200 мм", ref: "\(N.g23166.code), \(N.g30674.code)"),
        StdBlock(id: "g2400", kind: .glassDoor, w: 2.4, h: 2.3, name: "Портал раздвижной (PSK/HST) 2400×2300 мм", ref: "\(N.g23166.code), \(N.g30674.code)"),
        StdBlock(id: "d670", kind: .door, w: 0.67, h: 2.071, name: "Блок дверной межкомнатный ДГ 21-7 (полотно 600×2000, коробка 670×2071)", ref: N.g475.code),
        StdBlock(id: "d770", kind: .door, w: 0.77, h: 2.071, name: "Блок дверной межкомнатный ДГ 21-8 (полотно 700×2000, коробка 770×2071)", ref: N.g475.code),
        StdBlock(id: "d870", kind: .door, w: 0.87, h: 2.071, name: "Блок дверной межкомнатный ДГ 21-9 (полотно 800×2000, коробка 870×2071)", ref: N.g475.code),
        StdBlock(id: "d970", kind: .door, w: 0.97, h: 2.071, name: "Блок дверной ДГ 21-10 (полотно 900×2000, коробка 970×2071)", ref: N.g475.code),
        StdBlock(id: "s860", kind: .door, w: 0.86, h: 2.05, name: "Блок дверной стальной входной утеплённый с терморазрывом 860×2050 мм", ref: N.g31173.code),
        StdBlock(id: "s960", kind: .door, w: 0.96, h: 2.05, name: "Блок дверной стальной входной утеплённый с терморазрывом 960×2050 мм", ref: N.g31173.code),
        StdBlock(id: "s1200", kind: .door, w: 1.2, h: 2.05, name: "Блок дверной стальной входной полуторный 1200×2050 мм", ref: N.g31173.code),
    ]

    /// Ближайший стандартный блок по размеру проёма (для наружных дверей — только стальные)
    static func nearest(_ o: Opening, exterior: Bool) -> StdBlock {
        let cand = catalog.filter { b in
            guard b.kind == o.kind else { return false }
            if o.kind == .door { return exterior ? b.id.hasPrefix("s") : b.id.hasPrefix("d") }
            return true
        }
        return cand.min { abs($0.roW - o.width) + abs($0.roH - o.height) < abs($1.roW - o.width) + abs($1.roH - o.height) } ?? catalog[5]
    }
}
