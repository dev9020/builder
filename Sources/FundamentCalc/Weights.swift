import Foundation

struct WeightItem: Identifiable {
    let id = UUID()
    let name: String
    let kN: Double
    var note = ""
    var t: Double { kN / 9.81 }
}

/// Сводка: сколько весит дом (летом/зимой, с мебелью) и сколько выдерживает фундамент
struct WeightReport {
    var structure: [WeightItem] = []    // конструкции дома
    var snow = 0.0                      // снег зимой, кН
    var contents: [WeightItem] = []     // мебель, техника, люди, вода — оценка
    var liveNorm = 0.0                  // полезная по СП 20, кН
    var foundationSelf = 0.0            // вес фундамента, кН
    var capacity = 0.0                  // какую нагрузку от дома выдержит фундамент, кН
    var load = 0.0                      // нагрузка от дома, с которой сравниваем, кН
    var basis = ""                      // на чём основана несущая способность
    var local = ""                      // самый нагруженный участок
    var localRatio = 0.0

    var dead: Double { structure.reduce(0) { $0 + $1.kN } }
    var contentsSum: Double { contents.reduce(0) { $0 + $1.kN } }
    var winter: Double { dead + snow + contentsSum }
    var onSoil: Double { winter + foundationSelf }
    var reserve: Double { capacity / max(load, 1e-6) }
}

enum Weights {
    static func make(_ p: Project, _ r: CalcResults) -> WeightReport {
        var w = WeightReport()
        let L = r.loads
        let A = L.floorArea
        let H = Double(p.floors) * p.floorHeight
        let ops = p.validOpenings
        let pitched = p.roofType != .flat

        // --- Стены ---
        var frameW = 0.0, facadeW = 0.0, fillW = 0.0, openA = 0.0
        for (i, ln) in L.lines.enumerated() where ln.isExterior {
            let ao = LoadCalc.openingArea(p, ln, ops)
            let wallA = ln.length * H + (i < L.fronton.count ? L.fronton[i] : 0) - ao
            frameW += ln.material.areaWeight(ln.thickness) * wallA
            facadeW += p.facade.weight * wallA
            openA += ao
        }
        fillW = 0.35 * openA
        var partW = 0.0
        for pt in p.partitions { partW += pt.material.areaWeight(pt.thickness) * pt.length * H }
        w.structure.append(WeightItem(name: "Каркас наружных стен и фронтонов", kN: frameW, note: "стойки, ОСП, утеплитель, ГКЛ, плёнки"))
        w.structure.append(WeightItem(name: "Фасад: \(p.facade.title.lowercased())", kN: facadeW, note: "\(Int(p.facade.weight * 100)) кг/м² с обрешёткой"))
        w.structure.append(WeightItem(name: "Окна и двери", kN: fillW, note: "\(fmt(openA, 1)) м² проёмов"))
        w.structure.append(WeightItem(name: "Внутренние стены и перегородки", kN: partW, note: "все этажи"))

        // --- Перекрытия и полы ---
        let inter = Double(max(p.floors - 1, 0)) * p.floorType.dead * A
        let attic = pitched ? p.floorType.dead * A : 0
        if inter > 0 { w.structure.append(WeightItem(name: "Межэтажные перекрытия", kN: inter, note: p.floorType.title)) }
        if attic > 0 { w.structure.append(WeightItem(name: "Чердачное перекрытие", kN: attic, note: p.floorType.title)) }
        let groundOnFoundation = p.selectedFoundation == .slab || p.groundFloor == .wood
        if groundOnFoundation {
            let g = p.selectedFoundation == .slab ? 1.0 : p.groundFloor.dead
            w.structure.append(WeightItem(name: "Пол 1-го этажа", kN: g * A,
                                          note: p.selectedFoundation == .slab ? "утеплитель, стяжка, покрытие на плите" : "балки по фундаменту"))
        }

        // --- Кровля и снег ---
        let roofPlan = pitched ? L.roofArea * cos(p.roofAngleEff * .pi / 180) : A
        w.structure.append(WeightItem(name: "Кровля: \(pitched ? p.covering.title.lowercased() : p.flatSlab.title.lowercased())", kN: L.roofDead * roofPlan,
                                      note: pitched ? "стропила, обрешётка\(p.roofInsulated ? ", утеплитель" : "")" : "балки, утеплитель, мембрана"))
        w.snow = L.snowS * roofPlan

        // --- Содержимое (оценка) ---
        w.contents = [
            WeightItem(name: "Мебель и бытовая техника", kN: 0.4 * A * Double(p.floors), note: "≈ 40 кг/м² пола"),
            WeightItem(name: "Люди (до 6 человек)", kN: 6 * 0.8, note: "≈ 80 кг на человека"),
            WeightItem(name: "Вода: отопление, бойлер, ванна", kN: 5.0, note: "≈ 0.5 т"),
        ]
        w.liveNorm = (1.5 * Double(p.floors) + (pitched ? 0.7 : 0)) * A

        // --- Фундамент: собственный вес и несущая способность ---
        // Несущая способность: во сколько раз k можно увеличить нагрузку от дома, пока не перестанет
        // выполняться первая проверка (давление на грунт, осадка, прочность). «Выдержит» = k × нагрузка.
        func pick(_ ks: [(Double, String)]) -> (Double, String) { ks.filter { $0.0.isFinite && $0.0 > 0 }.min { $0.0 < $1.0 } ?? (1, "") }
        switch p.selectedFoundation {
        case .strip:
            let s = r.strip
            w.foundationSelf = s.concrete * 25
            var ks: [(Double, String)] = []
            for sl in s.lines {
                guard let sec = s.section(sl.line), sl.load.char > 0 else { continue }
                let g = 25 * sec.area
                ks.append(((sl.R * sec.b - g) / sl.load.char, "давление под лентой \(sl.line.name): \(fmt(sl.p, 0)) из \(fmt(sl.R, 0)) кПа"))
            }
            let smax = s.lines.map(\.s).max() ?? 0
            if smax > 0 { ks.append((s.su / smax, "осадка \(fmt(smax * 100, 1)) из \(fmt(s.su * 100, 0)) см")) }
            w.load = zip(L.lines, L.stripLoads).reduce(0) { $0 + $1.1.char * $1.0.length }
            (w.localRatio, w.local) = { let k = pick(ks); return (1 / k.0, k.1) }()
            w.capacity = w.load / max(w.localRatio, 1e-6)
            w.basis = "Оценка по самой слабой проверке ленты: давление на грунт R (СП 22.13330, с учётом веса ленты) и осадка."
        case .slab:
            let s = r.slab
            w.foundationSelf = s.concrete * 25
            let g = 25 * s.t
            var ks: [(Double, String)] = [
                ((s.R - g) / max(s.pavg - g, 1e-6), "среднее давление \(fmt(s.pavg, 0)) из \(fmt(s.R, 0)) кПа"),
                ((1.2 * s.R - g) / max(s.plocal - g, 1e-6), "давление под стенами \(fmt(s.plocal, 0)) из \(fmt(1.2 * s.R, 0)) кПа"),
                (s.Qb / max(s.Qmax, 1e-6), "поперечная сила в плите \(fmt(s.Qmax, 0)) из \(fmt(s.Qb, 0)) кН/м"),
            ]
            if let asCalc = RC.As(M: s.Mmax, b: 1, h0: s.t - s.cover - 0.012, c: p.concrete, r: p.rebar), asCalc > 0 {
                ks.append((Bar.area(s.d) / s.step / asCalc, "изгиб плиты: арматура Ø\(s.d)/\(Int(s.step * 1000)) загружена на \(Int(asCalc / (Bar.area(s.d) / s.step) * 100)) %"))
            }
            if s.s > 0 { ks.append((s.su / s.s, "осадка \(fmt(s.s * 100, 1)) из \(fmt(s.su * 100, 0)) см")) }
            w.load = zip(L.lines, L.slabLoads).reduce(0) { $0 + $1.1.char * $1.0.length } + L.slabAreaChar * A
            (w.localRatio, w.local) = { let k = pick(ks); return (1 / k.0, k.1) }()
            w.capacity = w.load / max(w.localRatio, 1e-6)
            w.basis = "Оценка по самой слабой проверке плиты: давление на грунт (среднее и под стенами), изгиб и срез плиты, осадка (СП 22, СП 63)."
        case .piles:
            let s = r.piles
            let gW = s.grillageConcrete * 25
            w.foundationSelf = s.concrete * 25 + gW + (s.type == .screw ? Double(s.positions.count) * 0.5 : 0)
            w.load = zip(L.lines, L.stripLoads).reduce(0) { $0 + $1.1.design * $1.0.length }
            w.localRatio = s.Nmax / max(s.Nallow, 1e-6)
            w.local = "самая нагруженная свая: \(fmt(s.Nmax / 9.81, 2)) из \(fmt(s.Nallow / 9.81, 2)) т"
            w.capacity = w.load / max(w.localRatio, 1e-6)
            w.basis = "Оценка по самой нагруженной свае: допускаемая нагрузка Fd/γk (СП 24.13330), нагрузки расчётные — с коэффициентами надёжности."
        }
        return w
    }
}
