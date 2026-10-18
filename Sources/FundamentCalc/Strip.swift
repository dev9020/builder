import Foundation

struct Check: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let ok: Bool
    let ref: String
}

struct RebarItem: Identifiable {
    let id = UUID()
    let name: String
    let d: Int
    let cls: String
    let spec: String
    let length: Double
    var mass: Double { length * Bar.mass(d) }
}

struct StripSection {
    var b: Double, H: Double, isT: Bool, soleH: Double, stemW: Double, cover: Double
    var topN = 2, topD = 12, botN = 2, botD = 12
    var sideRows = 0, sideD = 10
    var clampD = 6, clampStep = 0.3
    var soleD = 0, soleStep = 0.0
    var area: Double { isT ? b * soleH + stemW * (H - soleH) : b * H }
    var mu: Double { (Double(topN) * Bar.area(topD) + Double(botN) * Bar.area(botD)) / area }
}

struct StripLine {
    let line: BearingLine
    let load: LineLoad
    let bReq: Double
    let b: Double
    let p: Double
    let R: Double
    let s: Double
}

struct StripResult {
    var dfn = 0.0, df = 0.0, depth = 0.0, H = 0.0, cushion = 0.2
    var ext: StripSection?
    var int: StripSection?
    var lines: [StripLine] = []
    var lap = 0.0
    var concrete = 0.0, formwork = 0.0, sand = 0.0, prep = 0.0, eps = 0.0
    var rebar: [RebarItem] = []
    var checks: [Check] = []
    var notes: [String] = []
    var su = 0.10
    var ok: Bool { !checks.isEmpty && checks.allSatisfy(\.ok) }
    var steel: Double { rebar.reduce(0) { $0 + $1.mass } }
    func section(_ l: BearingLine) -> StripSection? { l.isExterior ? ext : (int ?? ext) }
}

enum StripCalc {
    static func run(_ p: Project, _ L: LoadResult) -> StripResult {
        var r = StripResult()
        let soil = p.soil
        r.dfn = soil.d0 * max(0, p.mt).squareRoot()
        r.df = (p.heated ? 0.7 : 1.1) * r.dfn
        let heaving = soil.heave != .none
        if p.stripKind == .deep {
            r.depth = heaving ? max(0.5, roundUp(r.df, 0.05)) : 0.5
        } else {
            r.depth = max(0.3, p.shallowDepth)
        }
        let d = r.depth
        r.H = d + p.plinth
        let H = r.H
        let cover = p.concretePrep ? 0.04 : 0.07
        let lines = L.lines, loads = L.stripLoads
        guard !lines.isEmpty else { return r }
        let masonry = lines.contains { $0.material.isMasonry }
        r.su = masonry ? 0.10 : 0.15

        func R(_ b: Double) -> Double { Soil.R(soil, b: b, d: d, gwl: p.gwl) }
        func minB(_ idx: [Int]) -> Double {
            let t = idx.map { lines[$0].thickness }.max() ?? 0.2
            return max(0.3, roundUp(t, 0.05))
        }
        func weight(_ s: StripSection) -> Double {
            25 * s.area + (s.isT ? soil.gamma * (s.b - s.stemW) * max(0, d - s.soleH) : 0)
        }
        func reqB(_ q: LineLoad, _ mb: Double) -> Double {
            var b = mb
            while b < 3.0 {
                let isT = b > 0.6 + 1e-9
                let s = StripSection(b: b, H: H, isT: isT, soleH: isT ? min(0.3, H - 0.1) : H, stemW: isT ? mb : b, cover: cover)
                if (q.char + weight(s)) / b <= R(b) { return b }
                b += 0.05
            }
            return 3.0
        }

        let extIdx = lines.indices.filter { lines[$0].isExterior }
        let intIdx = lines.indices.filter { !lines[$0].isExterior }
        var breq = [Double](repeating: 0, count: lines.count)
        for (idx, isExt) in [(extIdx, true), (intIdx, false)] where !idx.isEmpty {
            let mb = minB(idx)
            for i in idx { breq[i] = reqB(loads[i], mb) }
            let b = roundUp(idx.map { breq[$0] }.max()!, 0.05)
            let qd = idx.map { loads[$0].design }.max()!
            let sec = section(b: b, minB: mb, qd: qd, H: H, cover: cover, p: p)
            if isExt { r.ext = sec } else { r.int = sec }
        }

        for i in lines.indices {
            guard let sec = r.section(lines[i]) else { continue }
            let w = weight(sec)
            let pr = (loads[i].char + w) / sec.b
            let pl = (loads[i].longTerm + w) / sec.b
            let s = Soil.settlement(p: pl, d: d, b: sec.b, l: 30 * sec.b, soil: soil).s
            r.lines.append(StripLine(line: lines[i], load: loads[i], bReq: breq[i], b: sec.b, p: pr, R: R(sec.b), s: s))
        }

        // --- Объёмы и спецификация ---
        r.cushion = (p.stripKind == .shallow && heaving) ? 0.4 : 0.2
        let cornersExt = p.rings.reduce(0) { $0 + $1.count }
        let cls = p.rebar.rawValue
        var maxLap = 0.0
        for (isExt, sec0) in [(true, r.ext), (false, r.int)] {
            guard let sec = sec0 else { continue }
            let grp = r.lines.filter { $0.line.isExterior == isExt }
            guard !grp.isEmpty else { continue }
            let len = grp.reduce(0) { $0 + $1.line.length }
            let g = isExt ? "Наружная лента" : "Лента под несущими стенами"
            r.concrete += len * sec.area
            r.formwork += len * 2 * H
            r.sand += len * (sec.b + 0.4) * r.cushion
            if p.concretePrep { r.prep += len * (sec.b + 0.2) * 0.05 }
            let lap = RC.lap(d: max(sec.botD, sec.topD), c: p.concrete, r: p.rebar)
            maxLap = max(maxLap, lap)
            let lapF = 1 + lap / 11.7
            r.rebar.append(RebarItem(name: "\(g): продольная нижняя", d: sec.botD, cls: cls, spec: "\(sec.botN) шт. в сечении", length: len * Double(sec.botN) * lapF))
            r.rebar.append(RebarItem(name: "\(g): продольная верхняя", d: sec.topD, cls: cls, spec: "\(sec.topN) шт. в сечении", length: len * Double(sec.topN) * lapF))
            if sec.sideRows > 0 {
                r.rebar.append(RebarItem(name: "\(g): боковая конструктивная", d: sec.sideD, cls: cls, spec: "\(sec.sideRows * 2) шт., шаг по высоте ≤ 400", length: len * Double(sec.sideRows * 2) * lapF))
            }
            let nCl = grp.reduce(0) { $0 + Int(($1.line.length / sec.clampStep).rounded(.up)) + 1 }
            let perim = 2 * ((sec.stemW - 2 * cover) + (H - 2 * cover)) + 0.2
            r.rebar.append(RebarItem(name: "\(g): хомуты", d: sec.clampD, cls: "А240", spec: "шаг \(Int(sec.clampStep * 1000)) мм, \(nCl) шт.", length: Double(nCl) * perim))
            if sec.isT && sec.soleD > 0 {
                let nS = grp.reduce(0) { $0 + Int(($1.line.length / sec.soleStep).rounded(.up)) + 1 }
                r.rebar.append(RebarItem(name: "\(g): поперечная подошвы", d: sec.soleD, cls: cls, spec: "шаг \(Int(sec.soleStep * 1000)) мм, \(nS) шт.", length: Double(nS) * (sec.b - 2 * cover)))
            }
            let corners = isExt ? cornersExt : grp.count * 2
            r.rebar.append(RebarItem(name: "\(g): угловые Г-образные", d: max(sec.botD, sec.topD), cls: cls, spec: "\(corners) узл. × \(sec.topN + sec.botN) шт., полки по \(Int(lap * 1000)) мм", length: Double(corners * (sec.topN + sec.botN)) * 2 * lap))
        }
        r.lap = maxLap
        if p.stripKind == .shallow {
            let per = p.rings.reduce(0) { $0 + Geo.perimeter($1) }
            r.eps = per * (p.plinth + d + 1.2)
        }

        // --- Проверки ---
        for (isExt, sec0) in [(true, r.ext), (false, r.int)] {
            guard let sec = sec0 else { continue }
            let grp = r.lines.filter { $0.line.isExterior == isExt }
            guard let worst = grp.max(by: { $0.p / $0.R < $1.p / $1.R }) else { continue }
            let g = isExt ? "наружная лента" : "внутренняя лента"
            r.checks.append(Check(title: "Давление под подошвой (\(g), b = \(Int(sec.b * 1000)) мм)",
                                  value: "p = \(fmt(worst.p, 1)) кПа ≤ R = \(fmt(worst.R, 1)) кПа (участок \(worst.line.name))",
                                  ok: worst.p <= worst.R * 1.0001, ref: "СП 22.13330.2016, ф. (5.7), п. 5.6.26"))
        }
        let smax = r.lines.map(\.s).max() ?? 0, smin = r.lines.map(\.s).min() ?? 0
        r.checks.append(Check(title: "Осадка основания", value: "s = \(fmt(smax * 100, 1)) см ≤ su = \(fmt(r.su * 100, 0)) см",
                              ok: smax <= r.su, ref: "СП 22.13330.2016, п. 5.6.31, прил. Г"))
        if p.stripKind == .deep {
            if heaving {
                r.checks.append(Check(title: "Глубина заложения (пучинистый грунт)", value: "d = \(fmt(d)) м ≥ df = kh·dfn = \(fmt(r.df)) м",
                                      ok: d >= r.df - 1e-6, ref: "СП 22.13330.2016, п. 5.5.3–5.5.4, табл. 5.3, 5.4"))
            } else {
                r.checks.append(Check(title: "Глубина заложения (непучинистый грунт)", value: "d = \(fmt(d)) м — не зависит от промерзания, ≥ 0.5 м",
                                      ok: true, ref: "СП 22.13330.2016, табл. 5.4"))
            }
        } else {
            let okShallow = !(heaving && soil.heave == .strong && masonry)
            r.checks.append(Check(title: "МЗЛФ: условия применения", value: heaving
                                  ? "песчаная подушка \(Int(r.cushion * 1000)) мм + утепление ЭППС по периметру; \(okShallow ? "допустимо" : "кладка на сильнопучинистом грунте — нужен расчёт деформаций пучения")"
                                  : "грунт непучинистый — допустимо",
                                  ok: okShallow, ref: "СП 22.13330.2016, п. 6.8.10–6.8.12"))
        }
        for (isExt, sec0) in [(true, r.ext), (false, r.int)] {
            guard let sec = sec0 else { continue }
            r.checks.append(Check(title: "Продольное армирование (\(isExt ? "наружная" : "внутренняя"))",
                                  value: "μ = \(fmt(sec.mu * 100, 3)) % ≥ 0.1 %, Ø ≥ 12 при длине стороны > 3 м",
                                  ok: sec.mu >= 0.001 - 1e-9, ref: "СП 63.13330.2018, п. 10.3.6, 10.3.8"))
            if sec.isT {
                r.checks.append(Check(title: "Консоль подошвы: изгиб и поперечная сила", value: sec.soleD > 0
                                      ? "h подошвы = \(Int(sec.soleH * 1000)) мм, Ø\(sec.soleD) шаг \(Int(sec.soleStep * 1000))"
                                      : "не удалось подобрать — увеличьте высоту подошвы",
                                      ok: sec.soleD > 0, ref: "СП 63.13330.2018, п. 8.1.8, 8.1.33"))
            }
        }

        // --- Рекомендации ---
        if masonry {
            r.notes.append("Под кладкой из газобетона/кирпича: горизонтальная гидроизоляция (2 слоя наплавляемой) по верху ленты, армирование первого ряда и монолитный армопояс под перекрытием/мауэрлатом.")
        }
        if lines.contains(where: { !$0.material.isMasonry }) && masonry {
            r.notes.append("Смешанные стены (каркас + кладка) дают разную нагрузку: лента рассчитана по наиболее нагруженному участку и выполняется непрерывной, жёстко связанной — это выравнивает осадки (разность по расчёту \(fmt((smax - smin) * 100, 1)) см).")
        }
        if p.groundFloor != .onGround {
            r.notes.append("Деревянное/сборное перекрытие над техподпольем: устройте продухи в цоколе (≈ 1/400 площади пола) и пароизоляцию грунта.")
        }
        if p.gwl < d + 0.5 {
            r.notes.append("УГВ (\(fmt(p.gwl)) м) близко к подошве: нужны обмазочная + оклеечная гидроизоляция и пристенный дренаж; при УГВ < df + 2 м грунт следует считать пучинистым.")
        }
        if heaving {
            r.notes.append("Пучинистый грунт: обратная засыпка пазух — непучинистым песком, утеплённая отмостка ≥ 1.0–1.2 м, не оставлять фундамент на зиму без нагрузки.")
        }
        r.notes.append("Подготовка: песчаная подушка \(Int(r.cushion * 1000)) мм с послойным уплотнением\(p.concretePrep ? ", бетонная подготовка 50 мм" : ""). Защитный слой бетона \(Int(cover * 1000)) мм.")
        return r
    }

    static func section(b: Double, minB: Double, qd: Double, H: Double, cover: Double, p: Project) -> StripSection {
        let isT = b > 0.6 + 1e-9
        let stem = isT ? minB : b
        var sec = StripSection(b: b, H: H, isT: isT, soleH: isT ? min(0.3, H - 0.1) : H, stemW: stem, cover: cover)
        if isT {
            let pd = qd / b
            let c = (b - stem) / 2
            var hh = 0.3
            search: while hh <= min(H - 0.1, 0.8) + 1e-9 {
                let h0 = hh - cover - 0.007
                let M = pd * c * c / 2
                let Q = max(0, pd * (c - h0))
                if Q <= 1.5 * p.concrete.Rbt * 1000 * h0, let As = RC.As(M: M, b: 1, h0: h0, c: p.concrete, r: p.rebar) {
                    let need = max(As, 0.001 * h0)
                    for dd in [10, 12, 14, 16] {
                        for st in [0.2, 0.15] where Bar.area(dd) / st >= need {
                            sec.soleD = dd; sec.soleStep = st
                            break search
                        }
                    }
                }
                hh += 0.05
            }
            sec.soleH = min(hh, H - 0.1)
        }
        let asLayer = 0.0005 * sec.area
        func layer(_ w: Double) -> (Int, Int) {
            for dd in [12, 14, 16, 18, 20, 22, 25] {
                let nMin = max(2, Int(((w - 2 * cover) / 0.4 - 1e-9).rounded(.up)) + 1)
                let n = max(nMin, Int((asLayer / Bar.area(dd) - 1e-9).rounded(.up)))
                let dm = Double(dd) / 1000
                let clear = (w - 2 * cover - dm) / Double(n - 1) - dm
                if clear >= max(0.025, dm) { return (n, dd) }
            }
            return (4, 25)
        }
        (sec.botN, sec.botD) = layer(b)
        (sec.topN, sec.topD) = layer(stem)
        if H > 0.7 { sec.sideRows = max(1, Int(((H - 2 * cover) / 0.4 - 1e-9).rounded(.up)) - 1) }
        let dmax = max(sec.botD, sec.topD)
        sec.clampD = (H > 0.8 || dmax >= 20) ? 8 : 6
        let h0 = H - cover - Double(sec.botD) / 2000
        sec.clampStep = min(0.3, roundDown(0.75 * h0, 0.05))
        return sec
    }
}
