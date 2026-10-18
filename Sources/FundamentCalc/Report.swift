import AppKit
import UniformTypeIdentifiers

enum Report {
    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    static func table(_ head: [String], _ rows: [[String]]) -> String {
        var s = "<table><tr>"
        for c in head { s += "<th>\(esc(c))</th>" }
        s += "</tr>"
        for row in rows {
            s += "<tr>"
            for c in row { s += "<td>\(esc(c))</td>" }
            s += "</tr>"
        }
        return s + "</table>"
    }

    static func checks(_ c: [Check]) -> String {
        table(["", "Проверка", "Результат", "Норматив"], c.map { [$0.ok ? "✔" : "✘", $0.title, $0.value, $0.ref] })
    }

    static func rebar(_ items: [RebarItem]) -> String {
        var rows = items.enumerated().map { i, it in ["\(i + 1)", it.name, "Ø\(it.d) \(it.cls)", it.spec, fmt(it.length, 0), fmt(it.mass, 1)] }
        for (d, its) in Dictionary(grouping: items, by: \.d).sorted(by: { $0.key < $1.key }) {
            rows.append(["", "Итого Ø\(d)", "", "", fmt(its.reduce(0) { $0 + $1.length }, 0), fmt(its.reduce(0) { $0 + $1.mass }, 1)])
        }
        rows.append(["", "Всего", "", "", "", fmt(items.reduce(0) { $0 + $1.mass }, 0)])
        return table(["Поз.", "Элемент", "Ø, класс", "Примечание", "Длина, м", "Масса, кг"], rows)
    }

    static func html(_ p: Project, _ r: CalcResults) -> String {
        let L = r.loads
        var h = """
        <!doctype html><html lang="ru"><head><meta charset="utf-8"><title>Расчёт фундамента</title>
        <style>body{font-family:-apple-system,Helvetica,sans-serif;margin:32px;max-width:1000px;color:#222}
        table{border-collapse:collapse;margin:8px 0 18px;font-size:13px}td,th{border:1px solid #ccc;padding:4px 8px;text-align:left}
        th{background:#f2f2f2}h1{font-size:22px}h2{font-size:18px;margin-top:28px;border-bottom:1px solid #ddd}.note{color:#666;font-size:12px}</style></head><body>
        <h1>Расчёт фундамента</h1>
        <p class="note">Сформировано \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)). Предварительный расчёт по СП 20.13330.2016, СП 22.13330.2016, СП 24.13330.2021, СП 63.13330.2018.</p>
        <h2>Исходные данные</h2>
        """
        h += table(["Параметр", "Значение"], [
            ["Форма дома", "\(p.shape.title), \(fmt(p.length, 1)) × \(fmt(p.effW, 1)) м, площадь \(fmt(L.floorArea, 1)) м²"],
            ["Этажность", "\(p.floors) эт., высота этажа \(fmt(p.floorHeight)) м"],
            ["Каркас стен", p.usedMaterials.map { "\($0.title) \(Int(p.thickness($0) * 1000)) мм" }.joined(separator: "; ")],
            ["Перекрытия", "\(p.floorType.title); пол 1-го этажа: \(p.groundFloor.title)"],
            ["Фасад", p.facade.title],
            ["Кровля", p.roofType == .flat ? "\(p.roofType.title): \(p.flatSlab.title)" : "\(p.roofType.title), \(p.covering.title), уклон \(Int(p.roofAngleEff))°, свес \(fmt(p.overhang, 1)) м"],
            ["Снеговой район", "\(p.snowRegion.title), S = \(fmt(L.snowS)) кПа"],
            ["Грунт", "\(p.soil.name): γ = \(fmt(p.soil.gamma, 1)) кН/м³, φ = \(Int(p.soil.phi))°, c = \(Int(p.soil.c)) кПа, E = \(Int(p.soil.E)) МПа, \(p.soil.heave.title.lowercased())"],
            ["Промерзание", "Mt = \(fmt(p.mt, 1)), dfn = \(fmt(r.strip.dfn)) м, df = \(fmt(r.strip.df)) м; УГВ \(fmt(p.gwl, 1)) м"],
        ])
        h += "<h2>Нагрузки на фундамент</h2>"
        h += table(["Стена", "Материал", "L, м", "Стена", "Перекр.", "Кровля", "Снег", "Полезн.", "qн, кН/м", "qр, кН/м"],
                   L.lines.enumerated().map { i, ln in
                       let q = L.stripLoads[i]
                       return [ln.name, ln.material.short, fmt(ln.length), fmt(q.wall, 1), fmt(q.floors, 1), fmt(q.roof, 1), fmt(q.snow, 1), fmt(q.live, 1), fmt(q.char, 1), fmt(q.design, 1)]
                   })
        h += "<p>Итого нормативная нагрузка: \(fmt(L.summary.total, 0)) кН (\(fmt(L.summary.total / 9.81, 1)) т).</p>"
        let wr = Weights.make(p, r)
        h += "<h2>Вес дома и несущая способность фундамента</h2>"
        var wrows = wr.structure.map { [$0.name, fmt($0.t, 2), $0.note] }
        wrows.append(["Снег на кровле (зимой)", fmt(wr.snow / 9.81, 2), "по снеговому району"])
        wrows += wr.contents.map { [$0.name, fmt($0.t, 2), $0.note] }
        wrows.append(["Итого дом зимой", fmt(wr.winter / 9.81, 1), ""])
        wrows.append(["Собственный вес фундамента", fmt(wr.foundationSelf / 9.81, 1), ""])
        wrows.append(["Фундамент выдержит", fmt(wr.capacity / 9.81, 1), wr.basis])
        wrows.append(["Запас", "×" + fmt(wr.reserve, 1), wr.local])
        h += table(["Позиция", "т", "Примечание"], wrows)
        let dr = Drainage.make(p, r)
        h += "<h2>Отмостка и дренаж (обязательные требования)</h2>"
        h += table(["Требование", "Значение", "Норматив"], dr.requirements.map { [$0.title, $0.value, $0.ref] })
        h += "<h2>Сравнение вариантов</h2>"
        h += table(["Вариант", "Размеры", "Бетон, м³", "Арматура, кг", "Проверки"], [
            ["Ленточный", r.strip.ext.map { "b = \(Int($0.b * 1000)), H = \(Int($0.H * 1000)) мм" } ?? "—", fmt(r.strip.concrete, 2), fmt(r.strip.steel, 0), r.strip.ok ? "OK" : "не проходит"],
            ["Плита", "t = \(Int(r.slab.t * 1000)) мм", fmt(r.slab.concrete, 2), fmt(r.slab.steel, 0), r.slab.ok ? "OK" : "не проходит"],
            ["Сваи", "\(r.piles.positions.count) × Ø\(Int(r.piles.d * 1000)), L = \(fmt(r.piles.L)) м", fmt(r.piles.concrete + r.piles.grillageConcrete, 2), fmt(r.piles.steel, 0), r.piles.ok ? "OK" : "не проходит"],
        ])
        switch p.selectedFoundation {
        case .strip:
            let s = r.strip
            h += "<h2>Ленточный фундамент</h2><p>d = \(fmt(s.depth)) м, H = \(fmt(s.H)) м, бетон \(p.concrete.title), арматура \(p.rebar.rawValue), нахлёст \(Int(s.lap * 1000)) мм.</p>"
            for (t, sec0) in [("Наружные стены", s.ext), ("Несущие перегородки", s.int)] {
                guard let sec = sec0 else { continue }
                h += "<p><b>\(t):</b> b = \(Int(sec.b * 1000)) мм\(sec.isT ? " (тавр, стенка \(Int(sec.stemW * 1000)), подошва \(Int(sec.soleH * 1000)))" : ""), низ \(sec.botN)Ø\(sec.botD), верх \(sec.topN)Ø\(sec.topD), хомуты Ø\(sec.clampD) шаг \(Int(sec.clampStep * 1000)) мм.</p>"
            }
            h += checks(s.checks) + rebar(s.rebar)
            h += "<p>Бетон: \(fmt(s.concrete, 2)) м³; подготовка: \(fmt(s.prep, 2)) м³; песок: \(fmt(s.sand, 2)) м³; опалубка: \(fmt(s.formwork, 1)) м².</p>"
            h += "<ul>" + s.notes.map { "<li>\(esc($0))</li>" }.joined() + "</ul>"
        case .slab:
            let s = r.slab
            h += "<h2>Фундаментная плита</h2><p>t = \(Int(s.t * 1000)) мм, сетки Ø\(s.d) шаг \(Int(s.step * 1000)) верх/низ, площадь \(fmt(s.area, 1)) м².</p>"
            h += checks(s.checks) + rebar(s.rebar)
            h += "<p>Бетон: \(fmt(s.concrete, 2)) м³; песок: \(fmt(s.sand, 1)) м³; ЭППС: \(fmt(s.eps, 1)) м².</p>"
            h += "<ul>" + s.notes.map { "<li>\(esc($0))</li>" }.joined() + "</ul>"
        case .piles:
            let s = r.piles
            h += "<h2>Свайный фундамент</h2><p>\(s.type.title): \(s.positions.count) шт., Ø\(Int(s.d * 1000)) мм, L = \(fmt(s.L)) м; Fd = \(fmt(s.Fd, 1)) кН. Ростверк \(Int(s.bg * 1000))×\(Int(s.hg * 1000)) мм.</p>"
            h += checks(s.checks) + rebar(s.rebar)
            h += "<ul>" + s.notes.map { "<li>\(esc($0))</li>" }.joined() + "</ul>"
        }
        let w = Works.plan(p, r)
        h += "<h2>Производство работ</h2>"
        for (i, sec) in w.sections.enumerated() {
            h += "<h3>\(i + 1). \(esc(sec.title))</h3><ol>" + sec.steps.map { "<li>\(esc($0))</li>" }.joined() + "</ol>"
            if !sec.items.isEmpty { h += table(["Позиция", "Кол-во", "Ед.", "Стоимость", "Примечание"], sec.items.map { [$0.name, fmt($0.qty, $0.digits), $0.unit, $0.price > 0 ? rub($0.cost) : "—", $0.note] }) }
        }
        h += "<h2>Ведомость закупки и стоимость</h2>" + table(["Позиция", "Кол-во", "Ед.", "Стоимость", "Примечание"], w.purchase.map { [$0.name, fmt($0.qty, $0.digits), $0.unit, $0.price > 0 ? rub($0.cost) : "—", $0.note] })
        h += "<p><b>Итого материалы: ≈ \(rub(w.purchase.reduce(0) { $0 + $1.cost }))</b>. \(Price.note)</p>"
        h += "<p class=\"note\">Расчёт предварительный, характеристики грунтов — табличные. Для строительства необходимы инженерно-геологические изыскания и проверка проектировщиком.</p></body></html>"
        return h
    }

    static func export(_ p: Project, _ r: CalcResults) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = "Расчёт фундамента.html"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? html(p, r).write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(url)
    }
}
