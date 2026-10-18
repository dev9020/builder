import SwiftUI

struct ResultsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var p: Project

    var body: some View {
        let r = model.results
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WeightsView(w: Weights.make(p, r), kind: p.selectedFoundation)
                comparison(r)
                loads(r)
                switch p.selectedFoundation {
                case .strip: strip(r.strip)
                case .slab: slab(r.slab)
                case .piles: piles(r.piles)
                }
                DrainageBlock(d: Drainage.make(p, r), kind: p.selectedFoundation,
                              depth: p.selectedFoundation == .strip ? r.strip.depth : p.selectedFoundation == .slab ? max(0.1, r.slab.t - 0.15) : 0,
                              plinth: p.selectedFoundation == .strip ? p.plinth : 0.15)
                Text("Расчёт предварительный: характеристики грунта приняты по табличным значениям, ветровые, сейсмические нагрузки и особые грунты (просадочные, набухающие, торф) не учитываются. Для строительства используйте данные инженерно-геологических изысканий; проект должен проверить инженер.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: 1000, alignment: .leading)
        }
    }

    // MARK: - Блоки

    func comparison(_ r: CalcResults) -> some View {
        GroupBox("Сравнение вариантов") {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                GridRow {
                    Text("Вариант").bold(); Text("Основные размеры").bold(); Text("Бетон, м³").bold(); Text("Арматура, кг").bold(); Text("Материалы*").bold(); Text("Проверки").bold()
                }
                Divider()
                row(.strip, r.strip.ext.map { "b = \(Int($0.b * 1000)) мм, H = \(Int($0.H * 1000)) мм, d = \(fmt(r.strip.depth)) м" } ?? "—",
                    r.strip.concrete + r.strip.prep, r.strip.steel, r.strip.ok)
                row(.slab, "t = \(Int(r.slab.t * 1000)) мм, Ø\(r.slab.d) шаг \(Int(r.slab.step * 1000)), \(fmt(r.slab.area, 1)) м²",
                    r.slab.concrete, r.slab.steel, r.slab.ok)
                row(.piles, "\(r.piles.positions.count) шт. Ø\(Int(r.piles.d * 1000)) L = \(fmt(r.piles.L)) м, ростверк \(Int(r.piles.bg * 1000))×\(Int(r.piles.hg * 1000))",
                    r.piles.concrete + r.piles.grillageConcrete, r.piles.steel, r.piles.ok)
            }
            .padding(6)
            Text("* материалы на фундамент, отмостку и дренаж, ориентировочно. " + Price.note).font(.caption).foregroundStyle(.secondary)
        }
    }

    func row(_ k: FoundationKind, _ dims: String, _ v: Double, _ m: Double, _ ok: Bool) -> some View {
        GridRow {
            Button(k.title) { p.selectedFoundation = k }
                .buttonStyle(.link)
                .fontWeight(p.selectedFoundation == k ? .bold : .regular)
            Text(dims)
            Text(fmt(v, 1))
            Text(fmt(m, 0))
            Text("≈ " + rub(Works.plan(p, model.results, kind: k).purchase.reduce(0) { $0 + $1.cost })).monospacedDigit()
            Label(ok ? "OK" : "Не проходит", systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .red)
        }
    }

    func loads(_ r: CalcResults) -> some View {
        let L = r.loads
        return GroupBox("Сбор нагрузок (СП 20.13330.2016)") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 24) {
                    stat("Стены", L.summary.walls)
                    stat("Перекрытия", L.summary.floors)
                    stat("Кровля", L.summary.roof)
                    stat("Снег", L.summary.snow)
                    stat("Полезная", L.summary.live)
                    stat("Итого (норм.)", L.summary.total)
                }
                Text("Снеговой район \(p.snowRegion.roman): S0 = \(fmt(p.snowRegion.s0, 1)) кПа, μ = \(fmt(L.snowMu)), S = \(fmt(L.snowS)) кПа; кровля \(fmt(L.roofDead)) кПа на план, площадь кровли ≈ \(fmt(L.roofArea, 1)) м². Высота стен \(fmt(L.wallHeight, 1)) м.")
                    .font(.caption).foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 3) {
                    GridRow {
                        Text("Стена").bold(); Text("Материал").bold(); Text("L, м").bold(); Text("Стена").bold(); Text("Перекр.").bold()
                        Text("Кровля").bold(); Text("Снег").bold(); Text("Полезн.").bold(); Text("qн, кН/м").bold(); Text("qр, кН/м").bold()
                    }
                    ForEach(Array(L.lines.enumerated()), id: \.element.id) { i, ln in
                        let q = L.stripLoads[i]
                        GridRow {
                            Text(ln.name); Text(ln.material.short); Text(fmt(ln.length)); Text(fmt(q.wall, 1)); Text(fmt(q.floors, 1))
                            Text(fmt(q.roof, 1)); Text(fmt(q.snow, 1)); Text(fmt(q.live, 1)); Text(fmt(q.char, 1)).bold(); Text(fmt(q.design, 1))
                        }
                        .font(.system(.caption, design: .monospaced))
                    }
                }
                Text("Грузовые площади определены по ближайшей опоре; скатная кровля опирается на стены, параллельные коньку, плоская — на все несущие стены. qр — основное сочетание: γf по табл. 7.1, снег 1.4, полезная 1.3, ψ = 0.9 для неосновной кратковременной.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(6)
        }
    }

    func stat(_ t: String, _ v: Double) -> some View {
        VStack(alignment: .leading) {
            Text(t).font(.caption).foregroundStyle(.secondary)
            Text("\(fmt(v / 9.81, 1)) т").font(.title3.weight(.semibold))
            Text("\(fmt(v, 0)) кН").font(.caption2).foregroundStyle(.secondary)
        }
    }

    func checks(_ c: [Check]) -> some View {
        GroupBox("Проверки") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(c) { ch in
                    HStack(alignment: .top) {
                        Image(systemName: ch.ok ? "checkmark.circle.fill" : "xmark.octagon.fill").foregroundStyle(ch.ok ? .green : .red)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(ch.title).bold()
                            Text(ch.value)
                            Text(ch.ref).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    func spec(_ items: [RebarItem], extra: [(String, String)]) -> some View {
        GroupBox("Спецификация материалов") {
            VStack(alignment: .leading, spacing: 8) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 3) {
                    GridRow { Text("Поз.").bold(); Text("Элемент").bold(); Text("Ø, класс").bold(); Text("Примечание").bold(); Text("Длина, м").bold(); Text("Масса, кг").bold() }
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                        GridRow {
                            Text("\(i + 1)"); Text(it.name); Text("Ø\(it.d) \(it.cls)"); Text(it.spec).foregroundStyle(.secondary)
                            Text(fmt(it.length, 0)); Text(fmt(it.mass, 1))
                        }
                    }
                    Divider()
                    let byD = Dictionary(grouping: items, by: \.d).sorted { $0.key < $1.key }
                    ForEach(byD, id: \.key) { d, its in
                        GridRow {
                            Text(""); Text("Итого Ø\(d)").bold(); Text(""); Text("")
                            Text(fmt(its.reduce(0) { $0 + $1.length }, 0)); Text(fmt(its.reduce(0) { $0 + $1.mass }, 1)).bold()
                        }
                    }
                    GridRow {
                        Text(""); Text("Всего арматуры").bold(); Text(""); Text(""); Text("")
                        Text("\(fmt(items.reduce(0) { $0 + $1.mass }, 0)) кг").bold()
                    }
                }
                Divider()
                ForEach(extra, id: \.0) { k, v in
                    HStack { Text(k); Spacer(); Text(v).bold() }
                }
            }
            .padding(6)
        }
    }

    func notes(_ n: [String]) -> some View {
        GroupBox("Рекомендации") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(n, id: \.self) { Text("• " + $0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    // MARK: - Лента

    func strip(_ s: StripResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Ленточный фундамент — параметры") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Глубина заложения d = \(fmt(s.depth)) м (dfn = \(fmt(s.dfn)) м, df = \(fmt(s.df)) м); высота ленты H = \(fmt(s.H)) м; цоколь \(fmt(p.plinth)) м. Бетон \(p.concrete.title), арматура \(p.rebar.rawValue). Нахлёст стержней \(Int(s.lap * 1000)) мм.")
                    HStack(alignment: .top, spacing: 20) {
                        if let e = s.ext { sectionCard("Наружные стены", e) }
                        if let i = s.int { sectionCard("Несущие перегородки", i) }
                    }
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 3) {
                        GridRow { Text("Участок").bold(); Text("qн, кН/м").bold(); Text("bтреб, мм").bold(); Text("b, мм").bold(); Text("p, кПа").bold(); Text("R, кПа").bold(); Text("s, см").bold() }
                        ForEach(s.lines, id: \.line.id) { l in
                            GridRow {
                                Text(l.line.name); Text(fmt(l.load.char, 1)); Text("\(Int((l.bReq * 1000).rounded()))"); Text("\(Int((l.b * 1000).rounded()))")
                                Text(fmt(l.p, 1)); Text(fmt(l.R, 1)); Text(fmt(l.s * 100, 2))
                            }
                            .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
                .padding(6)
            }
            checks(s.checks)
            spec(s.rebar, extra: [("Бетон \(p.concrete.title)", "\(fmt(s.concrete, 2)) м³"),
                                  ("Бетонная подготовка B7.5", "\(fmt(s.prep, 2)) м³"),
                                  ("Песчаная подушка", "\(fmt(s.sand, 2)) м³"),
                                  ("Опалубка (2 стороны)", "\(fmt(s.formwork, 1)) м²")] +
                 (s.eps > 0 ? [("ЭППС (цоколь + отмостка)", "\(fmt(s.eps, 1)) м²")] : []))
            notes(s.notes)
        }
    }

    func sectionCard(_ title: String, _ sec: StripSection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            StripSectionView(sec: sec, depth: model.results.strip.depth)
                .frame(width: 300, height: 300)
            Text("Сечение \(sec.isT ? "тавровое" : "прямоугольное"): b = \(Int(sec.b * 1000)) мм\(sec.isT ? ", стенка \(Int(sec.stemW * 1000)) мм, подошва h = \(Int(sec.soleH * 1000)) мм" : ""), H = \(Int(sec.H * 1000)) мм")
            Text("Низ: \(sec.botN)Ø\(sec.botD) · Верх: \(sec.topN)Ø\(sec.topD)\(sec.sideRows > 0 ? " · Бок: \(sec.sideRows * 2)Ø\(sec.sideD)" : "")")
            Text("Хомуты Ø\(sec.clampD) А240 шаг \(Int(sec.clampStep * 1000)) мм\(sec.isT && sec.soleD > 0 ? " · Подошва Ø\(sec.soleD) шаг \(Int(sec.soleStep * 1000))" : "")")
            Text("μ = \(fmt(sec.mu * 100, 3)) %, защитный слой \(Int(sec.cover * 1000)) мм").foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    // MARK: - Плита

    func slab(_ s: SlabResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Монолитная фундаментная плита — параметры") {
                HStack(alignment: .top, spacing: 20) {
                    SlabSectionView(s: s).frame(width: 340, height: 220)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Толщина t = \(Int(s.t * 1000)) мм, площадь \(fmt(s.area, 1)) м², периметр \(fmt(s.perimeter, 1)) м")
                        Text("Армирование: две сетки Ø\(s.d) \(p.rebar.rawValue) шаг \(Int(s.step * 1000))×\(Int(s.step * 1000)) мм (верх и низ)")
                        Text("Защитный слой \(Int(s.cover * 1000)) мм; бетон \(p.concrete.title)")
                        Text("Отметка подошвы относительно земли: −\(fmt(max(0, s.t - 0.15))) м, подушка \(Int(p.slabCushion * 1000)) мм")
                        Text("β = \(fmt(s.beta, 3)) 1/м (балка на упругом основании, k = \(fmt(p.soil.kSub, 0)) кН/м³)").foregroundStyle(.secondary)
                        Text("Mmax = \(fmt(s.Mmax, 1)) кН·м/м, As,треб = \(fmt(s.As * 1e6, 0)) мм²/м").foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
                .padding(6)
            }
            checks(s.checks)
            spec(s.rebar, extra: [("Бетон \(p.concrete.title)", "\(fmt(s.concrete, 2)) м³"),
                                  ("Песчаная подушка", "\(fmt(s.sand, 1)) м³"),
                                  ("ЭППС 100 мм (УШП + отмостка)", "\(fmt(s.eps, 1)) м²"),
                                  ("Опалубка торцов", "\(fmt(s.formwork, 1)) м²")])
            notes(s.notes)
        }
    }

    // MARK: - Сваи

    func piles(_ s: PileResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Свайный фундамент с монолитным ростверком — параметры") {
                HStack(alignment: .top, spacing: 20) {
                    GrillageSectionView(s: s).frame(width: 300, height: 320)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(s.type.title): \(s.positions.count) шт., Ø\(Int(s.d * 1000)) мм\(s.type != .bored ? " (\(s.type == .screw ? "лопасть" : "уширение") Ø\(Int(s.D * 1000)))" : ""), длина \(fmt(s.L)) м")
                        Text("Несущая способность Fd = \(fmt(s.Fd, 1)) кН, допускаемая Fd/1.4 = \(fmt(s.Nallow, 1)) кН (\(fmt(s.Nallow / 9.81, 2)) т)")
                        Text("Макс. нагрузка на сваю N = \(fmt(s.Nmax, 1)) кН")
                        Text("Ростверк \(Int(s.bg * 1000))×\(Int(s.hg * 1000)) мм: низ \(s.botN)Ø\(s.botD), верх \(s.topN)Ø\(s.topD), хомуты Ø\(s.stirD) шаг \(Int(s.stirStep * 1000))")
                        if s.type != .screw { Text("Каркас сваи: \(s.cageN)Ø\(s.cageD) \(p.rebar.rawValue) + хомуты Ø6 шаг 400") }
                        Divider()
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
                            GridRow { Text("Участок").bold(); Text("L, м").bold(); Text("qр, кН/м").bold(); Text("Пролётов").bold(); Text("Шаг, м").bold() }
                            ForEach(s.lines, id: \.line.id) { l in
                                GridRow { Text(l.line.name); Text(fmt(l.line.length)); Text(fmt(l.qd, 1)); Text("\(l.n)"); Text(fmt(l.spacing)) }
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }
                    }
                    .font(.callout)
                }
                .padding(6)
            }
            checks(s.checks)
            spec(s.rebar, extra: [("Бетон сваи", "\(fmt(s.concrete, 2)) м³"),
                                  ("Бетон ростверка \(p.concrete.title)", "\(fmt(s.grillageConcrete, 2)) м³"),
                                  ("Опалубка ростверка", "\(fmt(s.formwork, 1)) м²")])
            notes(s.notes)
        }
    }
}

// MARK: - Чертежи сечений

private func dimText(_ ctx: GraphicsContext, _ s: String, _ at: CGPoint, _ anchor: UnitPoint = .center) {
    ctx.draw(Text(s).font(.system(size: 10)), at: at, anchor: anchor)
}

struct StripSectionView: View {
    let sec: StripSection
    let depth: Double
    var body: some View {
        Canvas { ctx, size in
            let pad = 36.0
            let sc = min((size.width - 2 * pad) / max(sec.b, 0.3), (size.height - 2 * pad) / sec.H)
            let cx = size.width / 2, top = pad
            func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: cx + x * sc, y: top + y * sc) } // y — вниз от верха
            var shape = Path()
            if sec.isT {
                let sw = sec.stemW / 2, b = sec.b / 2, hs = sec.H - sec.soleH
                shape.addLines([P(-sw, 0), P(sw, 0), P(sw, hs), P(b, hs), P(b, sec.H), P(-b, sec.H), P(-b, hs), P(-sw, hs)])
            } else {
                shape.addLines([P(-sec.b / 2, 0), P(sec.b / 2, 0), P(sec.b / 2, sec.H), P(-sec.b / 2, sec.H)])
            }
            shape.closeSubpath()
            ctx.fill(shape, with: .color(.gray.opacity(0.25)))
            ctx.stroke(shape, with: .color(.primary), lineWidth: 1.2)
            // уровень земли
            let gy = sec.H - depth
            var g = Path(); g.move(to: P(-sec.b / 2 - 0.15, gy)); g.addLine(to: P(sec.b / 2 + 0.15, gy))
            ctx.stroke(g, with: .color(.green), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
            dimText(ctx, "±0.000", P(sec.b / 2 + 0.02, gy - 0.03), .bottomLeading)
            // хомут
            let c = sec.cover
            var cl = Path()
            cl.addRect(CGRect(x: P(-sec.stemW / 2 + c, 0).x, y: P(0, c).y, width: (sec.stemW - 2 * c) * sc, height: (sec.H - 2 * c) * sc))
            ctx.stroke(cl, with: .color(.orange), lineWidth: 1.2)
            if sec.isT && sec.soleD > 0 {
                var sb = Path(); sb.move(to: P(-sec.b / 2 + c, sec.H - c - 0.012)); sb.addLine(to: P(sec.b / 2 - c, sec.H - c - 0.012))
                ctx.stroke(sb, with: .color(.orange), lineWidth: 1.2)
            }
            func dots(_ n: Int, _ d: Int, _ w: Double, _ y: Double) {
                let r = max(Double(d) / 2000 * sc, 2.5)
                for i in 0..<n {
                    let x = n == 1 ? 0 : -w / 2 + c + Double(i) * (w - 2 * c) / Double(n - 1)
                    let pt = P(x, y)
                    ctx.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: 2 * r, height: 2 * r)), with: .color(.red))
                }
            }
            dots(sec.topN, sec.topD, sec.stemW, c)
            dots(sec.botN, sec.botD, sec.b, sec.H - c)
            if sec.sideRows > 0 {
                for k in 1...sec.sideRows { dots(2, sec.sideD, sec.stemW, c + (sec.H - 2 * c) * Double(k) / Double(sec.sideRows + 1)) }
            }
            dimText(ctx, "\(Int(sec.b * 1000))", P(0, sec.H + 0.06))
            dimText(ctx, "H=\(Int(sec.H * 1000))", P(-sec.b / 2 - 0.04, sec.H / 2), .trailing)
            dimText(ctx, "\(sec.topN)Ø\(sec.topD)", P(sec.stemW / 2 + 0.03, c), .leading)
            dimText(ctx, "\(sec.botN)Ø\(sec.botD)", P(sec.b / 2 + 0.03, sec.H - c), .leading)
            dimText(ctx, "Ø\(sec.clampD) шаг \(Int(sec.clampStep * 1000))", P(0, -0.05), .bottom)
        }
    }
}

struct SlabSectionView: View {
    let s: SlabResult
    var body: some View {
        Canvas { ctx, size in
            let w = 1.4, h = s.t
            let sc = min((size.width - 90) / w, (size.height - 80) / max(h, 0.15) * 0.5)
            let x0 = 16.0, y0 = size.height / 2
            func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x0 + x * sc, y: y0 + y * sc) }
            var slab = Path(); slab.addRect(CGRect(origin: P(0, 0), size: CGSize(width: w * sc, height: h * sc)))
            ctx.fill(slab, with: .color(.gray.opacity(0.25))); ctx.stroke(slab, with: .color(.primary), lineWidth: 1.2)
            var cush = Path(); cush.addRect(CGRect(origin: P(0, h), size: CGSize(width: w * sc, height: 0.12 * sc)))
            ctx.fill(cush, with: .color(.yellow.opacity(0.3)))
            var wall = Path(); wall.addRect(CGRect(origin: P(0.15, -0.45), size: CGSize(width: 0.3 * sc, height: 0.45 * sc)))
            ctx.fill(wall, with: .color(.orange.opacity(0.35))); ctx.stroke(wall, with: .color(.primary), lineWidth: 0.8)
            let r = max(Double(s.d) / 2000 * sc, 2)
            for yy in [s.cover, h - s.cover] {
                var line = Path(); line.move(to: P(s.cover, yy)); line.addLine(to: P(w - 0.02, yy))
                ctx.stroke(line, with: .color(.red), lineWidth: max(r * 0.8, 1.5))
                var x = s.cover
                while x < w {
                    let pt = P(x, yy + (yy < h / 2 ? Double(s.d) / 1000 : -Double(s.d) / 1000))
                    ctx.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: 2 * r, height: 2 * r)), with: .color(.red))
                    x += s.step
                }
            }
            var u = Path()
            u.move(to: P(0.25, s.cover)); u.addLine(to: P(s.cover, s.cover)); u.addLine(to: P(s.cover, h - s.cover)); u.addLine(to: P(0.25, h - s.cover))
            ctx.stroke(u, with: .color(.orange), lineWidth: 1.5)
            dimText(ctx, "t = \(Int(s.t * 1000))", P(w + 0.02, h / 2), .leading)
            dimText(ctx, "Ø\(s.d) шаг \(Int(s.step * 1000)) — верх и низ, в двух направлениях", P(w / 2, h + 0.25))
            dimText(ctx, "стена", P(0.3, -0.5), .bottom)
            dimText(ctx, "подушка", P(w / 2, h + 0.06))
        }
    }
}

struct GrillageSectionView: View {
    let s: PileResult
    var body: some View {
        Canvas { ctx, size in
            let total = s.hg + 0.15 + min(s.L, 3.0)
            let sc = min((size.width - 100) / max(s.bg, s.D, 0.3), (size.height - 30) / total)
            let cx = size.width / 2, y0 = 15.0
            func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: cx + x * sc, y: y0 + y * sc) }
            var g = Path(); g.addRect(CGRect(origin: P(-s.bg / 2, 0), size: CGSize(width: s.bg * sc, height: s.hg * sc)))
            ctx.fill(g, with: .color(.gray.opacity(0.25))); ctx.stroke(g, with: .color(.primary), lineWidth: 1.2)
            let c = s.cover
            var st = Path(); st.addRect(CGRect(origin: P(-s.bg / 2 + c, c), size: CGSize(width: (s.bg - 2 * c) * sc, height: (s.hg - 2 * c) * sc)))
            ctx.stroke(st, with: .color(.orange), lineWidth: 1.2)
            func dots(_ n: Int, _ d: Int, _ y: Double) {
                let r = max(Double(d) / 2000 * sc, 2.5)
                for i in 0..<n {
                    let x = -s.bg / 2 + c + Double(i) * (s.bg - 2 * c) / Double(max(n - 1, 1))
                    let pt = P(x, y)
                    ctx.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: 2 * r, height: 2 * r)), with: .color(.red))
                }
            }
            dots(s.topN, s.topD, c); dots(s.botN, s.botD, s.hg - c)
            // зазор и земля
            let gy = s.hg + 0.15
            var gl = Path(); gl.move(to: P(-0.5, gy)); gl.addLine(to: P(0.5, gy))
            ctx.stroke(gl, with: .color(.green), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
            let shown = min(s.L, 3.0)
            var pile = Path(); pile.addRect(CGRect(origin: P(-s.d / 2, s.hg - 0.05), size: CGSize(width: s.d * sc, height: (shown + 0.2) * sc)))
            ctx.fill(pile, with: .color(s.type == .screw ? .blue.opacity(0.25) : .gray.opacity(0.35)))
            ctx.stroke(pile, with: .color(.primary), lineWidth: 1)
            if s.type != .bored {
                let by = s.hg + 0.15 + shown - (s.type == .screw ? 0.25 : 0.15)
                var bl = Path()
                if s.type == .screw { bl.move(to: P(-s.D / 2, by)); bl.addLine(to: P(s.D / 2, by)); ctx.stroke(bl, with: .color(.blue), lineWidth: 3) }
                else { bl.addEllipse(in: CGRect(origin: P(-s.D / 2, by - s.D * 0.3), size: CGSize(width: s.D * sc, height: s.D * 0.6 * sc))); ctx.fill(bl, with: .color(.gray.opacity(0.35))) }
            }
            dimText(ctx, "\(Int(s.bg * 1000))×\(Int(s.hg * 1000))", P(s.bg / 2 + 0.03, s.hg / 2), .leading)
            dimText(ctx, "\(s.topN)Ø\(s.topD) / \(s.botN)Ø\(s.botD)", P(-s.bg / 2 - 0.03, s.hg / 2), .trailing)
            dimText(ctx, "зазор 150", P(s.d / 2 + 0.05, s.hg + 0.08), .leading)
            dimText(ctx, "L = \(fmt(s.L)) м", P(s.d / 2 + 0.05, s.hg + 0.15 + shown / 2), .leading)
        }
    }
}
