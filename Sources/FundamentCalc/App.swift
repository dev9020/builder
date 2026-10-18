import SwiftUI
import AppKit

@main
struct FundamentApp: App {
    @StateObject private var model = AppModel()

    init() {
        if CommandLine.arguments.contains("--presets") {
            for pr in HousePreset.all {
                let p0 = Project()
                pr.build(p0); p0.sheathing = .osbBraces; p0.fitToModule()
                for c in Daylight.improve(p0) { print("   свет: \(c.room) — \(c.text)") }
                for i in Daylight.issues(p0) { print("   ТЕМНО: \(i)") }
                for o in p0.openings {
                    guard case .edge(let ei) = o.host else { continue }
                    let g = (o.pos - o.width / 2 - 0.075 + p0.studDepth / 2) / Module.step
                    let kings = [o.pos - o.width / 2 - 0.075, o.pos + o.width / 2 + 0.075]
                    if CommandLine.arguments.contains("--edges") { print("   проём \(o.kind.title) w=\(fmt(o.width)) стена \(ei) pos \(fmt(o.pos)) L=\(fmt((p0.edges[ei].b - p0.edges[ei].a).len)) a=\(p0.edges[ei].a) studs=\(Daylight.junctionStuds(p0, edge: ei).map { fmt($0) })") }
                    if abs(g - g.rounded()) > 0.01, !Daylight.junctionStuds(p0, edge: ei).contains(where: { s in kings.contains { abs($0 - s) < 0.01 } }) { print("   не на сетке: \(o.kind.title) \(fmt(o.width)) стена \(ei) pos \(fmt(o.pos))") }
                }
                let p = Project()
                pr.apply(p)
                let r = Calculator.run(p)
                let ops = p.validOpenings
                var issues: [String] = []
                // перекрытие проёмов на одной стене
                for (i, a) in ops.enumerated() {
                    for b in ops[(i + 1)...] where a.host == b.host && abs(a.pos - b.pos) < (a.width + b.width) / 2 + 0.1 {
                        issues.append("перекрытие \(a.kind.title)@\(fmt(a.pos)) и \(b.kind.title)@\(fmt(b.pos))")
                    }
                    if p.openings.first(where: { $0.id == a.id })!.pos != a.pos { issues.append("сдвинут \(a.kind.title)") }
                }
                let ok = pr.foundation == .strip ? r.strip.ok : r.slab.ok
                let wr = Weights.make(p, r)
                let costs = FoundationKind.allCases.map { k -> String in
                    let w = Works.plan(p, r, kind: k)
                    let dr = w.sections.last!.items.reduce(0) { $0 + $1.cost }
                    return "\(k.title): \(rub(w.purchase.reduce(0) { $0 + $1.cost })) (из них отмостка+дренаж \(rub(dr)))"
                }
                print("   стоимость:", costs.joined(separator: "; "))
                print("   вес: конструкции \(fmt(wr.dead / 9.81, 1)) т, снег \(fmt(wr.snow / 9.81, 1)) т, содержимое \(fmt(wr.contentsSum / 9.81, 1)) т, зимой \(fmt(wr.winter / 9.81, 1)) т; фундамент \(fmt(wr.foundationSelf / 9.81, 1)) т, выдержит \(fmt(wr.capacity / 9.81, 0)) т, нагрузка \(fmt(wr.load / 9.81, 1)) т, запас ×\(fmt(wr.reserve, 1)), лок. \(Int(wr.localRatio * 100))%")
                let D = p.studDepth
                print("   наружные размеры каркаса: \(fmt(p.length + D, 2))×\(fmt(p.effW + D, 2)), крылья \(fmt(p.wingA + D, 2))/\(fmt(p.wingB + D, 2)), двор \(fmt(p.innerL - D, 2))×\(fmt(p.innerW - D, 2)), проверки: \(BuildPlan.make(p, r).checks.filter { !$0.ok }.map(\.title))")
                print("\(pr.id): S=\(fmt(Geo.area(p.rings), 1)) эт=\(p.floors) уклон=\(Int(p.roofAngleEff)) проёмов \(ops.count)/\(p.openings.count) фундамент OK=\(ok)", issues.isEmpty ? "" : issues.joined(separator: "; "))
                if !ok {
                    let ch = pr.foundation == .strip ? r.strip.checks : r.slab.checks
                    for c in ch where !c.ok { print("   ✘", c.title, c.value) }
                }
            }
            exit(0)
        }
        if CommandLine.arguments.contains("--rooms") {
            for pr in HousePreset.all + [nil] {
                let p = Project()
                pr?.apply(p)
                let r = Calculator.run(p)
                let L = BuildPlan.make(p, r).layout
                print("\(pr?.id ?? "default"): " + L.rooms.map { "\($0.name) \(fmt($0.area, 1)) [\(fmt($0.seed.x, 1)),\(fmt($0.seed.y, 1))]" }.joined(separator: "; "))
                let unplaced = L.rooms.filter { r in !L.furniture.contains { $0.room == r.id } && ![.corridor].contains(r.type) }.map(\.name)
                print("   мебели \(L.furniture.count), точек \(L.points.count), без мебели: \(unplaced); ввод \(L.entryWall)/\(fmt(L.entryOffset)), выпуск \(L.outletWall)/\(fmt(L.outletOffset)) −\(fmt(L.outletDepth)), септик \(fmt(L.sewerLen, 1)) м вход −\(fmt(L.septicInlet)), скв. \(fmt(L.waterLen, 1)) м, участок \(fmt(L.plotHi.x - L.plotLo.x, 0))×\(fmt(L.plotHi.y - L.plotLo.y, 0))")
                let kinds = Dictionary(grouping: L.furniture, by: { $0.room }).map { k, v in "\(L.rooms[k].name): " + v.map(\.name).joined(separator: ", ") }
                for k in kinds.sorted() { print("     " + k) }
            }
            exit(0)
        }
        if CommandLine.arguments.contains("--build") {
            let p = Project()
            if let i = CommandLine.arguments.firstIndex(of: "--preset"), i + 1 < CommandLine.arguments.count,
               let pr = HousePreset.all.first(where: { $0.id == CommandLine.arguments[i + 1] }) { pr.apply(p) }
            func arg(_ k: String) -> String? { CommandLine.arguments.firstIndex(of: k).flatMap { $0 + 1 < CommandLine.arguments.count ? CommandLine.arguments[$0 + 1] : nil } }
            if let w = arg("--wind").flatMap(Int.init), let wr = WindRegion(rawValue: w) { p.windRegion = wr }
            if let a = arg("--angle").flatMap(Double.init) { p.roofAngleAuto = false; p.roofAngle = a }
            if let o = arg("--overhang").flatMap(Double.init) { p.overhang = o }
            if let f = arg("--facade"), let ff = FacadeFinish(rawValue: f) { p.facade = ff }
            if let c = arg("--covering"), let cc = RoofCovering(rawValue: c) { p.covering = cc }
            if CommandLine.arguments.contains("--cold") { p.roofInsulated = false }
            if CommandLine.arguments.contains("--stove") { p.fireplace = true; p.heatSource = .solid }
            if let k = arg("--foundation"), let kk = FoundationKind(rawValue: k) { p.selectedFoundation = kk }
            let r = Calculator.run(p)
            let b = BuildPlan.make(p, r)
            let F = b.frame
            print("элементов каркаса: \(F.members.count), стен: \(F.walls.count), анкеров: \(F.anchors.count)")
            if CommandLine.arguments.contains("--roofcheck") {
                // скачки высоты ската и рёбра без стропил
                let o = p.overhang
                let m = RoofModel.of(p, overhang: o)
                let rings = p.rings.enumerated().map { i, rr in Geo.offset(rr, by: i == 0 ? o : -o) }
                let (lo, hi) = Geo.bbox(rings)
                let h = 0.05
                var jumps = 0
                var y = lo.y + h / 2
                while y < hi.y {
                    var x = lo.x + h / 2
                    while x < hi.x {
                        let v = V2(x, y)
                        if Geo.contains(v, rings), let d0 = m.depth(v) {
                            for w in [V2(x + h, y), V2(x, y + h)] where Geo.contains(w, rings) {
                                if let d1 = m.depth(w), abs(d1.d - d0.d) > h * 1.5 {
                                    jumps += 1
                                    if jumps <= 30 { print("  скачок \(fmt(v.x, 2)),\(fmt(v.y, 2)) → \(fmt(w.x, 2)),\(fmt(w.y, 2)): \(fmt(d0.d, 2))/e\(d0.edge) → \(fmt(d1.d, 2))/e\(d1.edge)") }
                                }
                            }
                        }
                        x += h
                    }
                    y += h
                }
                print("скачков: \(jumps)")
                let long = F.members.filter { $0.length > 6.01 && $0.kind != .batten && $0.kind != .counterBatten }
                print("элементов длиннее 6 м: \(long.count) " + Dictionary(grouping: long, by: \.kind).map { "\($0.key.rawValue) \($0.value.count) (до \(fmt($0.value.map(\.length).max() ?? 0)) м)" }.joined(separator: ", "))
                for m in F.members.filter({ [.rafter, .hip, .ridge].contains($0.kind) }).prefix(400) where m.kind != .rafter || abs(m.a.y - 0) < 0.6 || abs(m.a.x - 14.8) < 0.6 {
                    print("  \(m.kind) seq\(m.seq) a=(\(fmt(m.a.x)),\(fmt(m.a.y)),\(fmt(m.a.z))) b=(\(fmt(m.b.x)),\(fmt(m.b.y)),\(fmt(m.b.z))) up=(\(fmt(m.up.x)),\(fmt(m.up.y)),\(fmt(m.up.z))) \(m.sec.label)")
                }
                // участки ската без стропил: точка дальше 0.45 м от ближайшего стропила/диагональной ноги
                var holes = 0
                y = lo.y + 0.1
                while y < hi.y {
                    var x = lo.x + 0.1
                    while x < hi.x {
                        let v = V2(x, y)
                        if Geo.contains(v, rings) {
                            let dmin = F.rafterLines.map { Geo.distToSegment(v, $0.0, $0.1) }.min() ?? 99
                            let hips = F.members.filter { $0.kind == .hip }.map { Geo.distToSegment(v, V2($0.a.x, $0.a.y), V2($0.b.x, $0.b.y)) }.min() ?? 99
                            if min(dmin, hips) > 0.45 { holes += 1; if holes <= 20 { print("  без стропил: \(fmt(x, 2)),\(fmt(y, 2))") } }
                        }
                        x += 0.2
                    }
                    y += 0.2
                }
                print("точек без стропил: \(holes)")
                for (i, e) in m.edges.enumerated() { print("  e\(i) \(fmt(e.a.x)),\(fmt(e.a.y))→\(fmt(e.b.x)),\(fmt(e.b.y)) eave=\(e.eave)") }
                for (a, b) in F.ridgeLines { print("  конёк \(fmt(a.x)),\(fmt(a.y))→\(fmt(b.x)),\(fmt(b.y))") }
            }
            if CommandLine.arguments.contains("--walls") {
                for w in F.walls where w.storey == 0 {
                    let xs = w.rects.filter { [.stud, .cornerStud, .king, .jack].contains($0.kind) }.map { "\($0.kind == .stud ? "" : String($0.kind.rawValue.prefix(3)))\(Int((($0.u0 + $0.u1) / 2 * 1000).rounded()))" }
                    print(w.name, "L=\(fmt(w.length, 3)) origin=\(fmt(w.origin, 3))", xs.joined(separator: " "))
                    print("   проёмы:", w.openings.map { "\(Int($0.u0 * 1000))–\(Int($0.u1 * 1000))" }.joined(separator: ", "))
                }
            }
            print("отметки: верх фунд. \(fmt(F.foundTop)), пол 1 эт. \(fmt(F.levelBase)), верх стен \(fmt(F.wallTop)), стены \(F.wallHeights.map { fmt($0) })")
            for j in F.floors + (F.attic.map { [$0] } ?? []) {
                if CommandLine.arguments.contains("--joists") {
                    print("    вдоль X: \(j.alongX); прогоны: " + j.beams.map { "(\(fmt($0.0.x)),\(fmt($0.0.y)))→(\(fmt($0.1.x)),\(fmt($0.1.y)))" }.joined(separator: " "))
                    for g in j.girders {
                        print("    прогон \(fmt(g.length)) м \(g.title) ok=\(g.check.ok) σ=\(fmt(g.check.sigma, 1)) макс.пролёт \(fmt(g.maxGap)) куски \(g.pieces.map { fmt($0.1 - $0.0) }) опоры: " + g.supports.map { "\(fmt($0.u))\($0.kind.rawValue.prefix(4))" }.joined(separator: " "))
                    }
                    print("    опоры: " + j.supports.map { "(\(fmt($0.0.x)),\(fmt($0.0.y)))→(\(fmt($0.1.x)),\(fmt($0.1.y)))" }.joined(separator: " "))
                    print("    балки: " + j.lines.prefix(40).map { "\(fmt(($0.1 - $0.0).len))" }.joined(separator: " "))
                }
                print("  \(j.title): \(j.check.title) шаг \(j.check.step) пролёт \(fmt(j.maxSpan)) σ=\(fmt(j.check.sigma, 1)) f=\(fmt(j.check.f * 1000, 0))/\(fmt(j.check.fu * 1000, 0)) ok=\(j.check.ok) линий \(j.lines.count)")
            }
            if let rf = F.rafter { print("  стропила \(rf.title) шаг \(rf.step) проекция \(fmt(F.rafterRun)) σ=\(fmt(rf.sigma, 1)) f=\(fmt(rf.f * 1000, 0))/\(fmt(rf.fu * 1000, 0)) ok=\(rf.ok) подкос=\(F.rafterStrut)") }
            print("  стойка N=\(fmt(F.stud.N, 1)) φ=\(fmt(F.stud.phi, 2)) σ=\(fmt(F.stud.sigma, 2)) ok=\(F.stud.ok)")
            for h in F.headers { print("  перемычка \(h.wall)/\(h.storey) l=\(fmt(h.span)) q=\(fmt(h.q, 1)) \(h.check.title) σ=\(fmt(h.check.sigma, 1)) ok=\(h.check.ok)") }
            print("ГСОП \(Int(b.gsop)): Rст \(fmt(b.rWall)) → \(Int(b.woolWall * 1000)); Rкр \(fmt(b.rRoof)) → \(Int(b.woolRoof * 1000)); Rпол \(fmt(b.rFloor)) → \(Int(b.woolFloor * 1000)); Rок \(fmt(b.rWindow))")
            for k in MemberKind.allCases { let n = F.members.filter { $0.kind == k }.count; if n > 0 { print("  \(k.rawValue): \(n)") } }
            for row in b.lumber { print("  \(row.sec.label): \(row.pieces) шт, \(fmt(row.totalLength, 0)) м, \(fmt(row.volume, 2)) м³ — \(row.use)") }
            if let j = CommandLine.arguments.firstIndex(of: "--stage"), j + 1 < CommandLine.arguments.count {
                let key = CommandLine.arguments[j + 1]
                for s in b.stages where s.title.lowercased().contains(key.lowercased()) || "\(s.number)" == key {
                    print("== \(s.number). \(s.title)\n   когда: \(s.when)")
                    for st in s.steps { print("  • " + st) }
                    for d in s.decisions { print("  ◆ \(d.title): \(d.value) — \(d.why) [\(d.ref)]") }
                    if let t = s.table { print("  " + t.head.joined(separator: " | ")); for r in t.rows { print("  " + r.joined(separator: " | ")) } }
                    for it in s.items { print("  ▸ \(it.name): \(fmt(it.qty, it.digits)) \(it.unit) \(it.note)") }
                }
                exit(0)
            }
            for s in b.stages { print("\(s.number). \(s.title): шагов \(s.steps.count), решений \(s.decisions.count), схем \(s.figures.count), позиций \(s.items.count), \(rub(s.items.reduce(0) { $0 + $1.cost }))") }
            for g in b.groups { print("[\(g.title)] \(rub(g.items.reduce(0) { $0 + $1.cost }))"); for it in g.items { print("    \(it.name): \(fmt(it.qty, it.digits)) \(it.unit) \(rub(it.cost))") } }
            print("ИТОГО \(rub(b.total))")
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--pdf"), i + 1 < CommandLine.arguments.count {
            MainActor.assumeIsolated {
                let p = Project()
                if let j = CommandLine.arguments.firstIndex(of: "--preset"), j + 1 < CommandLine.arguments.count,
                   let pr = HousePreset.all.first(where: { $0.id == CommandLine.arguments[j + 1] }) { pr.apply(p) }
                if let j = CommandLine.arguments.firstIndex(of: "--foundation"), j + 1 < CommandLine.arguments.count,
                   let k = FoundationKind(rawValue: CommandLine.arguments[j + 1]) { p.selectedFoundation = k }
                let r = Calculator.run(p)
                let b = BuildPlan.make(p, r)
                let t0 = Date()
                let data = PDFExport.make(p, r, b)
                try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
                print("PDF: \(data.count / 1024) КБ за \(fmt(Date().timeIntervalSince(t0), 1)) с")
            }
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--figs"), i + 1 < CommandLine.arguments.count {
            MainActor.assumeIsolated {
                let p = Project()
                if let j = CommandLine.arguments.firstIndex(of: "--preset"), j + 1 < CommandLine.arguments.count,
                   let pr = HousePreset.all.first(where: { $0.id == CommandLine.arguments[j + 1] }) { pr.apply(p) }
                if let j = CommandLine.arguments.firstIndex(of: "--foundation"), j + 1 < CommandLine.arguments.count,
                   let k = FoundationKind(rawValue: CommandLine.arguments[j + 1]) { p.selectedFoundation = k }
                if CommandLine.arguments.contains("--boards") { p.interiorFinish = .boards }
                if CommandLine.arguments.contains("--water") { p.floorHeating = .water }
                let r = Calculator.run(p)
                let b = BuildPlan.make(p, r)
                let ctx = Drawings.Ctx(p: p, r: r, b: b)
                var n = 0
                for s in b.stages {
                    for f in s.figures {
                        n += 1
                        let w = 1030.0, h = w * f.aspect
                        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w), pixelsHigh: Int(h), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                        let g = NSGraphicsContext(bitmapImageRep: rep)!
                        let cg = g.cgContext
                        cg.translateBy(x: 0, y: h); cg.scaleBy(x: 2, y: -2)
                        Drawings.render(f.kind, ctx, cg, CGRect(x: 0, y: 0, width: w / 2, height: h / 2))
                        let png = rep.representation(using: .png, properties: [:])!
                        try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]).appendingPathComponent(String(format: "fig%02d.png", n)))
                        if CommandLine.arguments.contains("--list") { print(String(format: "fig%02d ", n) + f.title) }
                    }
                }
                print("схем: \(n)")
            }
            exit(0)
        }
        if CommandLine.arguments.contains("--dump") {
            let p = Project()
            for kind in FoundationKind.allCases {
                p.selectedFoundation = kind
                let r = Calculator.run(p)
                print(Report.html(p, r).replacingOccurrences(of: "<tr>", with: "\n").replacingOccurrences(of: "</td>", with: " | ")
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
            }
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            MainActor.assumeIsolated { Snapshot.run(CommandLine.arguments[i + 1]) }
            exit(0)
        }
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
    }

    var body: some Scene {
        WindowGroup("Дом своими руками") {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.project)
                .frame(minWidth: 1000, minHeight: 680)
        }
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: false))
    }
}

enum MainTab: String, CaseIterable, Identifiable {
    case view3D = "3D-модель", plan = "План", results = "Расчёт", works = "Работы", build = "Проект дома"
    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var project: Project
    @StateObject private var editor = EditorState()
    @State private var tab: MainTab = .view3D
    @State private var options = SceneOptions()
    @State private var resetToken = 0
    @State private var showCatalog = false

    var currentOK: Bool {
        switch project.selectedFoundation {
        case .strip: return model.results.strip.ok
        case .slab: return model.results.slab.ok
        case .piles: return model.results.piles.ok
        }
    }

    var body: some View {
        HSplitView {
            SidebarView()
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 440)
            Group {
                switch tab {
                case .view3D: view3D
                case .plan: PlanEditorView().environmentObject(editor)
                case .results: ResultsView()
                case .works: WorksView()
                case .build: BuildView(show3D: { st, sub in options.stage = st; options.sub = sub; tab = .view3D })
                }
            }
            .frame(minWidth: 640, maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showCatalog) {
            CatalogView().environmentObject(project)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Вид", selection: $tab) {
                    ForEach(MainTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            ToolbarItem(placement: .navigation) {
                Button { showCatalog = true } label: {
                    Label("Готовые проекты", systemImage: "house.lodge")
                        .labelStyle(.titleAndIcon)
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.link)
                .help("Каталог готовых проектов домов 80–150 м²")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Фундамент", selection: $project.selectedFoundation) {
                    ForEach(FoundationKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Тип фундамента")
                Image(systemName: currentOK ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(currentOK ? .green : .orange)
                    .help(currentOK ? "Все проверки выполнены" : "Есть невыполненные проверки — см. вкладку «Расчёт»")
                Button {
                    Report.export(project, model.results)
                } label: { Label("Отчёт", systemImage: "square.and.arrow.up") }
                .help("Экспорт отчёта в HTML")
            }
        }
    }

    @State private var layersOpen = true

    var view3D: some View {
        ZStack(alignment: .topLeading) {
            Scene3DView(project: project, results: model.results, options: options, resetToken: resetToken)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Button { withAnimation(.easeInOut(duration: 0.15)) { layersOpen.toggle() } } label: {
                        Label("Слои", systemImage: layersOpen ? "chevron.up" : "square.3.layers.3d")
                    }
                    .buttonStyle(.borderless)
                    Button { resetToken += 1 } label: { Image(systemName: "scope") }
                        .buttonStyle(.borderless)
                        .help("Сбросить вид")
                }
                .font(.callout)
                if layersOpen {
                    Toggle("Стены", isOn: $options.walls)
                    Slider(value: Binding(get: { 1 - options.wallOpacity }, set: { options.wallOpacity = 1 - $0 }), in: 0...0.9) {
                        Text("Прозр.").font(.caption)
                    }
                    .controlSize(.mini)
                    .frame(width: 130)
                    Toggle("Кровля", isOn: $options.roof)
                    Toggle("Фундамент", isOn: $options.foundation)
                    Toggle("Армирование", isOn: $options.rebar)
                    Toggle("Отмостка и дренаж", isOn: $options.drainage)
                    Toggle("Участок: забор, сад", isOn: $options.site)
                    Toggle("Грунт", isOn: $options.ground)
                }
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(8)

            VStack {
                let steps = Steps3D.make(project, model.results, model.plan.frame)
                let cur = steps.firstIndex { $0.stage == options.stage && $0.sub == options.sub }
                    ?? steps.lastIndex { $0.stage == options.stage } ?? steps.count - 1
                let go = { (i: Int) in let s = steps[max(0, min(steps.count - 1, i))]; options.stage = s.stage; options.sub = s.sub }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Этап:").bold()
                        Button { go(cur - 1) } label: { Image(systemName: "chevron.left") }
                            .disabled(cur == 0)
                            .keyboardShortcut(.leftArrow, modifiers: [])
                        Slider(value: Binding(get: { Double(cur) }, set: { go(Int($0.rounded())) }),
                               in: 0...Double(max(steps.count - 1, 1)), step: 1)
                            .frame(width: 260)
                        Button { go(cur + 1) } label: { Image(systemName: "chevron.right") }
                            .disabled(cur >= steps.count - 1)
                            .keyboardShortcut(.rightArrow, modifiers: [])
                        Text("\(cur + 1)/\(steps.count). \(steps[cur].title)").bold().frame(width: 270, alignment: .leading)
                    }
                    Text(steps[cur].note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 600, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .font(.callout)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 8)
                Spacer()
                HStack(spacing: 10) {
                    ForEach(project.usedMaterials) { m in
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2).fill(Color(nsColor: m.nsColor)).frame(width: 12, height: 9)
                                .overlay(RoundedRectangle(cornerRadius: 2).stroke(.black.opacity(0.3)))
                            Text(m.short)
                        }
                    }
                    Spacer()
                    let wr = Weights.make(project, model.results)
                    Text("Дом зимой ≈ \(fmt(wr.winter / 9.81, 1)) т · фундамент выдержит ≈ \(fmt(wr.capacity / 9.81, 0)) т")
                        .bold().foregroundStyle(wr.reserve >= 1 ? Color.primary : Color.red)
                    Text("·").foregroundStyle(.secondary)
                    Text("ЛКМ — вращение · колесо — масштаб · ⌥+ЛКМ — сдвиг")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                .padding(8)
            }
        }
    }
}
