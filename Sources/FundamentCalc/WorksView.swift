import SwiftUI

struct WorksView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var p: Project

    var body: some View {
        let w = Works.plan(p, model.results)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    GroupBox("Кратко: \(p.selectedFoundation.title.lowercased()) фундамент") {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                            ForEach(w.summary, id: \.0) { k, v in
                                GridRow {
                                    Text(k).foregroundStyle(.secondary)
                                    Text(v).bold()
                                }
                            }
                        }
                        .padding(6)
                    }
                    .frame(width: 330)
                    GroupBox("Схема разбивки: обноска, шнуры, маяки") {
                        LayoutSchemeView(scheme: w.scheme, kind: p.selectedFoundation)
                            .frame(height: 300)
                    }
                }
                ForEach(Array(w.sections.enumerated()), id: \.element.id) { i, s in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(s.steps.enumerated()), id: \.offset) { k, st in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(k + 1).").monospacedDigit().foregroundStyle(.secondary).frame(width: 20, alignment: .trailing)
                                    Text(st).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            if !s.items.isEmpty {
                                Divider()
                                itemsGrid(s.items)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                    } label: {
                        Label("\(i + 1). \(s.title)", systemImage: s.icon).font(.headline)
                    }
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Материалы на фундамент, отмостку и дренаж:")
                            Text("≈ " + rub(w.purchase.reduce(0) { $0 + $1.cost })).font(.title2.bold()).foregroundStyle(Color.accentColor)
                        }
                        Text(Price.note).font(.caption).foregroundStyle(.secondary)
                        itemsGrid(w.purchase)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                } label: {
                    Label("Ведомость закупки и стоимость", systemImage: "cart").font(.headline)
                }
                Text("Количества ориентировочные, с учётом типового запаса (доска +5 %, арматура +5 %, бетон +3 %). Нормы допусков — СП 70.13330.2012 «Несущие и ограждающие конструкции».")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: 1000, alignment: .leading)
        }
    }

    func itemsGrid(_ items: [WorkItem], total: Bool = true) -> some View {
        let sum = items.reduce(0) { $0 + $1.cost }
        return Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
            ForEach(items) { it in
                GridRow {
                    Text(it.name)
                    Text(fmt(it.qty, it.digits)).bold().monospacedDigit().gridColumnAlignment(.trailing)
                    Text(it.unit).foregroundStyle(.secondary)
                    Text(it.price > 0 ? rub(it.cost) : "—").monospacedDigit().gridColumnAlignment(.trailing)
                    Text(it.note).foregroundStyle(.secondary)
                }
            }
            if total && sum > 0 {
                Divider()
                GridRow {
                    Text("Итого").bold()
                    Text(""); Text("")
                    Text(rub(sum)).bold().monospacedDigit()
                    Text("")
                }
            }
        }
    }
}

struct LayoutSchemeView: View {
    let scheme: LayoutScheme
    let kind: FoundationKind

    var body: some View {
        Canvas { ctx, size in
            let pts = scheme.obnoska
            guard !pts.isEmpty else { return }
            let (lo, hi) = Geo.bbox([pts])
            let pad = 26.0
            let sc = min((size.width - 2 * pad) / (hi.x - lo.x), (size.height - 2 * pad) / (hi.y - lo.y))
            let ox = (size.width - (hi.x - lo.x) * sc) / 2, oy = (size.height + (hi.y - lo.y) * sc) / 2
            func P(_ v: V2) -> CGPoint { CGPoint(x: ox + (v.x - lo.x) * sc, y: oy - (v.y - lo.y) * sc) }

            // площадка
            var site = Path()
            site.addRect(CGRect(origin: P(V2(scheme.site.lo.x, scheme.site.hi.y)), size: CGSize(width: (scheme.site.hi.x - scheme.site.lo.x) * sc, height: (scheme.site.hi.y - scheme.site.lo.y) * sc)))
            ctx.fill(site, with: .color(.brown.opacity(0.08)))
            ctx.stroke(site, with: .color(.brown.opacity(0.4)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            // фундамент
            for (a, b, wd) in scheme.footprint {
                var l = Path(); l.move(to: P(a)); l.addLine(to: P(b))
                ctx.stroke(l, with: .color(.gray.opacity(0.45)), style: StrokeStyle(lineWidth: wd * sc, lineCap: .square))
            }
            if !scheme.slab.isEmpty {
                var s = Path()
                for r in scheme.slab { s.addLines(r.map(P)); s.closeSubpath() }
                ctx.fill(s, with: .color(.gray.opacity(0.35)), style: FillStyle(eoFill: true))
            }
            for pl in scheme.piles {
                let c = P(pl)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)), with: .color(.black))
            }
            // шнуры
            for (a, b) in scheme.strings {
                var l = Path(); l.move(to: P(a)); l.addLine(to: P(b))
                ctx.stroke(l, with: .color(.red.opacity(0.7)), style: StrokeStyle(lineWidth: 0.8, dash: [6, 3]))
            }
            // обноска
            var ob = Path(); ob.addLines(pts.map(P)); ob.closeSubpath()
            ctx.stroke(ob, with: .color(.orange), lineWidth: 2.5)
            for post in scheme.posts {
                let c = P(post)
                ctx.fill(Path(CGRect(x: c.x - 2.5, y: c.y - 2.5, width: 5, height: 5)), with: .color(.brown))
            }
            // маяки
            for bcn in scheme.beacons {
                let c = P(bcn)
                var t = Path()
                t.move(to: CGPoint(x: c.x, y: c.y - 4)); t.addLine(to: CGPoint(x: c.x + 3.5, y: c.y + 2.5)); t.addLine(to: CGPoint(x: c.x - 3.5, y: c.y + 2.5)); t.closeSubpath()
                ctx.fill(t, with: .color(.blue))
            }
            // легенда
            let items: [(Color, String)] = [(.orange, "обноска"), (.red, "шнуры по граням"), (.blue, kind == .slab ? "маяки (сетка 1.5 м)" : "метки верха"), (.brown, "столбики")]
            var x = 8.0
            for (c, t) in items {
                ctx.fill(Path(CGRect(x: x, y: 6, width: 10, height: 10)), with: .color(c))
                let txt = ctx.resolve(Text(t).font(.system(size: 10)))
                ctx.draw(txt, at: CGPoint(x: x + 14, y: 11), anchor: .leading)
                x += 28 + Double(txt.measure(in: size).width)
            }
        }
    }
}
