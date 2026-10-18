import Foundation

struct PileLine {
    let line: BearingLine
    let load: LineLoad
    let qd: Double
    let spacing: Double
    let n: Int
}

struct PileResult {
    var type: PileType = .bored
    var d = 0.3, D = 0.3, L = 2.5
    var Fd = 0.0, Nallow = 0.0, Nmax = 0.0
    var positions: [V2] = []
    var lines: [PileLine] = []
    var bg = 0.4, hg = 0.4, cover = 0.04
    var topN = 2, topD = 12, botN = 2, botD = 12
    var stirD = 8, stirStep = 0.2
    var M = 0.0, Q = 0.0, Qult = 0.0
    var heaving = false
    var heaveF = 0.0, holdF = 0.0, anchorF = 0.0
    var cageN = 4, cageD = 12
    var concrete = 0.0, grillageConcrete = 0.0, formwork = 0.0
    var rebar: [RebarItem] = []
    var checks: [Check] = []
    var notes: [String] = []
    var ok: Bool { !checks.isEmpty && checks.allSatisfy(\.ok) }
    var steel: Double { rebar.reduce(0) { $0 + $1.mass } }
}

enum PileCalc {
    // СП 24.13330.2021, табл. 7.10 — коэффициенты α1, α2 для винтовых свай
    static let phiT: [Double] = [13, 15, 16, 18, 20, 22, 24, 26, 28, 30, 32, 34]
    static let a1T: [Double] = [7.8, 8.4, 9.4, 10.1, 12.1, 15.0, 18.0, 23.1, 29.5, 38.0, 48.4, 64.9]
    static let a2T: [Double] = [2.8, 3.3, 3.8, 4.5, 5.5, 7.0, 9.2, 12.3, 16.5, 22.5, 31.0, 44.4]

    static func interp(_ x: Double, _ xs: [Double], _ ys: [Double]) -> Double {
        if x <= xs[0] { return ys[0] }
        for i in 1..<xs.count where x <= xs[i] {
            let t = (x - xs[i - 1]) / (xs[i] - xs[i - 1])
            return ys[i - 1] + t * (ys[i] - ys[i - 1])
        }
        return ys.last!
    }

    static func run(_ p: Project, _ Lr: LoadResult) -> PileResult {
        var r = PileResult()
        let soil = p.soil
        r.type = p.pileType
        r.d = p.pileDiameter
        r.D = p.pileType == .bored ? p.pileDiameter : max(p.pileEnlarge, p.pileDiameter)
        let dfn = soil.d0 * max(0, p.mt).squareRoot()
        r.heaving = soil.heave != .none
        r.L = p.pileLengthAuto ? max(2.0, roundUp(dfn + 0.5, 0.25)) : p.pileLength
        let lines = Lr.lines, loads = Lr.stripLoads
        guard !lines.isEmpty else { return r }
        let masonry = lines.contains { $0.material.isMasonry }

        // --- Несущая способность одиночной сваи ---
        let u = Double.pi * r.d
        let A = Double.pi * r.D * r.D / 4
        var tipPart = 0.0
        switch p.pileType {
        case .bored, .boredEnlarged:
            // СП 24.13330.2021 ф. (7.11): Fd = γc(γcR·R·A + u·Σγcf·fi·hi), γc = 1, γcR = 1, γcf = 0.7
            tipPart = soil.rTip * A
            let side = u * 0.7 * soil.fSide * max(0, r.L - (p.pileType == .boredEnlarged ? 0.3 : 0))
            r.Fd = tipPart + side
            r.anchorF = u * 0.7 * soil.fSide * max(0, r.L - dfn) + (p.pileType == .boredEnlarged ? 0.5 * soil.rTip * Double.pi * (r.D * r.D - r.d * r.d) / 4 : 0)
        case .screw:
            // СП 24.13330.2021 ф. (7.15): Fd = γc[(α1c + α2γh1)A + u·f·(h − D)], γc = 0.8 (сжатие)
            let a1 = interp(soil.phi, phiT, a1T), a2 = interp(soil.phi, phiT, a2T)
            tipPart = (a1 * soil.c + a2 * soil.gamma * r.L) * A
            r.Fd = 0.8 * (tipPart + u * soil.fSide * max(0, r.L - r.D))
            r.anchorF = 0.7 * tipPart
        }
        r.Nallow = r.Fd / 1.4    // γk = 1.4 (СП 24, п. 7.1.11)

        // --- Ростверк ---
        let maxT = lines.map(\.thickness).max() ?? 0.2
        r.bg = max(0.3, roundUp(maxT, 0.05))
        r.cover = 0.04
        let smax = masonry ? 2.0 : 3.0
        let smin = 3 * r.d
        func qd(_ i: Int, _ hg: Double) -> Double { loads[i].design + 1.1 * 25 * r.bg * hg }

        var hg = max(0.3, p.grillageH)
        var designed = false
        while hg <= 0.9 + 1e-9 {
            r.hg = hg
            r.lines = []
            for i in lines.indices {
                let q = qd(i, hg)
                let sReq = r.Nallow / q
                let s = min(sReq, smax)
                let n = max(1, Int((lines[i].length / max(s, 0.05) - 1e-9).rounded(.up)))
                r.lines.append(PileLine(line: lines[i], load: loads[i], qd: q, spacing: lines[i].length / Double(n), n: n))
            }
            let sMaxAct = r.lines.map(\.spacing).max() ?? 1
            let qMax = r.lines.map(\.qd).max() ?? 1
            r.M = qMax * sMaxAct * sMaxAct / 10
            r.Q = 0.6 * qMax * sMaxAct
            let h0 = hg - r.cover - 0.01
            let Rbt = p.concrete.Rbt * 1000
            if let As = RC.As(M: r.M, b: r.bg, h0: h0, c: p.concrete, r: p.rebar) {
                let need = max(As, 0.001 * r.bg * h0)
                let nMin = max(2, Int(((r.bg - 2 * r.cover) / 0.2 - 1e-9).rounded(.up)) + 1)
                var picked = false
                for dd in [12, 14, 16, 18, 20, 22, 25] {
                    let n = max(nMin, Int((need / Bar.area(dd) - 1e-9).rounded(.up)))
                    let clear = (r.bg - 2 * r.cover - Double(dd) / 1000) / Double(n - 1) - Double(dd) / 1000
                    if clear >= max(0.025, Double(dd) / 1000) { r.topN = n; r.botN = n; r.topD = dd; r.botD = dd; picked = true; break }
                }
                // Поперечная сила: Qb (c = 2h0) + Qsw, СП 63 п. 8.1.33
                let Qb = 0.75 * Rbt * r.bg * h0
                var shearOK = false
                for sd in [8, 10] {
                    for st in [roundDown(min(0.5 * h0, 0.3), 0.05), 0.15, 0.1] where st > 0 {
                        let qsw = rswA240 * 1000 * 2 * Bar.area(sd) / st
                        let Qu = min(Qb + 1.5 * qsw * h0, 0.3 * p.concrete.Rb * 1000 * r.bg * h0)
                        if r.Q <= Qu { r.stirD = sd; r.stirStep = st; r.Qult = Qu; shearOK = true; break }
                    }
                    if shearOK { break }
                }
                if picked && shearOK { designed = true; break }
            }
            hg += 0.1
        }
        if !designed { r.hg = min(hg, 0.9) }

        // Расстановка свай с объединением в узлах
        var pos: [V2] = []
        func add(_ v: V2) { if !pos.contains(where: { ($0 - v).len < 0.15 }) { pos.append(v) } }
        for pl in r.lines {
            for k in 0...pl.n { add(pl.line.a + (pl.line.b - pl.line.a) * (Double(k) / Double(pl.n))) }
        }
        r.positions = pos
        r.Nmax = r.lines.map { $0.qd * $0.spacing }.max() ?? 0

        // Морозное пучение: τfh·Afh − N ≤ Frf (СП 22.13330.2016 ф. (6.40), γc/γn ≈ 1)
        if r.heaving {
            r.heaveF = soil.heave.tauFh * u * min(dfn, r.L)
            let lightest = r.lines.min { $0.load.gk * $0.spacing < $1.load.gk * $1.spacing }
            r.holdF = 0.9 * ((lightest?.load.gk ?? 0) + 25 * r.bg * r.hg) * (lightest?.spacing ?? 1)
        }

        // --- Объёмы ---
        let nP = pos.count
        let totalLen = lines.reduce(0) { $0 + $1.length }
        r.grillageConcrete = totalLen * r.bg * r.hg
        r.formwork = totalLen * (2 * r.hg + r.bg)
        let cls = p.rebar.rawValue
        let lap = RC.lap(d: r.botD, c: p.concrete, r: p.rebar)
        r.rebar.append(RebarItem(name: "Ростверк: продольная нижняя", d: r.botD, cls: cls, spec: "\(r.botN) шт. в сечении", length: totalLen * Double(r.botN) * (1 + lap / 11.7)))
        r.rebar.append(RebarItem(name: "Ростверк: продольная верхняя", d: r.topD, cls: cls, spec: "\(r.topN) шт. в сечении", length: totalLen * Double(r.topN) * (1 + lap / 11.7)))
        let nSt = r.lines.reduce(0) { $0 + Int(($1.line.length / r.stirStep).rounded(.up)) + 1 }
        r.rebar.append(RebarItem(name: "Ростверк: хомуты", d: r.stirD, cls: "А240", spec: "шаг \(Int(r.stirStep * 1000)) мм, \(nSt) шт.", length: Double(nSt) * (2 * (r.bg + r.hg - 4 * r.cover) + 0.2)))
        let corners = p.rings.reduce(0) { $0 + $1.count } + 2 * lines.filter { !$0.isExterior }.count
        r.rebar.append(RebarItem(name: "Ростверк: угловые Г-образные", d: r.botD, cls: cls, spec: "\(corners) узл.", length: Double(corners * (r.topN + r.botN)) * 2 * lap))
        switch p.pileType {
        case .bored, .boredEnlarged:
            r.cageN = r.d <= 0.25 ? 3 : 4
            r.cageD = 12
            let bell = p.pileType == .boredEnlarged ? Double.pi * r.D * r.D / 4 * 0.3 * 0.6 : 0
            r.concrete = Double(nP) * (Double.pi * r.d * r.d / 4 * r.L + bell)
            r.rebar.append(RebarItem(name: "Сваи: продольные стержни каркаса", d: r.cageD, cls: cls, spec: "\(r.cageN) шт. × \(nP) свай, выпуск в ростверк 300", length: Double(nP * r.cageN) * (r.L + 0.3)))
            let nCl = Int((r.L / 0.4).rounded(.up)) + 1
            r.rebar.append(RebarItem(name: "Сваи: хомуты каркаса", d: 6, cls: "А240", spec: "шаг 400, \(nCl * nP) шт.", length: Double(nCl * nP) * Double.pi * (r.d - 0.1)))
        case .screw:
            r.concrete = 0
            r.notes.append("Винтовые сваи: ствол Ø\(Int(r.d * 1000)) мм, лопасть Ø\(Int(r.D * 1000)) мм, длина \(fmt(r.L)) м — \(nP) шт. Полость ствола заполнить бетоном/ЦПР, оголовки 250×250×6.")
        }

        // --- Проверки ---
        r.checks.append(Check(title: "Нагрузка на сваю", value: "N = \(fmt(r.Nmax, 1)) кН ≤ Fd/γk = \(fmt(r.Fd, 1))/1.4 = \(fmt(r.Nallow, 1)) кН",
                              ok: r.Nmax <= r.Nallow * 1.0001, ref: p.pileType == .screw ? "СП 24.13330.2021, ф. (7.15), п. 7.1.11" : "СП 24.13330.2021, ф. (7.11), п. 7.1.11"))
        let sMin = r.lines.map(\.spacing).min() ?? 1
        r.checks.append(Check(title: "Шаг свай", value: "\(fmt(sMin)) … \(fmt(r.lines.map(\.spacing).max() ?? 0)) м; ≥ 3d = \(fmt(smin)) м; ≤ \(fmt(smax, 1)) м",
                              ok: sMin >= smin - 1e-6, ref: "СП 24.13330.2021, п. 8.13"))
        r.checks.append(Check(title: "Ростверк \(Int(r.bg * 1000))×\(Int(r.hg * 1000)) мм: изгиб", value: "M = q·l²/10 = \(fmt(r.M, 1)) кН·м; \(r.botN)Ø\(r.botD) низ + \(r.topN)Ø\(r.topD) верх",
                              ok: designed, ref: "СП 63.13330.2018, п. 8.1.8"))
        r.checks.append(Check(title: "Ростверк: поперечная сила", value: "Q = \(fmt(r.Q, 1)) кН ≤ Qb + Qsw = \(fmt(r.Qult, 1)) кН; хомуты Ø\(r.stirD) шаг \(Int(r.stirStep * 1000))",
                              ok: designed && r.Q <= r.Qult, ref: "СП 63.13330.2018, п. 8.1.31–8.1.33"))
        if r.heaving {
            r.checks.append(Check(title: "Устойчивость на морозное пучение", value: "τfh·Afh − N = \(fmt(r.heaveF, 1)) − \(fmt(r.holdF, 1)) = \(fmt(r.heaveF - r.holdF, 1)) кН ≤ Frf = \(fmt(r.anchorF, 1)) кН",
                                  ok: r.heaveF - r.holdF <= r.anchorF, ref: "СП 22.13330.2016, п. 6.8.9, ф. (6.40)"))
            r.checks.append(Check(title: "Длина сваи ниже промерзания", value: "L = \(fmt(r.L)) м ≥ dfn + 0.5 = \(fmt(dfn + 0.5)) м",
                                  ok: r.L >= dfn + 0.5 - 1e-6, ref: "СП 24.13330.2021, разд. 7.4"))
        }

        r.notes.append("Ростверк — монолитный, с зазором 100–150 мм от грунта (висячий) на пучинистых грунтах; под ростверк — пенополистирол/песок как демпфер.")
        if masonry {
            r.notes.append("Под кладкой из газобетона/кирпича шаг свай ограничен \(fmt(smax, 1)) м, ростверк — только монолитный ж/б (не металл/дерево).")
        }
        if r.heaving && r.heaveF - r.holdF > r.anchorF {
            r.notes.append("Не обеспечена анкеровка от пучения: увеличьте длину сваи, используйте уширение (ТИСЭ) или обмазку ствола в зоне промерзания (снижает τfh).")
        }
        r.notes.append("Несущая способность свай определена по табличным характеристикам; по СП 24 для ответственных объектов её подтверждают статическими испытаниями.")
        return r
    }
}
