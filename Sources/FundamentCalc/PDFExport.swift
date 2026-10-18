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
        ctx = CGContext(consumer: consumer, mediaBox: &box, [kCGPDFContextCreator as String: "Дом своими руками — проект каркасного дома"] as CFDictionary)!
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

    /// Сетка 3D-кадров по шагам: номер, заголовок и пояснение под каждым кадром
    func imageGrid(_ cells: [(img: CGImage, title: String, note: String)], cols: Int = 2) {
        let gap: CGFloat = 10
        let cw = (contentW - gap * CGFloat(cols - 1)) / CGFloat(cols)
        for row in stride(from: 0, to: cells.count, by: cols) {
            let rowCells = Array(cells[row..<min(row + cols, cells.count)])
            let caps = rowCells.map { c -> NSAttributedString in
                let a = NSMutableAttributedString(attributedString: attr(c.title, size: 7.6, bold: true))
                a.append(attr("\n" + c.note, size: 6.8, color: .darkGray))
                return a
            }
            let ih = cw * 0.6
            let ch = caps.map { height($0, cw) }.max() ?? 0
            ensure(ih + ch + 10)
            for (k, c) in rowCells.enumerated() {
                let x = M + CGFloat(k) * (cw + gap)
                let r = CGRect(x: x, y: y, width: cw, height: ih)
                ctx.saveGState()
                ctx.translateBy(x: r.minX, y: r.maxY); ctx.scaleBy(x: 1, y: -1)
                ctx.draw(c.img, in: CGRect(origin: .zero, size: r.size))
                ctx.restoreGState()
                ctx.setStrokeColor(NSColor(white: 0.8, alpha: 1).cgColor); ctx.setLineWidth(0.5); ctx.stroke(r)
                caps[k].draw(with: CGRect(x: x, y: y + ih + 3, width: cw, height: ch + 2), options: [.usesLineFragmentOrigin])
            }
            y += ih + ch + 10
        }
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
    static func render3D(_ p: Project, _ r: CalcResults, stage: Stage3D, sub: Int = Int.max, size: CGSize = CGSize(width: 1200, height: 720)) -> CGImage? {
        let scene = SCNScene()
        scene.background.contents = NSColor(srgbRed: 0.86, green: 0.91, blue: 0.96, alpha: 1)
        var o = SceneOptions(); o.stage = stage; o.sub = sub; o.site = stage == .finish
        scene.rootNode.addChildNode(SceneBuilder.build(p, r, o))
        let amb = SCNNode(); amb.light = SCNLight(); amb.light!.type = .ambient; amb.light!.intensity = 350
        let sun = SCNNode(); sun.light = SCNLight(); sun.light!.type = .directional; sun.light!.intensity = 1100
        sun.eulerAngles = SCNVector3(-1.0, 0.7, 0)
        scene.rootNode.addChildNode(amb); scene.rootNode.addChildNode(sun)
        let cam = SCNNode(); cam.camera = SCNCamera(); cam.camera!.zNear = 0.05; cam.camera!.zFar = 500
        let (lo, hi) = Geo.bbox(p.rings)
        let c = (lo + hi) / 2, d = (max(hi.x - lo.x, hi.y - lo.y) * 0.95 + 5) * (stage == .finish ? 0.95 : stage.isInterior ? 0.6 : 0.75)
        // внутренние работы — сверху, через полупрозрачную кровлю
        cam.position = SceneBuilder.v3(c + V2(d * 0.75, -d * 0.9), d * (stage <= .backfill ? 0.85 : stage.isInterior ? 1.25 : 0.6))
        cam.look(at: SceneBuilder.v3(c, stage <= .backfill ? 0 : 1.5))
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
            ["Стены", "каркас \(F.studExt.label)\(p.modular ? "×3000 (целые доски), высота каркаса 3150" : "") шаг \(Int(p.studStep * 1000)) мм, \(p.sheathing.title.lowercased()), утеплитель \(Int(b.woolWall * 1000)) мм, фасад: \(p.facade.title.lowercased())"],
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
        w.numbered(["Порядок строительства", "Планировка, мебель и сантехника", "Стандартные материалы: дом без лишних резов", "Соединения и крепёж"] + b.stages.map { $0.title } + ["Развёртки стен каркаса", "Ведомость пиломатериалов", "Сводная ведомость закупки", "Нормативные документы"], size: 10)
        w.heading("Ключевые решения", level: 2)
        let key = b.stages.flatMap { s in s.decisions.prefix(3).map { ["\(s.number). \($0.title)", $0.value, $0.ref] } }
        w.table(["Решение", "Принято", "Норматив"], key, widths: [0.3, 0.38, 0.32], size: 7.2)

        // --- Порядок строительства ---
        w.newPage()
        w.heading("Порядок строительства")
        w.heading("Решить до начала стройки", level: 2)
        w.numbered(BuildPlan.decideEarly(p), size: 8.5)
        w.heading("Пол: какой и на каком этапе", level: 2)
        w.table(["Этап", "Что делается"], BuildPlan.floorTimeline(p, b).map { [$0.0, $0.1] }, widths: [0.3, 0.7], size: 7.5)
        w.heading("Этапы", level: 2)
        w.table(["№", "Этап", "Когда"], b.stages.map { ["\($0.number)", $0.title, $0.when] }, widths: [0.06, 0.4, 0.54], size: 7.2)

        // --- Планировка и сантехника ---
        w.newPage()
        w.heading("Планировка, мебель и сантехника")
        w.table(["Помещение", "Площадь", "Мебель и приборы"], b.layout.rooms.map { r in [r.name, "\(fmt(r.area, 1)) м²", b.layout.furniture.filter { $0.room == r.id }.map(\.name).joined(separator: ", ")] }, widths: [0.25, 0.12, 0.63], size: 7.5)
        for f in [Figure(kind: .furniturePlan, title: "Планировка с мебелью", aspect: 0.7), Figure(kind: .plumbingPlan, title: "Разводка воды и канализации", aspect: 0.75)] {
            w.figure(f.title, aspect: f.aspect, maxH: 420) { cg, rect in Drawings.render(f.kind, ctx, cg, rect) }
        }
        let pt = PlumbingWorks.pointsTable(b.layout)
        w.heading("Точки воды и канализации", level: 2)
        w.table(pt.head, pt.rows, widths: [0.06, 0.2, 0.36, 0.14, 0.24], size: 7.2)

        // --- Модульная система ---
        w.newPage()
        w.heading("Стандартные материалы: дом без лишних резов")
        w.text("Все размеры подогнаны под материалы из магазина: шаг стоек, балок и стропил 625 мм (лист 1250 = 2 шага, плита утеплителя 600 входит в просвет 575 в распор), стойка — целая доска 3000 мм (каркас 3150 = 50 + 3000 + 2×50), наружные размеры каркаса кратны 1250 мм, окна и двери — типовые блоки. Там, где рез неизбежен, он один и без отходов: лист ОСП/ГКЛ или плита утеплителя режется пополам.", size: 9)
        w.heading("Проверка проекта", level: 2)
        w.table(["Правило", "Выполнено", "Подробности"], b.checks.map { [$0.title, $0.ok ? "да" : "⚠︎ нет", $0.detail] }, widths: [0.34, 0.12, 0.54], size: 7.5)
        w.heading("Карта материалов", level: 2)
        w.table(["Материал", "Размер", "Правило модуля", "Резка", "Кол-во"], b.kit.map { [$0.material, $0.size, $0.rule, $0.cut, $0.qty] },
                widths: [0.18, 0.16, 0.3, 0.2, 0.16], size: 6.8)
        let w0 = BuildPlan.wallsExt0First(F)
        var modFigs: [Figure] = [Figure(kind: .wallSection, title: "Разрез наружной стены: брус, утеплитель, отделка снаружи и изнутри, размеры в мм", aspect: 0.95),
                                 Figure(kind: .wallPlan, title: "Стена в плане: шаг 625, плита 600 в распор, стык ОСП по оси стойки", aspect: 0.4)]
        if let i = w0 { modFigs += [0, 1, 2].map { Figure(kind: .sheetLayout(i, $0), title: ["Раскладка ОСП снаружи", "Раскладка утеплителя", "Раскладка ГКЛ изнутри"][$0] + " — стена \(F.walls[i].name)", aspect: 0.42) } }
        for f in modFigs { w.figure(f.title, aspect: f.aspect, maxH: 420) { cg, rect in Drawings.render(f.kind, ctx, cg, rect) } }

        // --- Соединения ---
        w.newPage()
        w.heading("Соединения и крепёж")
        w.table(["Узел", "Чем", "Сколько / шаг", "Инструмент"], Kit.joints.map { [$0.what, $0.how, $0.qty, $0.tool] }, widths: [0.24, 0.34, 0.18, 0.24], size: 7)
        for f in [Figure(kind: .fasteners, title: "Основные узлы каркаса", aspect: 0.62), Figure(kind: .rigidity, title: "Откуда жёсткость стены: временные укосины, раскосы, ОСП", aspect: 0.42)] {
            w.figure(f.title, aspect: f.aspect) { cg, rect in Drawings.render(f.kind, ctx, cg, rect) }
        }
        w.heading(Fasteners.rule.title, level: 2)
        w.numbered(Fasteners.rule.steps, size: 8.5)
        let rg = Guides.walls(p, F)[2]
        w.heading(rg.title, level: 2)
        w.numbered(rg.steps)

        // --- Этапы ---
        var shownScenes = Set<Stage3D>()
        let steps3D = Steps3D.make(p, r, b.frame)
        var shownWalls = Set<Int>()
        for s in b.stages {
            w.newPage()
            w.heading("Этап \(s.number). \(s.title)")
            w.text(s.goal, size: 9.5, italic: true, color: .darkGray, after: 4)
            if !s.when.isEmpty { w.text("Когда: " + s.when, size: 8.5, color: NSColor(srgbRed: 0.1, green: 0.3, blue: 0.6, alpha: 1), after: 6) }
            if !shownScenes.contains(s.scene) {
                shownScenes.insert(s.scene)
                // все шаги этого 3D-этапа по порядку (как на бегунке «Этап» во вкладке 3D); длинные серии — выборочно
                var shots = steps3D.filter { $0.stage == s.scene }
                if shots.count > 8 {
                    let n = shots.count
                    shots = (0..<8).map { shots[Int((Double($0) * Double(n - 1) / 7).rounded())] }
                }
                if shots.count > 1 {
                    w.heading("Как это выглядит на площадке — по шагам (3D)", level: 2)
                    let cells = shots.compactMap { st -> (img: CGImage, title: String, note: String)? in
                        guard let img = render3D(p, r, stage: st.stage, sub: st.sub, size: CGSize(width: 760, height: 456)) else { return nil }
                        let n = (steps3D.firstIndex(of: st) ?? 0) + 1
                        return (img, "Шаг \(n). \(st.title)", st.note)
                    }
                    w.imageGrid(cells)
                } else if let img = render3D(p, r, stage: s.scene, size: CGSize(width: 1100, height: 560)) {
                    w.image(img, height: 200)
                    let note = shots.first.map { "Шаг \((steps3D.firstIndex(of: $0) ?? 0) + 1). \($0.title) — \($0.note)" } ?? "3D: этап «\(s.scene.title)»"
                    w.text(note, size: 7.5, italic: true, color: .gray, after: 6)
                }
            }
            w.heading("Порядок работ", level: 2)
            w.numbered(s.steps)
            if !s.tools.isEmpty {
                w.heading("Инструмент", level: 2)
                w.text(s.tools.map { "• " + $0 }.joined(separator: "\n"), size: 8.5)
            }
            if let t = s.table {
                w.heading(t.title, level: 2)
                w.table(t.head, t.rows, widths: t.widths, size: 7.2)
            }
            if !s.fasteners.isEmpty {
                w.heading("Крепёж: что → чем → инструмент", level: 2)
                w.table(["Что крепим", "Чем (что купить)", "Чем закручивать / забивать"], s.fasteners.map { [$0.what, $0.item, $0.how] }, widths: [0.27, 0.43, 0.3], size: 7.2)
            }
            for g in s.guides {
                w.heading("🔧 " + g.title, level: 3)
                w.numbered(g.steps, size: 8.5)
                if !g.tip.isEmpty { w.text("Совет: " + g.tip, size: 8, italic: true, color: .darkGray) }
            }
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
        w.text("Подсчитано по фактической раскладке всех элементов каркаса: стойки 3000 — целыми досками 3 м, короткие элементы — из досок 3 м, остальное — раскрой хлыстов 6 м (+5 % на брак). Хвойные породы, 2 сорт по ГОСТ 8486-86, камерной сушки (влажность ≤ 20 %).", size: 8.5, color: .darkGray)
        w.table(["Сечение", "Назначение (кол-во элементов)", "Погонаж, м", "Досок, шт", "Объём, м³"],
                b.lumber.map { [$0.sec.label + "×\(Int($0.stock * 1000))" + ($0.whole ? " целиком" : ""), $0.use, fmt($0.totalLength, 0), "\($0.pieces)", fmt($0.volume, 2)] }
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
