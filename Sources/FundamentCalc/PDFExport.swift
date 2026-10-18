import AppKit
import SceneKit
import Metal
import UniformTypeIdentifiers

/// Простая вёрстка A4 поверх CGContext PDF (координаты — сверху вниз)
final class PDFWriter {
    let data = NSMutableData()
    let ctx: CGContext
    let W: CGFloat = 595, H: CGFloat = 842, M: CGFloat = 40
    var y: CGFloat = 0
    var page = 0
    var open = false
    var header = ""

    init() {
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        let consumer = CGDataConsumer(data: data as CFMutableData)!
        ctx = CGContext(consumer: consumer, mediaBox: &box, [kCGPDFContextCreator as String: "Расчёт фундамента — проект дома"] as CFDictionary)!
    }

    var contentW: CGFloat { W - 2 * M }
    var bottom: CGFloat { H - M - 14 }

    func newPage() {
        if open { endPage() }
        ctx.beginPDFPage(nil)
        ctx.translateBy(x: 0, y: H)
        ctx.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        open = true
        page += 1
        y = M
        if page > 1 && !header.isEmpty {
            Sk.text(header, CGPoint(x: M, y: M - 16), size: 7, color: .gray)
            ctx.setStrokeColor(NSColor(white: 0.8, alpha: 1).cgColor); ctx.setLineWidth(0.5)
            ctx.move(to: CGPoint(x: M, y: M - 9)); ctx.addLine(to: CGPoint(x: W - M, y: M - 9)); ctx.strokePath()
        }
    }

    func endPage() {
        Sk.text("— \(page) —", CGPoint(x: W / 2, y: H - M / 2), size: 7, color: .gray, ax: 0.5)
        ctx.endPDFPage()
        open = false
    }

    func ensure(_ h: CGFloat) { if !open || y + h > bottom { newPage() } }

    func attr(_ s: String, size: CGFloat, bold: Bool = false, italic: Bool = false, color: NSColor = .black) -> NSAttributedString {
        var font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        if italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        let ps = NSMutableParagraphStyle(); ps.lineSpacing = 1.2
        return NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: ps])
    }

    func height(_ a: NSAttributedString, _ w: CGFloat) -> CGFloat {
        ceil(a.boundingRect(with: CGSize(width: w, height: 10000), options: [.usesLineFragmentOrigin]).height)
    }

    func text(_ s: String, size: CGFloat = 9, bold: Bool = false, italic: Bool = false, color: NSColor = .black, indent: CGFloat = 0, after: CGFloat = 4) {
        let a = attr(s, size: size, bold: bold, italic: italic, color: color)
        let w = contentW - indent
        let h = height(a, w)
        ensure(h)
        a.draw(with: CGRect(x: M + indent, y: y, width: w, height: h + 2), options: [.usesLineFragmentOrigin])
        y += h + after
    }

    func heading(_ s: String, level: Int = 1) {
        let size: CGFloat = level == 1 ? 15 : level == 2 ? 11.5 : 10
        ensure(size * 4)
        if level == 1 { y += 4 }
        text(s, size: size, bold: true, color: level == 1 ? NSColor(srgbRed: 0.1, green: 0.25, blue: 0.5, alpha: 1) : .black, after: level == 1 ? 6 : 3)
        if level == 1 {
            ctx.setStrokeColor(NSColor(srgbRed: 0.1, green: 0.25, blue: 0.5, alpha: 1).cgColor); ctx.setLineWidth(0.8)
            ctx.move(to: CGPoint(x: M, y: y - 2)); ctx.addLine(to: CGPoint(x: W - M, y: y - 2)); ctx.strokePath()
            y += 4
        }
    }

    func numbered(_ items: [String], size: CGFloat = 8.8) {
        for (i, s) in items.enumerated() {
            let a = attr(s, size: size)
            let h = height(a, contentW - 18)
            ensure(h + 2)
            Sk.text("\(i + 1).", CGPoint(x: M + 14, y: y), size: size, color: .darkGray, ax: 1, ay: 0)
            a.draw(with: CGRect(x: M + 18, y: y, width: contentW - 18, height: h + 2), options: [.usesLineFragmentOrigin])
            y += h + 3
        }
        y += 3
    }

    /// Таблица: widths — доли ширины
    func table(_ head: [String], _ rows: [[String]], widths: [CGFloat], size: CGFloat = 7.5, bold: Set<Int> = []) {
        let ws = widths.map { $0 * contentW }
        func rowH(_ cells: [String], _ b: Bool) -> CGFloat {
            zip(cells, ws).map { height(attr($0, size: size, bold: b), $1 - 6) }.max().map { $0 + 5 } ?? 12
        }
        func drawRow(_ cells: [String], b: Bool, bg: NSColor?) {
            let h = rowH(cells, b)
            if y + h > bottom { newPage(); drawRow(head, b: true, bg: NSColor(white: 0.9, alpha: 1)) }
            var x = M
            if let bg { ctx.setFillColor(bg.cgColor); ctx.fill(CGRect(x: M, y: y, width: contentW, height: h)) }
            for (c, w) in zip(cells, ws) {
                attr(c, size: size, bold: b).draw(with: CGRect(x: x + 3, y: y + 2.5, width: w - 6, height: h), options: [.usesLineFragmentOrigin])
                x += w
            }
            ctx.setStrokeColor(NSColor(white: 0.78, alpha: 1).cgColor); ctx.setLineWidth(0.4)
            ctx.move(to: CGPoint(x: M, y: y + h)); ctx.addLine(to: CGPoint(x: W - M, y: y + h)); ctx.strokePath()
            y += h
        }
        ensure(rowH(head, true) + rowH(rows.first ?? head, false) + 4)
        drawRow(head, b: true, bg: NSColor(white: 0.9, alpha: 1))
        for (i, r) in rows.enumerated() { drawRow(r, b: bold.contains(i), bg: i % 2 == 1 ? NSColor(white: 0.97, alpha: 1) : nil) }
        y += 8
    }

    func figure(_ caption: String, aspect: CGFloat, maxH: CGFloat = 330, draw: (CGContext, CGRect) -> Void) {
        let w = contentW
        let h = min(w * aspect, maxH)
        ensure(h + 18)
        let r = CGRect(x: M + (contentW - (h / aspect < w ? h / aspect : w)) / 2 * 0, y: y, width: w, height: h)
        draw(ctx, r)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        y += h + 2
        text(caption, size: 7.5, italic: true, color: .darkGray, after: 8)
    }

    func image(_ img: CGImage, height: CGFloat) {
        ensure(height + 6)
        let w = min(contentW, height * CGFloat(img.width) / CGFloat(img.height))
        let r = CGRect(x: M + (contentW - w) / 2, y: y, width: w, height: height)
        ctx.saveGState()
        ctx.translateBy(x: r.minX, y: r.maxY); ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(origin: .zero, size: r.size))
        ctx.restoreGState()
        y += height + 6
    }

    func finish() -> Data {
        if open { endPage() }
        ctx.closePDF()
        return data as Data
    }
}

enum PDFExport {
    /// 3D-вид этапа в JPEG (сохраняет DCT-сжатие в PDF)
    @MainActor
    static func render3D(_ p: Project, _ r: CalcResults, stage: Stage3D, size: CGSize = CGSize(width: 1200, height: 720)) -> CGImage? {
        let scene = SCNScene()
        scene.background.contents = NSColor(srgbRed: 0.86, green: 0.91, blue: 0.96, alpha: 1)
        var o = SceneOptions(); o.stage = stage; o.site = stage == .finish
        scene.rootNode.addChildNode(SceneBuilder.build(p, r, o))
        let amb = SCNNode(); amb.light = SCNLight(); amb.light!.type = .ambient; amb.light!.intensity = 350
        let sun = SCNNode(); sun.light = SCNLight(); sun.light!.type = .directional; sun.light!.intensity = 1100
        sun.eulerAngles = SCNVector3(-1.0, 0.7, 0)
        scene.rootNode.addChildNode(amb); scene.rootNode.addChildNode(sun)
        let cam = SCNNode(); cam.camera = SCNCamera(); cam.camera!.zNear = 0.05; cam.camera!.zFar = 500
        let (lo, hi) = Geo.bbox(p.rings)
        let c = (lo + hi) / 2, d = (max(hi.x - lo.x, hi.y - lo.y) * 0.95 + 5) * (stage == .finish ? 0.95 : 0.75)
        cam.position = SceneBuilder.v3(c + V2(d * 0.75, -d * 0.9), d * (stage <= .foundation ? 0.85 : 0.6))
        cam.look(at: SceneBuilder.v3(c, stage <= .foundation ? 0 : 1.5))
        scene.rootNode.addChildNode(cam)
        let rnd = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        rnd.scene = scene
        rnd.pointOfView = cam
        let img = rnd.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]),
              let prov = CGDataProvider(data: jpg as CFData) else { return nil }
        return CGImage(jpegDataProviderSource: prov, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    @MainActor
    static func make(_ p: Project, _ r: CalcResults, _ b: BuildPlan) -> Data {
        let w = PDFWriter()
        let ctx = Drawings.Ctx(p: p, r: r, b: b)
        let F = b.frame
        let area = r.loads.floorArea
        let city = p.cityIndex >= 0 && p.cityIndex < cities.count ? cities[p.cityIndex].name : "свои климатические данные"
        w.header = "Проект каркасного дома \(fmt(p.length, 1))×\(fmt(p.effW, 1)) м · \(p.floors) эт. · \(city)"

        // --- Титул ---
        w.newPage()
        w.y = 70
        w.text("Проект каркасного дома", size: 24, bold: true, color: NSColor(srgbRed: 0.1, green: 0.25, blue: 0.5, alpha: 1), after: 4)
        w.text("Пошаговая инструкция от подготовки участка до кровли: решения с обоснованием по действующим СП и ГОСТ, схемы узлов и монтажа, ведомости материалов для закупки.", size: 10.5, color: .darkGray, after: 14)
        if let img = render3D(p, r, stage: .finish) { w.image(img, height: 290) }
        w.table(["Параметр", "Значение"], [
            ["Дом", "\(p.shape.title), \(fmt(p.length, 1)) × \(fmt(p.effW, 1)) м по осям, площадь застройки \(fmt(area, 1)) м², этажей: \(p.floors), высота этажа \(fmt(p.floorHeight, 2)) м"],
            ["Стены", "каркас \(F.studExt.label) шаг \(Int(p.studStep * 1000)) мм, \(p.sheathing.title.lowercased()), утеплитель \(Int(b.woolWall * 1000)) мм, фасад: \(p.facade.title.lowercased())"],
            ["Фундамент", "\(p.selectedFoundation.title.lowercased()), бетон \(p.concrete.title), арматура \(p.rebar.rawValue)"],
            ["Кровля", p.roofType == .flat ? p.roofType.title : "\(p.roofType.title.lowercased()), \(p.covering.title.lowercased()), уклон \(Int(p.roofAngleEff))°, стропила \(F.rafter?.title ?? "—") шаг \(Int((F.rafter?.step ?? 0.6) * 1000))"],
            ["Климат", "\(city): снеговой район \(p.snowRegion.roman), Mt = \(fmt(p.mt, 0)), ГСОП = \(Int(b.gsop)) °C·сут"],
            ["Грунт", "\(p.soil.name), УГВ \(fmt(p.gwl, 1)) м"],
            ["Материалы (ориентир.)", "≈ \(rub(b.total)) — \(Price.note)"],
        ], widths: [0.22, 0.78], size: 8)
        let df = DateFormatter(); df.locale = Locale(identifier: "ru_RU"); df.dateStyle = .long; df.timeStyle = .short
        w.text("Сформировано \(df.string(from: Date())). Документ — предварительный проект для самостоятельного строительства. Расчёты выполнены по упрощённым моделям; характеристики грунтов — табличные. Перед строительством закажите инженерно-геологические изыскания и проверку проекта инженером. Статус нормативов проверен на октябрь 2026 г.; уточняйте актуальные редакции в ФГИС ФЦС.", size: 7.5, italic: true, color: .gray)

        // --- Содержание ---
        w.newPage()
        w.heading("Содержание")
        w.numbered(b.stages.map { $0.title } + ["Развёртки стен каркаса", "Ведомость пиломатериалов", "Сводная ведомость закупки", "Нормативные документы"], size: 10)
        w.heading("Ключевые решения", level: 2)
        let key = b.stages.flatMap { s in s.decisions.prefix(3).map { ["\(s.number). \($0.title)", $0.value, $0.ref] } }
        w.table(["Решение", "Принято", "Норматив"], key, widths: [0.3, 0.38, 0.32], size: 7.2)

        // --- Этапы ---
        var lastScene: Stage3D? = nil
        var shownWalls = Set<Int>()
        for s in b.stages {
            w.newPage()
            w.heading("Этап \(s.number). \(s.title)")
            w.text(s.goal, size: 9.5, italic: true, color: .darkGray, after: 6)
            if s.scene != lastScene, let img = render3D(p, r, stage: s.scene, size: CGSize(width: 1100, height: 560)) {
                w.image(img, height: 200)
                w.text("3D: этап «\(s.scene.title)»", size: 7.5, italic: true, color: .gray, after: 6)
                lastScene = s.scene
            }
            w.heading("Порядок работ", level: 2)
            w.numbered(s.steps)
            if !s.decisions.isEmpty {
                w.heading("Принятые решения и обоснование", level: 2)
                w.table(["Решение", "Принято", "Обоснование", "Норматив"], s.decisions.map { [$0.title, $0.value, $0.why, $0.ref] }, widths: [0.18, 0.25, 0.33, 0.24], size: 7.2)
            }
            if s.figures.contains(where: { if case .openingNode = $0.kind { return true }; return false }) {
                w.heading("Проёмы: стандартные блоки и перемычки", level: 2)
                w.table(["Стена", "Тип", "Проём в проекте", "Блок (стандарт)", "Черновой проём", "Перемычка"], b.openings.map { o in
                    [o.wall, o.opening.kind.title, "\(Drawings.mm(o.opening.width))×\(Drawings.mm(o.opening.height))" + (o.standard ? "" : " ⚠︎"),
                     o.block.name, "\(Drawings.mm(o.block.roW))×\(Drawings.mm(o.block.roH))", o.header.map { "\($0.title), σ = \(fmt($0.sigma, 1)) МПа" } ?? "—"]
                }, widths: [0.07, 0.11, 0.13, 0.4, 0.12, 0.17], size: 6.8)
            }
            for f in s.figures {
                if case .wallElevation(let i) = f.kind { shownWalls.insert(i) }
                w.figure(f.title, aspect: f.aspect) { cg, rect in Drawings.render(f.kind, ctx, cg, rect) }
            }
            let items = s.items.filter { $0.qty > 0 }
            if !items.isEmpty {
                w.heading("Материалы этапа", level: 2)
                let sum = items.reduce(0) { $0 + $1.cost }
                w.table(["Позиция (как спрашивать в магазине)", "Кол-во", "Ед.", "≈ ₽", "Примечание"],
                        items.map { [$0.name, fmt($0.qty, $0.digits), $0.unit, $0.price > 0 ? rub($0.cost) : "—", $0.note] } + [["Итого по этапу", "", "", rub(sum), ""]],
                        widths: [0.42, 0.08, 0.06, 0.11, 0.33], size: 7, bold: [items.count])
            }
        }

        // --- Развёртки ---
        w.newPage()
        w.heading("Развёртки стен каркаса")
        w.text("Вид изнутри помещения, размеры в мм. Цвета: обвязки — тёмные, стойки — светлые, перемычки — коричневые, проёмы — голубые.", size: 8.5, color: .darkGray)
        for (i, wf) in F.walls.enumerated() where !shownWalls.contains(i) {
            w.figure("\(wf.exterior ? "Наружная стена" : "Внутренняя стена") \(wf.name), этаж \(wf.storey + 1): длина \(Drawings.mm(wf.length)), высота каркаса \(Drawings.mm(wf.height)), стойки \(Lumber(50, Int((wf.depth * 1000).rounded())).label)", aspect: 0.4) { cg, rect in
                Drawings.render(.wallElevation(i), ctx, cg, rect)
            }
        }

        // --- Пиломатериалы ---
        w.newPage()
        w.heading("Ведомость пиломатериалов")
        w.text("Подсчитано по фактической раскладке всех элементов каркаса с раскроем на хлысты 6 м (+5 % на брак). Хвойные породы, 2 сорт по ГОСТ 8486-86, камерной сушки (влажность ≤ 20 %).", size: 8.5, color: .darkGray)
        w.table(["Сечение", "Назначение (кол-во элементов)", "Погонаж, м", "Хлыстов 6 м", "Объём, м³"],
                b.lumber.map { [$0.sec.label, $0.use, fmt($0.totalLength, 0), "\($0.pieces)", fmt($0.volume, 2)] }
                + [["Итого", "", fmt(b.lumber.reduce(0) { $0 + $1.totalLength }, 0), "\(b.lumber.reduce(0) { $0 + $1.pieces })", fmt(b.lumber.reduce(0) { $0 + $1.volume }, 2)]],
                widths: [0.1, 0.5, 0.13, 0.13, 0.14], size: 7.5, bold: [b.lumber.count])

        // --- Закупка ---
        w.heading("Сводная ведомость закупки")
        w.text(Price.note, size: 8, color: .darkGray)
        for g in b.groups {
            w.heading("\(g.title) — ≈ \(rub(g.items.reduce(0) { $0 + $1.cost }))", level: 3)
            w.table(["Позиция", "Кол-во", "Ед.", "≈ ₽", "Примечание"], g.items.map { [$0.name, fmt($0.qty, $0.digits), $0.unit, $0.price > 0 ? rub($0.cost) : "—", $0.note] },
                    widths: [0.47, 0.08, 0.07, 0.11, 0.27], size: 7)
        }
        w.text("Итого материалы: ≈ \(rub(b.total)). Работа, доставка (кроме бетона), инструмент, инженерные системы и чистовая отделка не учтены.", size: 9.5, bold: true)

        // --- Нормативы ---
        w.newPage()
        w.heading("Нормативные документы")
        w.text("Решения в проекте обоснованы следующими документами. Статус проверен по открытым реестрам на октябрь 2026 г.", size: 8.5, color: .darkGray)
        w.table(["Обозначение", "Наименование", "Статус"], N.all.map { [$0.code, $0.title, $0.status] }, widths: [0.22, 0.6, 0.18], size: 7.5)
        w.text("Важно: СП 352.1325800.2017 и СП 64.13330.2017 — основные документы для деревянного каркаса; СП 31-105-2002 носит рекомендательный характер. Нормы обязательного применения определяются перечнем по ПП РФ № 815 от 28.05.2021 (в ред. на дату строительства).", size: 7.5, italic: true, color: .gray)
        return w.finish()
    }

    @MainActor
    static func save(_ data: Data, suggested: String = "Проект дома.pdf") {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = suggested
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url)
        NSWorkspace.shared.open(url)
    }
}
