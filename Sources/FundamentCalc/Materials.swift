import SwiftUI
import AppKit

func rgb(_ r: Double, _ g: Double, _ b: Double) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }

enum HouseShape: String, CaseIterable, Identifiable {
    case square, rectangle, lShape, uShape, ring
    var id: String { rawValue }
    var title: String {
        switch self {
        case .square: return "Квадрат"
        case .rectangle: return "Прямоуг."
        case .lShape: return "Угловой"
        case .uShape: return "П-образный"
        case .ring: return "С двором"
        }
    }
}

/// Каркасные стены (вес — с обшивками ОСП/ГКЛ, утеплителем, плёнками и обрешёткой; без фасадной отделки)
enum WallMaterial: String, CaseIterable, Identifiable {
    case frame150, frame200, frame250, sip
    var id: String { rawValue }

    var title: String {
        switch self {
        case .frame150: return "Каркас 150 мм (стойки 50×150)"
        case .frame200: return "Каркас 200 мм (стойки 50×200)"
        case .frame250: return "Каркас 250 мм (200 + 50 перекрёстный)"
        case .sip: return "СИП-панели 174 мм"
        }
    }

    var short: String {
        switch self {
        case .frame150: return "Каркас 150"
        case .frame200: return "Каркас 200"
        case .frame250: return "Каркас 250"
        case .sip: return "СИП 174"
        }
    }

    /// Толщина стены с обшивками, м
    var defaultThickness: Double {
        switch self {
        case .frame150: return 0.18
        case .frame200: return 0.23
        case .frame250: return 0.28
        case .sip: return 0.19
        }
    }

    /// Нормативный вес 1 м² стены при типовой толщине, кН/м²
    var baseWeight: Double {
        switch self {
        case .frame150: return 0.45
        case .frame200: return 0.52
        case .frame250: return 0.60
        case .sip: return 0.35
        }
    }

    /// Коэффициент надёжности по нагрузке (дерево), СП 20.13330.2016 табл. 7.1
    var gammaF: Double { 1.1 }

    var isMasonry: Bool { false }

    /// Типовая толщина внутренней стены/перегородки, м
    func partitionThickness(bearing: Bool) -> Double { bearing ? 0.175 : 0.10 }

    /// Нормативный вес 1 м² стены, кН/м²
    func areaWeight(_ t: Double) -> Double { baseWeight * (0.6 + 0.4 * t / defaultThickness) }

    /// Цвет в 3D (используется только для легенды; стены рисуются текстурой фасада)
    var nsColor: NSColor {
        switch self {
        case .frame150: return rgb(0.90, 0.80, 0.60)
        case .frame200: return rgb(0.85, 0.72, 0.50)
        case .frame250: return rgb(0.78, 0.62, 0.40)
        case .sip: return rgb(0.80, 0.78, 0.68)
        }
    }

    /// Цвет на плане
    var planColor: Color {
        switch self {
        case .frame150: return Color(red: 0.95, green: 0.70, blue: 0.30)
        case .frame200: return Color(red: 0.85, green: 0.55, blue: 0.18)
        case .frame250: return Color(red: 0.65, green: 0.40, blue: 0.12)
        case .sip: return Color(red: 0.45, green: 0.60, blue: 0.40)
        }
    }
}

/// Фасадная отделка каркасного дома
enum FacadeFinish: String, CaseIterable, Identifiable {
    case siding, imitationTimber, fiberCement, plaster, facingBrick
    var id: String { rawValue }
    var title: String {
        switch self {
        case .siding: return "Сайдинг"
        case .imitationTimber: return "Имитация бруса / планкен"
        case .fiberCement: return "Фиброцементные панели"
        case .plaster: return "Штукатурный фасад по утеплителю"
        case .facingBrick: return "Облицовочный кирпич 120 мм"
        }
    }
    /// Вес отделки с обрешёткой/подсистемой, кН/м²
    var weight: Double {
        switch self {
        case .siding: return 0.08
        case .imitationTimber: return 0.15
        case .fiberCement: return 0.22
        case .plaster: return 0.35
        case .facingBrick: return 2.3
        }
    }
}

enum FloorType: String, CaseIterable, Identifiable {
    case woodJoists, woodScreed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .woodJoists: return "Деревянные балки, утеплитель, пол"
        case .woodScreed: return "Деревянные балки + СМЛ/стяжка (тёплый пол)"
        }
    }
    /// Постоянная нормативная, кПа
    var dead: Double { self == .woodJoists ? 0.7 : 1.3 }
    var gammaF: Double { 1.2 }
}

enum GroundFloorType: String, CaseIterable, Identifiable {
    case onGround, wood
    var id: String { rawValue }
    var title: String {
        switch self {
        case .onGround: return "Пол по грунту / на плите"
        case .wood: return "Деревянные балки на фундаменте"
        }
    }
    var dead: Double { self == .wood ? 0.7 : 0 }
    var gammaF: Double { 1.2 }
}

enum RoofType: String, CaseIterable, Identifiable {
    case flat, shed, gable, hip
    var id: String { rawValue }
    var title: String {
        switch self {
        case .flat: return "Плоская (деревянные балки)"
        case .shed: return "Односкатная"
        case .gable: return "Двускатная"
        case .hip: return "Вальмовая (4-скатная)"
        }
    }
}

enum RoofCovering: String, CaseIterable, Identifiable {
    case metalTile, profiledSheet, seam, slate, ondulin, softShingle, compositeTile, ceramicTile, cementTile
    var id: String { rawValue }
    var title: String {
        switch self {
        case .metalTile: return "Металлочерепица"
        case .profiledSheet: return "Профнастил"
        case .seam: return "Фальцевая кровля"
        case .slate: return "Шифер (асбестоцементный)"
        case .ondulin: return "Ондулин"
        case .softShingle: return "Мягкая черепица + ОСП"
        case .compositeTile: return "Композитная черепица"
        case .ceramicTile: return "Керамическая черепица"
        case .cementTile: return "Цементно-песчаная черепица"
        }
    }
    /// Вес покрытия, кПа по скату
    var weight: Double {
        switch self {
        case .metalTile, .profiledSheet: return 0.05
        case .seam: return 0.06
        case .slate: return 0.15
        case .ondulin: return 0.04
        case .softShingle: return 0.16
        case .compositeTile: return 0.07
        case .ceramicTile, .cementTile: return 0.50
        }
    }
    /// Минимальный уклон по рекомендациям производителей / СП 17.13330, град
    var minSlope: Double {
        switch self {
        case .metalTile: return 14
        case .profiledSheet: return 8
        case .seam: return 8
        case .slate: return 12
        case .ondulin: return 6
        case .softShingle: return 12
        case .compositeTile: return 12
        case .ceramicTile, .cementTile: return 22
        }
    }
    /// Уклон, при котором снег, как правило, сходит самостоятельно, град
    var snowSlideSlope: Double {
        switch self {
        case .metalTile, .profiledSheet, .seam, .compositeTile: return 25
        default: return 35
        }
    }

    var nsColor: NSColor {
        switch self {
        case .metalTile: return rgb(0.50, 0.15, 0.13)
        case .profiledSheet: return rgb(0.25, 0.38, 0.30)
        case .seam: return rgb(0.30, 0.32, 0.35)
        case .slate: return rgb(0.62, 0.63, 0.62)
        case .ondulin: return rgb(0.35, 0.22, 0.16)
        case .softShingle: return rgb(0.30, 0.22, 0.18)
        case .compositeTile: return rgb(0.25, 0.25, 0.27)
        case .ceramicTile: return rgb(0.75, 0.38, 0.20)
        case .cementTile: return rgb(0.55, 0.30, 0.22)
        }
    }
}

enum FlatRoofSlab: String, CaseIterable, Identifiable {
    case wood, woodBallast
    var id: String { rawValue }
    var title: String { self == .wood ? "Деревянные балки + мембрана" : "Деревянные балки + балласт (гравий 50 мм)" }
    var weight: Double { self == .wood ? 1.0 : 1.9 }
}

enum SnowRegion: Int, CaseIterable, Identifiable {
    case r1 = 1, r2, r3, r4, r5, r6, r7, r8
    var id: Int { rawValue }
    /// Нормативное значение веса снегового покрова S0, кПа (СП 20.13330.2016, табл. 10.1)
    var s0: Double { 0.5 * Double(rawValue) }
    var roman: String { ["I", "II", "III", "IV", "V", "VI", "VII", "VIII"][rawValue - 1] }
    var title: String { "\(roman) — \(fmt(s0, 1)) кПа" }
}

enum FoundationKind: String, CaseIterable, Identifiable {
    case strip, slab, piles
    var id: String { rawValue }
    var title: String {
        switch self {
        case .strip: return "Ленточный"
        case .slab: return "Плита"
        case .piles: return "Сваи + ростверк"
        }
    }
}

enum StripKind: String, CaseIterable, Identifiable {
    case deep, shallow
    var id: String { rawValue }
    var title: String { self == .deep ? "Заглублённая (ниже промерзания)" : "Мелкозаглублённая (МЗЛФ)" }
}

enum PileType: String, CaseIterable, Identifiable {
    case bored, boredEnlarged, screw
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bored: return "Буронабивные"
        case .boredEnlarged: return "Буронабивные с уширением (ТИСЭ)"
        case .screw: return "Винтовые"
        }
    }
}

struct City: Identifiable {
    let name: String
    let mt: Double
    let snow: SnowRegion
    var tHeat = -3.0       // средняя t отопительного периода, °C (СП 131.13330.2020, табл. 3.1, период t ≤ 8 °C)
    var zHeat = 210.0      // его продолжительность, сут
    var id: String { name }
}

/// Mt — сумма абсолютных среднемесячных отрицательных температур (ориентировочно, по СП 131.13330).
let cities: [City] = [
    City(name: "Москва", mt: 23, snow: .r3, tHeat: -2.2, zHeat: 205),
    City(name: "Санкт-Петербург", mt: 16, snow: .r3, tHeat: -1.3, zHeat: 213),
    City(name: "Нижний Новгород", mt: 29, snow: .r4, tHeat: -3.6, zHeat: 211),
    City(name: "Казань", mt: 35, snow: .r4, tHeat: -4.8, zHeat: 208),
    City(name: "Самара", mt: 33, snow: .r4, tHeat: -4.7, zHeat: 196),
    City(name: "Уфа", mt: 43, snow: .r5, tHeat: -5.4, zHeat: 203),
    City(name: "Пермь", mt: 46, snow: .r5, tHeat: -5.5, zHeat: 222),
    City(name: "Екатеринбург", mt: 44, snow: .r3, tHeat: -5.4, zHeat: 221),
    City(name: "Челябинск", mt: 48, snow: .r3, tHeat: -5.7, zHeat: 212),
    City(name: "Омск", mt: 62, snow: .r3, tHeat: -7.7, zHeat: 216),
    City(name: "Новосибирск", mt: 63, snow: .r4, tHeat: -7.9, zHeat: 222),
    City(name: "Красноярск", mt: 54, snow: .r3, tHeat: -6.5, zHeat: 228),
    City(name: "Иркутск", mt: 64, snow: .r2, tHeat: -7.9, zHeat: 232),
    City(name: "Хабаровск", mt: 71, snow: .r2, tHeat: -9.3, zHeat: 202),
    City(name: "Воронеж", mt: 22, snow: .r3, tHeat: -2.5, zHeat: 190),
    City(name: "Волгоград", mt: 14, snow: .r2, tHeat: -1.7, zHeat: 176),
    City(name: "Ростов-на-Дону", mt: 7, snow: .r2, tHeat: -0.1, zHeat: 166),
    City(name: "Краснодар", mt: 1.5, snow: .r2, tHeat: 2.0, zHeat: 145),
    City(name: "Минск", mt: 13, snow: .r2, tHeat: -0.9, zHeat: 196),
    City(name: "Киев", mt: 9, snow: .r2, tHeat: -0.1, zHeat: 176),
    City(name: "Алматы", mt: 11, snow: .r3, tHeat: -1.6, zHeat: 164),
    City(name: "Астана", mt: 54, snow: .r3, tHeat: -8.1, zHeat: 215),
]
