import Foundation

// Защита дома от ветра, влаги и огня: расчёты и этапы, без которых каркасный дом гниёт
// или эксплуатируется неправильно (ветер, пар, вентиляция, ендовы, подготовка древесины, мокрые зоны).

// MARK: - Исходные данные

/// Ветровой район (СП 20.13330.2016, табл. 11.1)
enum WindRegion: Int, CaseIterable, Identifiable {
    case ia = 0, r1, r2, r3, r4, r5, r6, r7
    var id: Int { rawValue }
    /// Нормативное значение ветрового давления w0, кПа
    var w0: Double { [0.17, 0.23, 0.30, 0.38, 0.48, 0.60, 0.73, 0.85][rawValue] }
    var roman: String { ["Iа", "I", "II", "III", "IV", "V", "VI", "VII"][rawValue] }
    var title: String { "\(roman) — \(fmt(w0, 2)) кПа" }
}

/// Источник тепла: от него зависят дымоход, приток в котельную и разделки
enum HeatSource: String, CaseIterable, Identifiable {
    case electric, heatPump, gas, solid
    var id: String { rawValue }
    var title: String {
        switch self {
        case .electric: return "Электрокотёл / электроконвекторы"
        case .heatPump: return "Тепловой насос"
        case .gas: return "Газовый котёл"
        case .solid: return "Твердотопливный котёл"
        }
    }
    var needsFlue: Bool { self == .gas || self == .solid }
}

// MARK: - Ветер

/// Ветровая нагрузка на лёгкий каркасный дом (СП 20.13330.2016, разд. 11, прил. В)
struct WindCheck {
    var region = WindRegion.r1
    var height = 0.0            // ze — высота конька, м
    var k = 0.5, zeta = 1.22
    var w = 0.0                 // нормативное давление с пульсацией, кПа
    var cUp = 0.0               // аэродинамический коэффициент отрыва ската (среднее по скату)
    var upRafter = 0.0          // расчётный отрыв опорного узла одной стропильной ноги (за вычетом 0.9 веса), кН
    var strapEvery = true       // ветровая скоба на каждую ногу
    var nodeCap = 4.0           // несущая способность 2 уголков 90×90×65 на отрыв, кН
    var shearX = 0.0, shearY = 0.0          // расчётная горизонтальная сила ветра на дом, кН
    var anchorsX = 0, anchorsY = 0          // анкеры на стенах, параллельных ветру
    var anchorT = 0.0                       // несущая способность анкера М12 на сдвиг (нагель), кН
    var anchorsNeed = 0                     // сколько анкеров нужно всего по сдвигу
    var upAnchor = 0.0                      // отрыв на 1 анкер карнизной стены, кН
    var washerCap = 3.8                     // смятие древесины под шайбой DIN 9021, кН
    var ok: Bool { upRafter <= nodeCap * 1.75 && anchorsNeed <= anchorsX + anchorsY && upAnchor <= washerCap }

    static func make(_ p: Project, _ r: CalcResults, _ F: Framing) -> WindCheck {
        var c = WindCheck()
        c.region = p.windRegion
        let tanA = p.roofType == .flat ? 0 : tan(p.roofAngleEff * .pi / 180)
        let rise = p.roofType == .flat ? 0.3 : tanA * max(F.rafterRun, 0.5)
        c.height = max(F.wallTop + rise, 3)
        // тип местности B (пригород, посёлок): k(ze) и ζ(ze), табл. 11.2 и 11.4
        func interp(_ z: Double, _ t: [(Double, Double)]) -> Double {
            if z <= t[0].0 { return t[0].1 }
            for i in 1..<t.count where z <= t[i].0 {
                let (z0, v0) = t[i - 1], (z1, v1) = t[i]
                return v0 + (v1 - v0) * (z - z0) / (z1 - z0)
            }
            return t.last!.1
        }
        c.k = interp(c.height, [(5, 0.5), (10, 0.65), (20, 0.85)])
        c.zeta = interp(c.height, [(5, 1.22), (10, 1.06), (20, 0.92)])
        let nu = 0.85
        c.w = c.region.w0 * c.k * (1 + c.zeta * nu)
        let gf = 1.4
        // отрыв ската: усреднённые коэффициенты по прил. В.1.2 (зоны F–J), на свесе добавляется подпор снизу +0.8
        let a = p.roofType == .flat ? 0 : p.roofAngleEff
        c.cUp = interp(a, [(0, -1.0), (5, -0.9), (15, -0.6), (30, -0.45), (45, -0.3)])
        let step = F.rafter?.step ?? p.studStep
        let run = p.roofType == .flat ? (F.attic?.maxSpan ?? 4) / 2 : max(F.rafterRun, 0.5)
        let ov = p.overhang
        let up = gf * c.w * step * (run * -c.cUp + ov * (-c.cUp + 0.8))
        let dead = 0.9 * r.loads.roofDead * step * (run + ov)
        c.upRafter = max(0, up - dead)
        c.strapEvery = c.upRafter > c.nodeCap * 0.5
        // горизонтальная сила: наветренная + подветренная стороны (ce = 0.8 + 0.5)
        let (lo, hi) = Geo.bbox(p.rings)
        let Lx = hi.x - lo.x, Ly = hi.y - lo.y
        let Hw = F.wallTop - F.levelBase
        let alongX = (F.ridgeLines.first.map { abs($0.1.x - $0.0.x) > abs($0.1.y - $0.0.y) }) ?? (Lx >= Ly)
        // ветер вдоль X давит на стены длиной Ly: фронтон (½·Ly·rise), если конёк вдоль X, иначе скат (Ly·rise)
        let aX = Ly * Hw + Ly * rise * (alongX ? 0.5 : 1.0)
        let aY = Lx * Hw + Lx * rise * (alongX ? 1.0 : 0.5)
        c.shearX = gf * c.w * 1.3 * aX
        c.shearY = gf * c.w * 1.3 * aY
        // анкер — стальной нагель Ø1.2 см в обвязке толщиной a (СП 64.13330, табл. 20): T = 2.5d² + 0.01a² ≤ 4d²
        let d = 1.2, aCm = (p.selectedFoundation == .slab ? F.studExt.tm : F.sillSec.tm) * 100
        c.anchorT = min(2.5 * d * d + 0.01 * aCm * aCm, 4 * d * d)
        for an in F.anchors {
            guard let ln = F.sillLines.min(by: { Geo.distToSegment(an, $0.0, $0.1) < Geo.distToSegment(an, $1.0, $1.1) }) else { continue }
            if abs(ln.1.x - ln.0.x) >= abs(ln.1.y - ln.0.y) { c.anchorsX += 1 } else { c.anchorsY += 1 }
        }
        let needX = Int((c.shearX / c.anchorT).rounded(.up)), needY = Int((c.shearY / c.anchorT).rounded(.up))
        c.anchorsNeed = max(needX, c.anchorsX) + max(needY, c.anchorsY)
        // отрыв карнизной стены: отрыв кровли на 1 м минус 0.9 × (стена + перекрытия + кровля) на 1 м
        var worst = 0.0
        for (i, ln) in r.loads.lines.enumerated() where ln.isExterior && i < r.loads.stripLoads.count {
            let s = r.loads.stripLoads[i]
            guard s.roof > 0 else { continue }
            let upM = up / step - 0.9 * (s.wall + s.floors + s.roof)
            worst = max(worst, upM)
        }
        c.upAnchor = max(0, worst) * 2.0
        return c
    }

    var decisions: [Decision] {
        [Decision(title: "Ветер", value: "район \(region.roman): w0 = \(fmt(region.w0, 2)) кПа, w = \(fmt(w, 2)) кПа на высоте \(fmt(height, 1)) м",
                  why: "тип местности B, k = \(fmt(k, 2)), пульсация ζ = \(fmt(zeta, 2)), ν = 0.85; γf = 1.4", ref: N.sp20.at("разд. 11, табл. 11.1, 11.2, 11.4"))]
    }
    var rafterDecision: Decision {
        Decision(title: "Отрыв стропила ветром", value: upRafter <= 0.01 ? "нет — вес кровли больше отсоса" : "\(fmt(upRafter, 1)) кН на опорный узел",
                 why: "отсос на скате c = \(fmt(cUp, 2)), на свесе ещё +0.8 подпор снизу; 2 уголка 90×90×65 держат ≈ \(fmt(nodeCap, 0)) кН, перфолента/скоба к стойке — ещё ≈ 3 кН → "
                     + (upRafter > nodeCap * 1.75 ? "⚠︎ НЕ ХВАТАЕТ: скоба на каждую ногу + шпилька М12 через стропило и стойку (стяжной узел)" : strapEvery ? "ветровая скоба на КАЖДУЮ ногу" : "скоба на каждую 2-ю ногу достаточно"),
                 ref: "\(N.sp20.at("прил. В.1.2")), \(N.sp64.at("разд. 8 «Соединения»"))")
    }
    var anchorDecision: Decision {
        let have = anchorsX + anchorsY
        return Decision(title: "Анкеры на ветер", value: anchorsNeed > have ? "⚠︎ нужно \(anchorsNeed) шт. (сейчас \(have)) — уменьшить шаг" : "\(have) шт. достаточно",
                        why: "сдвиг: \(fmt(max(shearX, shearY), 1)) кН на дом, 1 анкер М12 (нагель в обвязке) ≈ \(fmt(anchorT, 1)) кН; отрыв на анкер \(fmt(upAnchor, 1)) кН ≤ \(fmt(washerCap, 1)) кН (смятие под шайбой DIN 9021)"
                            + (upAnchor > washerCap ? " — ⚠︎ поставить пластину 50×50×5 вместо шайбы" : ""),
                        ref: "\(N.sp20.at("разд. 11")), \(N.sp64.at("п. 8.2, табл. 20"))")
    }
}

// MARK: - Паропроницаемость слоёв

/// Упрощённая проверка влагонакопления: сопротивление паропроницанию слоёв ВНУТРИ утеплителя
/// должно быть не менее чем в 5 раз больше, чем СНАРУЖИ до вентзазора (Sd — эквивалентная толщина воздуха, м)
struct VaporCheck {
    struct Layer { let name: String; let sd: Double; let inside: Bool }
    var title = ""
    var layers: [Layer] = []
    var sdIn: Double { layers.filter(\.inside).reduce(0) { $0 + $1.sd } }
    var sdOut: Double { layers.filter { !$0.inside }.reduce(0) { $0 + $1.sd } }
    var ratio: Double { sdIn / max(sdOut, 0.01) }
    var ok: Bool { ratio >= 5 }
    /// Требуемая Sd пароизоляции, м
    var barrierSd: Double { max(20, (5 * sdOut).rounded(.up)) }

    static let barrier = 20.0     // плёнка пароизоляционная класса «В» / ПЭ 200 мкм — Sd ≥ 20 м

    static func wall(_ p: Project, _ woolWall: Double) -> VaporCheck {
        var v = VaporCheck(title: "Наружная стена")
        switch p.interiorFinish {
        case .gkl: v.layers.append(Layer(name: "ГКЛ 12.5", sd: 0.12, inside: true))
        case .osb: v.layers.append(Layer(name: "ОСП-3 12 изнутри", sd: 3.0, inside: true))
        default: break     // вагонка/доска — с зазорами, пару не держит
        }
        v.layers.append(Layer(name: "пароизоляция", sd: barrier, inside: true))
        v.layers.append(Layer(name: "минвата \(Int(woolWall * 1000))", sd: woolWall, inside: true))
        if p.sheathing.hasOSB { v.layers.append(Layer(name: "ОСП-3 9 снаружи", sd: 1.8, inside: false)) }
        if p.facade != .plaster { v.layers.append(Layer(name: "ветрозащитная мембрана", sd: 0.02, inside: false)) }
        if p.facade == .plaster {
            v.layers.append(Layer(name: "фасадная минвата 100", sd: 0.1, inside: false))
            v.layers.append(Layer(name: "минеральная штукатурка 8 мм", sd: 0.25, inside: false))
        }
        return v
    }

    static func roof(_ p: Project, _ woolRoof: Double) -> VaporCheck {
        var v = VaporCheck(title: p.roofInsulated ? "Мансардная кровля" : "Чердачное перекрытие")
        v.layers = [Layer(name: "ГКЛ / вагонка потолка", sd: 0.12, inside: true),
                    Layer(name: "пароизоляция", sd: barrier, inside: true),
                    Layer(name: "минвата \(Int(woolRoof * 1000))", sd: woolRoof, inside: true),
                    Layer(name: "супердиффузионная мембрана", sd: 0.02, inside: false)]
        return v
    }

    var decision: Decision {
        Decision(title: "Пар: \(title.lowercased())", value: ok ? "Sd до наружной грани утеплителя \(fmt(sdIn, 1)) м : снаружи \(fmt(sdOut, 2)) м = \(Int(ratio)) : 1 ✓" : "⚠︎ \(fmt(ratio, 1)) : 1 < 5 : 1 — риск конденсата",
                 why: "слои внутри утеплителя должны быть в ≥ 5 раз плотнее для пара, чем снаружи; пароизоляция — Sd ≥ \(Int(barrierSd)) м (плёнка класса В или ПЭ 200 мкм), не «пароизоляция» Sd 2–5 м. Слои: "
                     + layers.map { "\($0.name) \(fmt($0.sd, 2))" }.joined(separator: ", "),
                 ref: N.sp50.at("разд. 8 «Защита от переувлажнения ограждающих конструкций»"))
    }
}

// MARK: - Вентиляция

struct VentRow {
    let room: String
    let area: Double
    let supply: Double
    let exhaust: Double
    let device: String
}

struct VentPlan {
    var rows: [VentRow] = []
    var supply = 0.0, exhaust = 0.0
    var ducts: [(room: String, d: Int, flow: Double, n: Int)] = []
    var channels: Int { ducts.reduce(0) { $0 + $1.n } }
    var valves = 0
    var undercut: [String] = []

    static func make(_ p: Project, _ L: HouseLayout) -> VentPlan {
        var v = VentPlan()
        let h = max(p.floorHeight - 0.3, 2.5)
        // естественный канал: скорость ≤ 1 м/с → Ø125 ≈ 44 м³/ч, Ø160 ≈ 72 м³/ч; больше — несколько каналов
        func duct(_ room: String, _ flow: Double) -> (room: String, d: Int, flow: Double, n: Int) {
            flow <= 44 ? (room, 125, flow, 1) : (room, 160, flow, Int((flow / 72).rounded(.up)))
        }
        for room in L.rooms {
            let A = room.area
            var s = 0.0, e = 0.0
            switch room.type {
            case .bedroom: s = max(3 * A, 60)
            case .living, .office: s = max(3 * A, 30)
            case .kitchenLiving: s = max(3 * A, 60); e = 90
            case .kitchen: e = 60
            case .bath: e = 50
            case .wc: e = 25
            case .boiler: e = max(A * h, 25); s = p.heatSource.needsFlue ? max(3 * A * h, 60) : 0
            case .hall, .corridor, .storage: break
            }
            if [.bath, .wc, .kitchen, .boiler].contains(room.type) { v.undercut.append(room.name) }
            let dev = e > 0 ? "вытяжной канал" + (s > 0 ? " + приточный клапан ×\(Int((s / 30).rounded(.up)))" : "") : s > 0 ? "приточный клапан ×\(Int((s / 30).rounded(.up)))" : "переток из жилых"
            v.rows.append(VentRow(room: room.name, area: A, supply: s, exhaust: e, device: dev))
            if s > 0 && room.type != .boiler { v.valves += Int((s / 30).rounded(.up)) }
            if e > 0 { v.ducts.append(duct(room.name, e)) }
            v.supply += s; v.exhaust += e
        }
        // вытяжка не меньше притока: недостающее — через санузлы и кухню
        if v.exhaust < v.supply, !v.ducts.isEmpty {
            let f = v.supply / max(v.exhaust, 1)
            v.ducts = v.ducts.map { duct($0.room, $0.flow * f) }
            v.exhaust = v.supply
        }
        return v
    }

    var table: StageTable {
        StageTable(head: ["Помещение", "S, м²", "Приток, м³/ч", "Вытяжка, м³/ч", "Устройство"],
                   rows: rows.map { [$0.room, fmt($0.area, 1), $0.supply > 0 ? "\(Int($0.supply))" : "—", $0.exhaust > 0 ? "\(Int($0.exhaust))" : "—", $0.device] }
                       + [["Итого", "", "\(Int(supply))", "\(Int(exhaust))", "баланс: вытяжка ≥ притока"]],
                   title: "Воздухообмен по помещениям", widths: [0.24, 0.1, 0.16, 0.16, 0.34])
    }
}

// MARK: - Геометрия кровли

enum RoofGeo {
    /// Число ендов: внутренние углы наружного контура + все углы внутреннего двора (скатные кровли)
    static func valleys(_ p: Project) -> Int {
        guard p.roofType == .gable || p.roofType == .hip else { return 0 }
        var n = 0
        for (ri, r) in p.rings.enumerated() {
            let s = Geo.signedArea(r)
            for i in r.indices {
                let a = r[(i - 1 + r.count) % r.count], b = r[i], c = r[(i + 1) % r.count]
                let cr = cross2(b - a, c - b)
                if ri == 0 ? cr * s < -1e-9 : true { n += 1 }
            }
        }
        return n
    }

    /// Длина одной ендовы по скату, м
    static func valleyLength(_ p: Project, _ F: Framing) -> Double {
        let run = max(F.rafterRun, 1)
        let tanA = tan(p.roofAngleEff * .pi / 180)
        return (2 * run * run + run * run * tanA * tanA).squareRoot() + p.overhang * 1.41
    }

    static func ridgeLength(_ F: Framing) -> Double { F.members.filter { $0.kind == .ridge }.reduce(0) { $0 + $1.length } }
}

// MARK: - Этапы

enum Protection {
    // MARK: Подготовка материалов

    static func materials(_ p: Project, _ r: CalcResults, _ b: BuildPlan) -> BuildStage {
        let F = b.frame
        var s = BuildStage(title: "Приёмка, хранение и защитная обработка материалов", icon: "drop.degreesign", scene: .floor)
        s.goal = "Получить сухой пиломатериал, сохранить материалы сухими до монтажа и пропитать древесину от гнили, жуков и огня ДО сборки, пока доступны все грани и торцы."
        s.when = "пиломатериал завезти за 1–2 недели до обвязки; обработку — сразу после приёмки, сборку — через 24–48 ч после высыхания состава"
        func area(_ f: (Member) -> Bool) -> Double {
            F.members.filter(f).reduce(0) { $0 + $1.length * 2 * ($1.sec.tm + $1.sec.wm) }
        }
        let risk: Set<MemberKind> = [.sill, .rim, .bottomPlate]
        let roofK: Set<MemberKind> = [.rafter, .hip, .ridge, .collar, .tie, .ceilingJoist, .gableStud, .counterBatten, .batten]
        let aRisk = area { risk.contains($0.kind) || ($0.stage == .floor && [.joist, .blocking, .girder].contains($0.kind)) }
        let aRoof = area { roofK.contains($0.kind) }
        let aFrame = area { !risk.contains($0.kind) && !roofK.contains($0.kind) && $0.kind != .tempBrace && !($0.stage == .floor && [.joist, .blocking, .girder].contains($0.kind)) }
        let facadeBattens = b.wallNet / 0.625 * 2 * (0.025 + 0.05)
        let woodFacade = p.facade == .imitationTimber
        s.steps = [
            "Приёмка пиломатериала: сорт не ниже 2-го (\(N.g8486.code)), влажность ≤ 20 % — проверить влагомером 10 досок из каждой пачки посередине длины. Камерной сушки (КС) хватает с запасом; «естественная влажность» 25–40 % — только сушить под навесом 3–6 недель, иначе каркас поведёт и швы раскроются.",
            "Отбраковка: гниль и синева глубже 2 мм — нет; сквозные трещины на торцах длиннее 150 мм, обзол на кромке, крыловатость и кривизна > 5 мм на 2 м — на короткие детали, не в стойки и балки. Сучки на кромке балки в средней трети пролёта — не в балки.",
            "Хранение: штабель на подкладках не ниже 300 мм от земли, через каждые 1–1.5 м — прокладки 25×50 (продух между рядами), сверху — кровля из ОСП/профлиста или тент с уклоном и свесом, бока открыты. Плёнкой «в обмотку» не укрывать — доска запреет.",
            "Что обрабатывать и чем (\(N.g20022.code) — классы условий службы):",
            "  • Зона риска увлажнения — обвязка/лежни, балки и распорки пола 1-го этажа, обвязочная доска, нижняя обвязка стен (≈ \(Int(aRisk)) м²): трудновымываемый огнебиозащитный состав II группы, 3 слоя, торцы и запилы — до полного насыщения. Без этого обвязка над подпольем сгнивает за 5–10 лет.",
            "  • Стропила, обрешётка, контробрешётка, чердачные балки, фронтоны (≈ \(Int(aRoof)) м²): огнебиозащита II группы огнезащитной эффективности (\(N.g53292.code)), 2 слоя — чердак и подкровельное пространство самые пожароопасные и влажные зоны.",
            "  • Остальной каркас стен и перекрытий (≈ \(Int(aFrame)) м²): бесцветный антисептик-консервант, 1–2 слоя (для КС-доски допустимо не обрабатывать, кроме торцов и примыканий к наружным стенам).",
            "  • Фасад: контррейки (≈ \(Int(facadeBattens)) м²) — антисептик для наружных работ\(woodFacade ? "; имитация бруса — грунт-антисептик по ВСЕМ сторонам и торцам до монтажа (тыльная сторона в вентзазоре тоже мокнет), лицевая — лессирующий состав 2 слоя после монтажа" : "").",
            "Как обрабатывать: на козлах, раскладывая доски с зазором; кистью-макловицей или садовым опрыскивателем; торцы — окунанием на 1–2 минуты. Слой — по высыхании предыдущего (2–4 ч). Колерованный состав — чтобы видеть пропуски. Каждый запил и отверстие, сделанные на стройке, — сразу прокрасить.",
            "Условия: древесина ≤ 25–30 % (на мокрую состав не впитается), t ≥ +5 °C, без дождя 24 ч. Состав — на водной основе, разрешённый для жилых помещений. Работать в перчатках, очках и респираторе.",
            "Другие материалы: ОСП и ГКЛ/ГВЛ — горизонтально на 3–4 подкладках под крышей, листы перед монтажом 24–48 ч в доме (акклиматизация); минвата — только под крышей, мокрую не монтировать; мембраны и плёнки — не на солнце: ветрозащиту закрыть фасадом/кровлей не позже чем через 3–4 месяца (УФ-стойкость); ламинат/SPC/доска — 48 ч в отапливаемом помещении до укладки; сухие смеси — на поддоне, плёнкой сверху.",
            "Ленты, герметики, пена — по температуре применения на упаковке (акриловые ленты и пена летняя — от +5 °C, бутиловые и зимняя пена — до −10 °C). Металл: только оцинкованный крепёж снаружи, срезы отливов и профилей — холодным цинком/краской.",
        ]
        s.decisions = [
            Decision(title: "Влажность древесины", value: "≤ 20 % при сборке", why: "усушка сырой доски 3–5 % по ширине — щели, скрип, трещины отделки, «ведёт» каркас", ref: "\(N.g8486.code), \(N.sp64.at("п. 5.1, табл. 2"))"),
            Decision(title: "Защита в зоне риска", value: "огнебиозащита II группы, 3 слоя + торцы", why: "класс условий службы 3 (периодическое увлажнение, контакт с бетоном) — гниение начинается при влажности > 20 %", ref: "\(N.g20022.code), \(N.sp64.at("разд. 11 «Защита от биоповреждения»"))"),
            Decision(title: "Огнезащита кровли", value: "II группа огнезащитной эффективности", why: "стропила и обрешётка — открытая сухая древесина под кровлей, путь распространения огня", ref: "\(N.g53292.code), \(N.sp4.code)"),
            Decision(title: "Хранение", value: "под навесом, на подкладках ≥ 300 мм, с прокладками", why: "намокший и запревший пиломатериал теряет сорт, синеет и плесневеет за 2–3 недели", ref: N.sp48.at("разд. «Складирование материалов»")),
        ]
        s.tools = ["Влагомер для древесины (игольчатый)", "Опрыскиватель садовый 5–8 л", "Кисть-макловица, валик", "Ёмкость для окунания торцов (ведро/лоток)", "Козлы 2 шт.", "Перчатки нитриловые, очки, респиратор", "Тент 6×8 м, подкладки и прокладки 25×50"]
        s.guides = [Guide(title: "Как быстро пропитать весь каркас", steps: [
            "Сначала — разметка и запилы деталей обвязки и балок (угловые замки, вырезы), потом пропитка: так обработаны и все запилы.",
            "Разложить 10–15 досок на прокладки, пройти опрыскивателем верх и кромки, через 2–3 часа перевернуть и пройти обратную сторону.",
            "Торцы — макнуть в лоток с составом на 1–2 минуты или 3 раза кистью: через торец древесина впитывает влагу в 10–20 раз быстрее, чем через пласть.",
            "Колер показывает пропуски; после высыхания — второй слой. Сложить в штабель с прокладками до сборки.",
        ], tip: "Пропитка на уже собранном каркасе не попадает в стыки, торцы под обвязкой и в пакеты стоек — именно там и начинается гниль.")]
        s.items = [
            WorkItem(name: "Огнебиозащитный состав II группы трудновымываемый (зона риска)", qty: max(5, (aRisk * 0.35).rounded(.up)), unit: "л", note: "≈ 0.12 л/м² × 3 слоя + торцы", digits: 0, price: Price.antisepticL * 1.3),
            WorkItem(name: "Огнебиозащитный состав II группы (стропила, обрешётка, чердак)", qty: max(5, (aRoof * 0.3).rounded(.up)), unit: "л", note: "≈ 0.15 л/м² × 2 слоя", digits: 0, price: Price.antisepticL),
            WorkItem(name: "Антисептик-консервант бесцветный (каркас стен и перекрытий)", qty: max(5, (aFrame * 0.15).rounded(.up)), unit: "л", note: "1 слой; по КС-доске — торцы и примыкания", digits: 0, price: 90),
            WorkItem(name: "Антисептик для наружных работ (контррейки фасада)", qty: max(2, (facadeBattens * 0.3).rounded(.up)), unit: "л", digits: 0, price: 150),
            WorkItem(name: "Влагомер для древесины", qty: 1, unit: "шт", digits: 0, price: 1500),
            WorkItem(name: "Тент укрывной 6×8 м (штабель)", qty: 2, unit: "шт", digits: 0, price: 1800),
            WorkItem(name: "Холодный цинк (аэрозоль) для срезов металла", qty: 2, unit: "шт", digits: 0, price: 650),
        ]
        if woodFacade {
            s.items += [WorkItem(name: "Грунт-антисептик для фасадной доски (все стороны)", qty: (b.wallNet * 2.2 * 0.12).rounded(.up), unit: "л", note: "лицо, тыл, кромки, торцы", digits: 0, price: 350),
                        WorkItem(name: "Лессирующий состав для фасада (2 слоя по лицу)", qty: (b.wallNet * 1.1 * 0.1 * 2).rounded(.up), unit: "л", digits: 0, price: 900)]
        }
        return s
    }

    // MARK: Вентиляция

    static func ventilation(_ p: Project, _ b: BuildPlan) -> BuildStage {
        let v = VentPlan.make(p, b.layout)
        var s = BuildStage(title: "Вентиляция: расчёт воздухообмена и каналы", icon: "wind", scene: .finish)
        s.goal = "Удалять влагу из дома: каркасный дом герметичен, без притока и вытяжки влажность растёт, плесневеют углы, мокнут утеплитель и окна."
        s.when = "каналы и проходки — вместе с черновой инженеркой, до утеплителя и пароизоляции изнутри; отверстия клапанов — до фасада"
        let rise = p.roofType == .flat ? 0.5 : tan(p.roofAngleEff * .pi / 180) * max(b.frame.rafterRun, 0.5)
        let ductLen = rise + 0.8 + Double(max(p.floors, 1) - 1) * p.floorHeight
        let coldAttic = !p.roofInsulated && p.roofType != .flat
        s.steps = [
            "Расчёт (таблица ниже): приток в жилые комнаты — 3 м³/ч на 1 м², в спальню не менее 60 м³/ч (30 м³/ч на человека); вытяжка — кухня 60–90, ванная/совмещённый санузел 50, туалет 25 м³/ч, котельная — не менее 1 обмена/ч. Итого приток \(Int(v.supply)), вытяжка \(Int(v.exhaust)) м³/ч.",
            "Естественная вытяжка — вертикальными каналами без горизонтальных участков длиннее 1 м: " + v.ducts.map { "\($0.room.lowercased()) — \($0.n > 1 ? "\($0.n) × " : "")Ø\($0.d) (\(Int($0.flow)) м³/ч)" }.joined(separator: ", ") + ". Скорость в естественном канале ≤ 1 м/с, поэтому каналов много; каналы — отдельные от каждого помещения, кухню с санузлом не объединять.",
            v.channels > 4 ? "При \(v.channels) естественных каналах выгоднее ПВУ с рекуператором: 2 магистрали Ø160 через кровлю/стену вместо \(v.channels) труб, приток подогрет, расход тепла на вентиляцию меньше в 3–5 раз." : "",
            "Выход над кровлей: в пределах 1.5 м от конька — не ниже 0.5 м над коньком, дальше — не ниже конька; на выходе — дефлектор/зонт, проход через кровлю — штатным проходным элементом с уплотнителем под ваше покрытие, через пароизоляцию — с манжетой.",
            coldAttic ? "На холодном чердаке каналы утеплить минватой 50 мм в фольгированной оболочке по всей длине до выхода — иначе тёплый влажный воздух конденсируется в канале и вода течёт обратно в комнату." : "Над кровлей участок канала — утеплённый (сэндвич или скорлупа 50 мм), иначе зимой в нём конденсат и наледь.",
            "Приток: \(v.valves) приточных клапанов Ø100–125 в наружных стенах (КИВ/стеновые) — над радиаторами или за шторами, на высоте 2.0–2.2 м; гильза клапана проклеивается к ветрозащите и пароизоляции. Альтернатива — приточно-вытяжная установка с рекуператором (ПВУ): для герметичного каркасного дома она лучше — нет сквозняков и теряется на 70–90 % меньше тепла.",
            "Переток: двери \(v.undercut.joined(separator: ", ").lowercased()) — с зазором 15–20 мм под полотном или переточной решёткой; без него вытяжка из санузла не работает.",
            "Кухонная вытяжка над плитой — в отдельный канал или рециркуляционная; общий вентканал кухни ею не перекрывать.",
            "Проверка после монтажа: лист бумаги у решётки вытяжки при открытом клапане должен притягиваться; при ПВУ — замер расходов анемометром.",
        ].filter { !$0.isEmpty }
        s.decisions = [
            Decision(title: "Воздухообмен", value: "приток \(Int(v.supply)) м³/ч, вытяжка \(Int(v.exhaust)) м³/ч", why: "нормы для жилых помещений, кухонь и санузлов; вытяжка не меньше притока", ref: "\(N.sp60.at("разд. 7, прил. К")), \(N.sp55.at("разд. 9"))"),
            Decision(title: "Каналы", value: v.ducts.map { "\($0.n > 1 ? "\($0.n)×" : "")Ø\($0.d)" }.joined(separator: ", "), why: "естественная тяга — скорость ≤ 1 м/с; высота канала \(fmt(ductLen + 2.5, 1)) м от решётки до выхода", ref: N.sp60.at("разд. 7")),
            Decision(title: "Утепление каналов", value: coldAttic ? "минвата 50 мм на холодном чердаке" : "над кровлей", why: "точка росы в канале: конденсат стекает обратно", ref: N.sp60.at("разд. 7")),
        ]
        s.table = v.table
        s.tools = ["Коронка Ø110–132 по дереву/ОСП", "Дрель/перфоратор", "Ножовка, нож", "Шуруповёрт", "Анемометр (для ПВУ)"]
        s.fasteners = [Fastener(what: "Вентканал к стропилу/балке", item: "хомуты с шпилькой М8 / перфолента", how: "шуруповёрт, через 1–1.5 м"),
                       Fastener(what: "Проходной элемент кровли", item: "саморезы кровельные 4.8×35 + герметик", how: "шуруповёрт"),
                       Fastener(what: "Приточный клапан в стене", item: "гильза ПВХ + пена + бутиловая лента к мембранам", how: "вручную")]
        let nd = v.channels
        s.items = [
            WorkItem(name: "Воздуховод ПВХ/оцинк. Ø125–160 (вытяжные каналы)", qty: (Double(nd) * ductLen * 1.15).rounded(.up), unit: "м", note: "\(nd) каналов × \(fmt(ductLen, 1)) м", digits: 0, price: 450),
            WorkItem(name: "Утеплитель для воздуховодов (минвата 50 мм фольгир.)", qty: (Double(nd) * (coldAttic ? ductLen : 1.0) * 0.5).rounded(.up), unit: "м²", digits: 0, price: 350),
            WorkItem(name: "Проходной элемент кровельный с уплотнителем", qty: Double(nd + 1), unit: "шт", note: "вентканалы + фановый стояк", digits: 0, price: 2800),
            WorkItem(name: "Дефлектор/зонт вентканала", qty: Double(nd), unit: "шт", digits: 0, price: 1500),
            WorkItem(name: "Клапан приточный стеновой Ø100–125", qty: Double(v.valves), unit: "шт", digits: 0, price: 2200),
            WorkItem(name: "Решётка вентиляционная / переточная", qty: Double(nd + v.undercut.count), unit: "шт", digits: 0, price: 350),
            WorkItem(name: "Манжета для пароизоляции (проход трубы)", qty: Double(nd + 1), unit: "шт", digits: 0, price: 450),
        ]
        return s
    }

    // MARK: Дымоход, печь, котёл

    static func chimney(_ p: Project, _ b: BuildPlan) -> BuildStage? {
        guard p.fireplace || p.heatSource.needsFlue else { return nil }
        var s = BuildStage(title: "Дымоход и противопожарные разделки", icon: "flame", scene: .roof)
        s.goal = "Провести дымоход через деревянное перекрытие и кровлю так, чтобы горячие конструкции не касались дерева."
        s.when = "проход через перекрытие и кровлю — при устройстве кровли (каркас разделки — вместе со стропилами); печь/котёл — после чистового пола"
        let combustible = [.softShingle, .ondulin].contains(p.covering)
        s.steps = [
            p.fireplace ? "Печь/камин: на отдельном фундаменте (не на балках пола и не на ленте дома), с зазором 30–50 мм от перекрытия. Под топкой из сгораемого пола — металлический предтопочный лист 500×700 мм по негорючей теплоизоляции." : "",
            p.heatSource == .gas ? "Газовый котёл: котельная ≥ 7.5 м³ (или по паспорту котла), окно с форточкой, приток на горение ≥ 0.02 м² под дверью или клапан в стене; котёл с закрытой камерой — коаксиальный дымоход через стену. Проект газоснабжения и приёмка — газовой службой." : "",
            p.heatSource == .solid ? "Твердотопливный котёл: котельная с приточным каналом на горение, пол и стена у котла — негорючие (лист по базальтовому картону/ЦСП с плиткой) на 0.5 м по сторонам и 1.25 м перед топкой." : "",
            "Дымоход — сэндвич из нержавеющей стали с утеплителем ≥ 50 мм (или кирпичный). Разделка в перекрытии и кровле — 500 мм от внутренней поверхности дымохода до деревянных конструкций (380 мм — если дерево защищено негорючим листом по базальтовому картону): короб из стальной/ЦСП-разделки, заполненный базальтовой ватой или керамзитом.",
            "Отступка от стены у печи — 130 мм с защитой стены (минерит/ЦСП по базальтовому картону) или 260 мм без защиты; деревянные стойки каркаса у печи — негорючая облицовка на высоту печи + 250 мм.",
            "Через кровлю — мастер-флеш/кровельная разделка с фартуком под покрытие, высота трубы: в 1.5 м от конька — ≥ 0.5 м над коньком, 1.5–3 м — не ниже конька, дальше — не ниже линии 10° от конька.",
            combustible ? "Кровля горючая (\(p.covering.title.lowercased())) — на трубе обязателен искрогаситель (сетка 5×5 мм)." : "",
            "Пароизоляцию и мембраны в зоне разделки — прерывать, стык к коробу — алюминиевой лентой, не бутилом.",
            "Перед первой топкой — проверка тяги и герметичности, акт осмотра дымохода (печник/ВДПО), датчик угарного газа в помещении с топкой.",
        ].filter { !$0.isEmpty }
        s.decisions = [
            Decision(title: "Разделка", value: "500 мм (380 мм с защитой дерева)", why: "расстояние от дымового канала до сгораемых конструкций перекрытия и кровли", ref: N.sp7.at("п. 5.14, 5.15, табл. Б.1")),
            Decision(title: "Отступка", value: "130 мм с защитой / 260 мм без", why: "от стенки печи до стены из горючих материалов", ref: N.sp7.at("п. 5.17, прил. Б")),
            Decision(title: "Высота трубы", value: "≥ 0.5 м над коньком в 1.5 м от него", why: "тяга и защита от опрокидывания тяги ветром", ref: N.sp7.at("п. 5.10")),
        ]
        if p.heatSource == .gas { s.decisions.append(Decision(title: "Газовая котельная", value: "≥ 7.5 м³, окно, приток на горение", why: "безопасная эксплуатация газового котла", ref: N.sp402.code)) }
        s.tools = ["Болгарка с диском по металлу", "Шуруповёрт", "Ножницы по металлу", "Уровень, отвес", "Перчатки, респиратор (базальтовая вата)"]
        s.items = [
            WorkItem(name: "Дымоход сэндвич нерж. Ø115–150/200 (комплект по высоте дома)", qty: (b.frame.wallTop + 2.5).rounded(.up), unit: "м", digits: 0, price: 5500),
            WorkItem(name: "Короб-разделка потолочный (ППУ) с базальтовой ватой", qty: Double(max(p.floors, 1)), unit: "шт", digits: 0, price: 6000),
            WorkItem(name: "Мастер-флеш / кровельная разделка с фартуком", qty: 1, unit: "шт", digits: 0, price: 3500),
            WorkItem(name: "Базальтовый картон + лист оцинк./минерит (защита стены и пола)", qty: 4, unit: "м²", digits: 0, price: 1800),
            WorkItem(name: "Датчик угарного газа", qty: 1, unit: "шт", digits: 0, price: 2500),
        ]
        if p.fireplace { s.items.append(WorkItem(name: "Предтопочный лист 500×700", qty: 1, unit: "шт", digits: 0, price: 2500)) }
        return s
    }

    // MARK: Мокрые зоны

    static func wetZones(_ p: Project, _ b: BuildPlan) -> BuildStage? {
        let L = b.layout
        let wet = L.rooms.filter { $0.type == .bath || $0.type == .wc }
        guard !wet.isEmpty else { return nil }
        let A = wet.reduce(0) { $0 + $1.area }
        let P = wet.reduce(0) { $0 + 2 * ($1.w + $1.h) }
        let showers = L.furniture.filter { $0.kind == .shower || $0.kind == .bathtub }.count
        let outlets = L.points.filter { r in wet.contains { $0.name == r.room } }.count
        let joists = p.floorBase == .joists
        var s = BuildStage(title: "Мокрые зоны: гидроизоляция санузлов", icon: "drop.circle", scene: .finish)
        s.goal = "Не пустить воду из душа и от протечек в деревянное перекрытие и каркас стен."
        s.when = "после основания пола и обшивки стен влагостойкими листами, до плитки и сантехприборов"
        s.steps = [
            joists ? "Основание пола по балкам: шаг балок в санузле ≤ 400–625 мм с прогибом ≤ l/400 (под плитку), по ОСП-22 — ГВЛВ 2×10 мм или ЦСП 16 мм на клей и саморезы через 200 мм. Плитка прямо на ОСП не клеится — ОСП «играет» и трескает швы." : "Основание: стяжка/плита — сухая (влажность ≤ 4 %), прогрунтована. Уклон 1–2 % к трапу, если душ без поддона.",
            "Стены санузлов: ГКЛВ, в зоне душа и ванны — ЦСП, ГВЛВ или цементная плита на высоту 2.0 м; стыки — на стойках каркаса.",
            "Ленты: во все углы пол–стена и стена–стена, на стыки листов, вокруг трапа — гидроизоляционная лента; на выводы труб — манжеты (\(outlets) шт.). Ленты вклеиваются в первый слой мастики.",
            "Обмазочная гидроизоляция (полимерная/полимерцементная, \(N.sp71.code)) — 2 слоя крест-накрест по 1–1.5 кг/м²: весь пол + заведение на стены 200 мм; в зоне душа — стены на высоту 2.0 м и шириной на 0.3 м шире поддона; за ванной — на 0.3 м выше борта.",
            showers > 0 ? "Душ без поддона — трап с гидроизоляционным фланцем, его фланец заклеивается в гидроизоляцию; высота гидрозатвора ≥ 50 мм (сухой затвор от запаха)." : "",
            "Проверка: через 24 ч налить воду на пол слоем 20–30 мм на сутки (порог закрыть) — снизу и по нижним стенам сухо.",
            "Плитка — на клей C2 по гидроизоляции, швы — эпоксидная/влагостойкая затирка; примыкание ванны и поддона — санитарный силикон с антигрибковой добавкой.",
            "Пароизоляция потолка санузла — сплошная и проклеенная; вытяжка обязательна (см. «Вентиляция»), дверь — с зазором под полотном.",
            "Защита от протечек: датчики на полу под стиральной машиной, бойлером и коллектором + краны с электроприводом на вводе.",
        ].filter { !$0.isEmpty }
        s.decisions = [
            Decision(title: "Гидроизоляция", value: "обмазочная 2 слоя + ленты и манжеты", why: "пол санузла по дереву — вода не должна попасть в ОСП и балки", ref: "\(N.sp29.at("разд. 6 «Гидроизоляция»")), \(N.sp71.code)"),
            Decision(title: "Основание под плитку", value: joists ? "ГВЛВ 2×10 / ЦСП 16 поверх ОСП" : "сухая стяжка, грунт", why: "плитке нужно жёсткое основание с прогибом ≤ l/400", ref: N.sp29.at("разд. 8")),
        ]
        s.tools = ["Шпатель, кисть-макловица для мастики", "Миксер-насадка", "Нож, ножницы для лент", "Уровень 2 м"]
        let wallWet = P * 0.2 + Double(max(showers, 1)) * 2.0 * 2.2
        s.items = [
            WorkItem(name: "Гидроизоляция обмазочная полимерная (2 слоя)", qty: ((A * 1.1 + wallWet) * 2.5).rounded(.up), unit: "кг", note: "\(fmt(A, 1)) м² пола + \(fmt(wallWet, 1)) м² стен", digits: 0, price: 280),
            WorkItem(name: "Лента гидроизоляционная для углов и стыков", qty: (P * 1.5 + Double(max(showers, 1)) * 6).rounded(.up), unit: "м", digits: 0, price: 120),
            WorkItem(name: "Манжета гидроизоляционная на вывод трубы", qty: Double(outlets), unit: "шт", digits: 0, price: 250),
            WorkItem(name: "Защита от протечек: краны с электроприводом + датчики", qty: 1, unit: "компл", digits: 0, price: 16000),
        ]
        if joists { s.items.insert(WorkItem(name: "ГВЛВ 10 мм 1200×2500 (основание под плитку, 2 слоя)", qty: (A * 2 / 3 * 1.1).rounded(.up), unit: "лист", digits: 0, price: 650), at: 0) }
        s.items.append(WorkItem(name: "ЦСП/ГВЛВ для стен в зоне душа и ванны", qty: (Double(max(showers, 1)) * 4.4 / 3 * 1.1).rounded(.up), unit: "лист", digits: 0, price: 1100))
        return s
    }

    // MARK: Крыльцо, козырёк, терраса

    static func porch(_ p: Project, _ b: BuildPlan) -> BuildStage? {
        let doors = p.validOpenings.filter { o in if case .edge = o.host { return o.kind.isDoor } else { return false } }
        guard !doors.isEmpty else { return nil }
        let n = doors.count
        let ffl = b.layout.ffl
        let steps = max(1, Int((max(ffl - 0.03, 0.15) / 0.17).rounded()))
        var s = BuildStage(title: "Крыльцо, козырёк, терраса", icon: "door.right.hand.open", scene: .finish)
        s.goal = "Сделать входы, у которых вода не затекает под дверь и в стену, а крыльцо не рвёт дом при пучении."
        s.when = "опоры крыльца — до отмостки; козырёк — вместе с фасадом (его кронштейны крепятся к стойкам каркаса до обшивки)"
        s.steps = [
            "Крыльцо (\(n) шт.) — на СВОИХ опорах (винтовые сваи/столбы ниже промерзания), не связанных с фундаментом дома: зазор 20–30 мм. Связанное крыльцо пучением отрывает и перекашивает дверь.",
            "Площадка — не меньше 1.5 × ширины двери в глубину (≥ 1.2–1.5 м), её верх на 20–50 мм НИЖЕ порога, уклон 1–2 % от дома; настил с зазорами 5–8 мм. Ступени: \(steps) × ≈ \(Int((ffl - 0.03) / Double(steps) * 1000)) мм высотой, проступь 280–300 мм; при 3 и более ступенях — перила.",
            "Козырёк над каждым входом: вылет не меньше глубины площадки (1.0–1.5 м), с водостоком или капельником. Кронштейны/консоли — в стойки каркаса через ОСП (закладные бруски ставятся до обшивки), примыкание к стене — фартук, заведённый ПОД ветрозащиту выше козырька.",
            "Терраса (если есть) — лучше отдельная, на своих опорах. Если опорная доска крепится к дому — только к обвязке/балкам через дистанционные шайбы 15–20 мм, над ней — Z-отлив, заведённый под мембрану; настил — с уклоном 1–2 % от дома и зазором 15–20 мм у стены.",
            "Лаги и опорные брусья крыльца и террасы — лиственница или сосна с пропиткой класса 4 (контакт с землёй/водой), торцы — 3 слоя антисептика; оголовки свай — гидроизоляция между металлом и деревом.",
            "Под крыльцом и террасой — геотекстиль и щебень (от травы и застоя воды), сток с площадки — в сторону от отмостки дома.",
        ]
        s.decisions = [
            Decision(title: "Фундамент крыльца", value: "отдельный, зазор 20–30 мм", why: "разная нагрузка и пучение у входа — связанное крыльцо отрывается от дома", ref: N.sp22.at("разд. 6.8")),
            Decision(title: "Площадка и ступени", value: "ниже порога на 20–50 мм, ступень ≤ 170–180 мм, проступь ≥ 280 мм", why: "вода не затекает под дверь; удобный и безопасный подъём", ref: N.sp55.at("разд. 6")),
            Decision(title: "Козырёк", value: "над каждым входом, вылет ≥ 1.0 м", why: "защита двери, порога и нижней обвязки от косого дождя и снега", ref: N.sp17.at("разд. 9")),
        ]
        s.tools = ["Ключ/вороток для винтовых свай", "Нивелир/уровень", "Циркулярная пила, шуруповёрт", "Лопата, трамбовка"]
        s.items = [
            WorkItem(name: "Свая винтовая 89×2000 с оголовком (крыльцо)", qty: Double(n * 4), unit: "шт", digits: 0, price: Price.screwPile(0.089) + 400),
            WorkItem(name: "Брус 100×150 лиственница (обвязка крыльца)", qty: Double(n * 2), unit: "шт", note: "по 6 м", digits: 0, price: 4200),
            WorkItem(name: "Доска террасная лиственница 28×140 (площадка и ступени)", qty: (Double(n) * 3.5).rounded(.up), unit: "м²", digits: 0, price: 2600),
            WorkItem(name: "Козырёк над входом: консоли, обрешётка, покрытие, водосток (комплект)", qty: Double(n), unit: "компл", digits: 0, price: 18000),
            WorkItem(name: "Антисептик класса 4 для контакта с землёй", qty: Double(n * 3), unit: "л", digits: 0, price: 220),
        ]
        return s
    }

    // MARK: Сдача и эксплуатация

    static func handover(_ p: Project, _ b: BuildPlan) -> BuildStage {
        let L = b.layout
        let living = L.rooms.filter { [.bedroom, .living, .office, .kitchenLiving, .kitchen, .corridor, .hall].contains($0.type) }.count
        var s = BuildStage(title: "Сдача дома и правила эксплуатации", icon: "checkmark.seal", scene: .finish)
        s.goal = "Проверить дом перед заселением и знать, что и когда обслуживать, чтобы каркас прослужил 50+ лет."
        s.when = "после всех работ; первый год — пристальное наблюдение (усадка, влажность, первая зима)"
        s.steps = [
            "Пожарная безопасность: автономные дымовые извещатели в каждой жилой комнате и коридоре (\(max(living, 2)) шт.), огнетушитель ОП-4 на кухне\(p.fireplace || p.heatSource.needsFlue ? " и у котла/печи, датчик угарного газа" : ""). Проверять кнопкой раз в месяц, батарейки — раз в год.",
            "Электрика: замер сопротивления контура заземления (≤ 30 Ом для системы TT; для TN-C-S — повторное ≤ 30 Ом) и изоляции, проверка УЗО кнопкой «Т» раз в квартал.",
            "Первая зима: держать влажность 40–55 % (гигрометр), не сушить дом «на максимум» обогревом — древесина досыхает до 10–12 %, щели в отделке появляются в первый год и потом стабилизируются.",
            "Нельзя: заклеивать и закрывать приточные клапаны, закрывать продухи подполья на зиму (кроме сильных морозов без снега — частично), закрывать вентзазор фасада внизу и вверху, складывать снег и дрова к стене выше цоколя.",
            "Календарь обслуживания — в таблице ниже.",
        ]
        s.decisions = [
            Decision(title: "Извещатели", value: "автономные дымовые в жилых и коридорах", why: "деревянный дом горит быстро — сигнал в первые минуты", ref: N.sp55.at("разд. 6 «Пожарная безопасность»")),
            Decision(title: "Влажность воздуха", value: "40–55 % зимой", why: "выше — конденсат на окнах и в каркасе, ниже — растрескивание древесины", ref: N.sp50.at("табл. 1, расчётные условия")),
        ]
        s.table = StageTable(head: ["Когда", "Что проверить и сделать"], rows: [
            ["Весна", "Водостоки и желоба — прочистить; отмостка — трещины и провалы заделать; цоколь и низ фасада — нет ли сырости и плесени; продухи подполья открыты, сетка цела"],
            ["Весна", "Кровля после снега: снегозадержатели, коньки, проходки и разделки; потёки на пароизоляции/чердаке; вентзазор у карниза не забит"],
            ["Лето", "Фасадная доска — подкрасить лессирующим составом раз в 3–5 лет (южная сторона — чаще); герметики и отливы окон; дренажные колодцы — промыть"],
            ["Осень", "Водостоки — от листвы; приточные клапаны и фильтры ПВУ — почистить/заменить; дымоход — прочистка перед сезоном (печь — 2 раза за сезон)"],
            ["Зима", "Чердак/подкровельное — нет ли инея на мембране (значит, пар идёт через пароизоляцию: проверить проходки и стыки); снег с кровли над входами; наледь в желобах"],
            ["Раз в год", "Дымовые извещатели — батарейки; УЗО — тест; контур заземления — визуально; герметики душа и ванны; датчики протечек — тест"],
            ["Раз в 5 лет", "Повторная пропитка открытых деревянных элементов крыльца и террасы; ревизия кровельных саморезов (подтянуть, заменить шайбы)"],
        ], title: "Календарь обслуживания дома", widths: [0.14, 0.86])
        s.items = [
            WorkItem(name: "Извещатель пожарный дымовой автономный", qty: Double(max(living, 2)), unit: "шт", digits: 0, price: 900),
            WorkItem(name: "Огнетушитель порошковый ОП-4", qty: p.fireplace || p.heatSource.needsFlue ? 2 : 1, unit: "шт", digits: 0, price: 1300),
            WorkItem(name: "Гигрометр-термометр комнатный", qty: 1, unit: "шт", digits: 0, price: 800),
        ]
        return s
    }
}
