import Foundation

enum ConcreteClass: String, CaseIterable, Identifiable {
    case B15, B20, B25, B30
    var id: String { rawValue }
    var mark: String {
        switch self {
        case .B15: return "М200"
        case .B20: return "М250"
        case .B25: return "М350"
        case .B30: return "М400"
        }
    }
    var title: String { "\(rawValue) (\(mark))" }
    /// СП 63.13330.2018 табл. 6.8, 6.11, МПа
    var Rb: Double {
        switch self {
        case .B15: return 8.5
        case .B20: return 11.5
        case .B25: return 14.5
        case .B30: return 17.0
        }
    }
    var Rbt: Double {
        switch self {
        case .B15: return 0.75
        case .B20: return 0.9
        case .B25: return 1.05
        case .B30: return 1.15
        }
    }
    var Eb: Double {
        switch self {
        case .B15: return 24000
        case .B20: return 27500
        case .B25: return 30000
        case .B30: return 32500
        }
    }
}

enum RebarClass: String, CaseIterable, Identifiable {
    case A400 = "А400", A500 = "А500С"
    var id: String { rawValue }
    /// СП 63.13330.2018 табл. 6.14, МПа
    var Rs: Double { self == .A400 ? 350 : 435 }
    var xiR: Double { self == .A400 ? 0.531 : 0.493 }
    var alphaR: Double { xiR * (1 - 0.5 * xiR) }
}

/// Поперечная арматура A240: Rsw = 170 МПа
let rswA240 = 170.0

enum Bar {
    static func area(_ d: Int) -> Double { .pi * Double(d * d) / 4 * 1e-6 }
    static func mass(_ d: Int) -> Double { 0.00617 * Double(d * d) }
}

enum RC {
    /// Требуемая площадь растянутой арматуры прямоугольного сечения, м² (СП 63, п. 8.1.8).
    /// M — кН·м, b, h0 — м. nil — сечение недостаточно (αm > αR).
    static func As(M: Double, b: Double, h0: Double, c: ConcreteClass, r: RebarClass) -> Double? {
        guard M > 0 else { return 0 }
        let am = M / (c.Rb * 1000 * b * h0 * h0)
        guard am < r.alphaR else { return nil }
        let xi = 1 - (1 - 2 * am).squareRoot()
        return xi * c.Rb * b * h0 / r.Rs
    }

    /// Длина нахлёста растянутых стержней, м — СП 63.13330.2018 п. 10.3.29–10.3.31
    static func lap(d: Int, c: ConcreteClass, r: RebarClass) -> Double {
        let rbond = 2.5 * 1.0 * c.Rbt
        let l0an = r.Rs * Double(d) / 1000 / (4 * rbond)
        let l = max(1.2 * l0an, 20 * Double(d) / 1000, 0.25)
        return roundUp(l, 0.05)
    }
}
