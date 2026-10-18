import Foundation

enum HeaveClass: Int, CaseIterable, Identifiable {
    case none, weak, medium, strong
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .none: return "Непучинистый"
        case .weak: return "Слабопучинистый"
        case .medium: return "Среднепучинистый"
        case .strong: return "Сильнопучинистый"
        }
    }
    /// Удельная касательная сила морозного пучения τfh, кПа (ориентировочно, СП 22.13330 / СП 24.13330)
    var tauFh: Double {
        switch self {
        case .none: return 0
        case .weak: return 60
        case .medium: return 90
        case .strong: return 110
        }
    }
}

struct Soil: Equatable {
    var name: String
    var gamma: Double     // удельный вес, кН/м³
    var phi: Double       // угол внутреннего трения, град
    var c: Double         // удельное сцепление, кПа
    var E: Double         // модуль деформации, МПа
    var gammaC1: Double   // коэф. условий работы γc1, СП 22 табл. 5.4
    var d0: Double        // для dfn = d0·√Mt, СП 22 п. 5.5.3
    var heave: HeaveClass
    var kSub: Double      // коэффициент постели, кН/м³
    var fSide: Double     // расчётное сопротивление по боковой поверхности сваи, кПа
    var rTip: Double      // расчётное сопротивление под нижним концом буронабивной сваи на гл. ~2.5–3 м, кПа

    static let presets: [Soil] = [
        Soil(name: "Песок средней крупности, ср. плотности", gamma: 18.0, phi: 35, c: 1, E: 30, gammaC1: 1.4, d0: 0.30, heave: .none, kSub: 30000, fSide: 35, rTip: 1700),
        Soil(name: "Песок мелкий, влажный", gamma: 17.5, phi: 30, c: 2, E: 25, gammaC1: 1.3, d0: 0.28, heave: .weak, kSub: 20000, fSide: 28, rTip: 1100),
        Soil(name: "Песок пылеватый, водонасыщенный", gamma: 18.5, phi: 26, c: 2, E: 14, gammaC1: 1.1, d0: 0.28, heave: .medium, kSub: 10000, fSide: 20, rTip: 600),
        Soil(name: "Супесь пластичная (IL 0…0.5)", gamma: 19.0, phi: 24, c: 10, E: 16, gammaC1: 1.2, d0: 0.28, heave: .strong, kSub: 15000, fSide: 25, rTip: 800),
        Soil(name: "Суглинок тугопластичный (IL 0.25…0.5)", gamma: 19.0, phi: 20, c: 20, E: 14, gammaC1: 1.2, d0: 0.23, heave: .medium, kSub: 15000, fSide: 27, rTip: 900),
        Soil(name: "Суглинок мягкопластичный (IL 0.5…0.75)", gamma: 18.5, phi: 16, c: 14, E: 8, gammaC1: 1.1, d0: 0.23, heave: .strong, kSub: 6000, fSide: 14, rTip: 450),
        Soil(name: "Глина тугопластичная", gamma: 19.5, phi: 16, c: 40, E: 15, gammaC1: 1.2, d0: 0.23, heave: .medium, kSub: 15000, fSide: 30, rTip: 1000),
        Soil(name: "Глина полутвёрдая", gamma: 20.0, phi: 19, c: 55, E: 22, gammaC1: 1.25, d0: 0.23, heave: .weak, kSub: 25000, fSide: 40, rTip: 1600),
    ]

    /// Расчётное сопротивление грунта основания R, кПа — СП 22.13330.2016, формула (5.7).
    /// Подвала нет (db = 0, d1 = d), k = 1.1 (характеристики по таблицам), γc2 = 1.0.
    static func R(_ s: Soil, b: Double, d: Double, gwl: Double, gammaC2: Double = 1.0) -> Double {
        let m = coefficients(s.phi)
        let kz = b < 10 ? 1.0 : 8.0 / b + 0.2
        let gBelow = gwl < d + b / 2 ? max(s.gamma - 10, 8) : s.gamma
        let k = 1.1
        return s.gammaC1 * gammaC2 / k * (m.mg * kz * b * gBelow + m.mq * max(d, 0) * s.gamma + m.mc * s.c)
    }

    /// Mγ, Mq, Mc — СП 22.13330.2016 табл. 5.5 (аналитические выражения)
    static func coefficients(_ phiDeg: Double) -> (mg: Double, mq: Double, mc: Double) {
        let f = max(1, phiDeg) * .pi / 180
        let ct = 1 / tan(f)
        let den = ct + f - .pi / 2
        return (.pi / (4 * den), 1 + .pi / den, .pi * ct / den)
    }

    /// Осадка методом послойного суммирования, СП 22.13330.2016 п. 5.6.31 (β = 0.8),
    /// граница сжимаемой толщи — σzp = 0.5 σzg. Возвращает осадку (м) и Hc (м).
    static func settlement(p: Double, d: Double, b: Double, l: Double, soil: Soil) -> (s: Double, hc: Double) {
        let p0 = max(0, p - soil.gamma * max(d, 0))
        let hi = min(0.1, 0.4 * b)
        var z = 0.0, s = 0.0
        while z < 60 {
            let zm = z + hi / 2
            let szp = alpha(zm, b, l) * p0
            let szg = soil.gamma * (max(d, 0) + zm)
            if szp <= 0.5 * szg { break }
            s += 0.8 * szp * hi / (soil.E * 1000)
            z += hi
        }
        return (s, z)
    }

    /// Коэффициент α под центром прямоугольной площадки b×l на глубине z
    static func alpha(_ z: Double, _ b: Double, _ l: Double) -> Double {
        if z < 1e-6 { return 1 }
        let m = (b / 2) / z, n = (l / 2) / z
        let r = (1 + m * m + n * n).squareRoot()
        let i = (atan(m * n / r) + m * n / r * (1 / (1 + m * m) + 1 / (1 + n * n))) / (2 * Double.pi)
        return 4 * i
    }
}
