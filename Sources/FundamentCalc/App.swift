import SwiftUI
import AppKit

@main
struct FundamentApp: App {
    @StateObject private var model = AppModel()

    init() {
        if CommandLine.arguments.contains("--presets") {
            for pr in HousePreset.all {
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
            let r = Calculator.run(p)
            let b = BuildPlan.make(p, r)
            let F = b.frame
            print("элементов каркаса: \(F.members.count), стен: \(F.walls.count), анкеров: \(F.anchors.count)")
            if CommandLine.arguments.contains("--walls") {
                for w in F.walls where w.storey == 0 {
                    let xs = w.rects.filter { [.stud, .cornerStud, .king, .jack].contains($0.kind) }.map { "\($0.kind == .stud ? "" : String($0.kind.rawValue.prefix(3)))\(Int((($0.u0 + $0.u1) / 2 * 1000).rounded()))" }
                    print(w.name, "L=\(fmt(w.length, 3)) origin=\(fmt(w.origin, 3))", xs.joined(separator: " "))
                    print("   проёмы:", w.openings.map { "\(Int($0.u0 * 1000))–\(Int($0.u1 * 1000))" }.joined(separator: ", "))
                }
            }
            print("отметки: верх фунд. \(fmt(F.foundTop)), пол 1 эт. \(fmt(F.levelBase)), верх стен \(fmt(F.wallTop)), стены \(F.wallHeights.map { fmt($0) })")
            for j in F.floors + (F.attic.map { [$0] } ?? []) {
                print("  \(j.title): \(j.check.title) шаг \(j.check.step) пролёт \(fmt(j.maxSpan)) σ=\(fmt(j.check.sigma, 1)) f=\(fmt(j.check.f * 1000, 0))/\(fmt(j.check.fu * 1000, 0)) ok=\(j.check.ok) линий \(j.lines.count)")
            }
            if let rf = F.rafter { print("  стропила \(rf.title) шаг \(rf.step) проекция \(fmt(F.rafterRun)) σ=\(fmt(rf.sigma, 1)) f=\(fmt(rf.f * 1000, 0))/\(fmt(rf.fu * 1000, 0)) ok=\(rf.ok) подкос=\(F.rafterStrut)") }
            print("  стойка N=\(fmt(F.stud.N, 1)) φ=\(fmt(F.stud.phi, 2)) σ=\(fmt(F.stud.sigma, 2)) ok=\(F.stud.ok)")
            for h in F.headers { print("  перемычка \(h.wall)/\(h.storey) l=\(fmt(h.span)) q=\(fmt(h.q, 1)) \(h.check.title) σ=\(fmt(h.check.sigma, 1)) ok=\(h.check.ok)") }
            print("ГСОП \(Int(b.gsop)): Rст \(fmt(b.rWall)) → \(Int(b.woolWall * 1000)); Rкр \(fmt(b.rRoof)) → \(Int(b.woolRoof * 1000)); Rпол \(fmt(b.rFloor)) → \(Int(b.woolFloor * 1000)); Rок \(fmt(b.rWindow))")
            for k in MemberKind.allCases { let n = F.members.filter { $0.kind == k }.count; if n > 0 { print("  \(k.rawValue): \(n)") } }
            for row in b.lumber { print("  \(row.sec.label): \(row.pieces) шт, \(fmt(row.totalLength, 0)) м, \(fmt(row.volume, 2)) м³ — \(row.use)") }
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
                case .build: BuildView(show3D: { st in options.stage = st; tab = .view3D })
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
                HStack(spacing: 8) {
                    Text("Этап:").bold()
                    Button { if options.stage.rawValue > 0 { options.stage = Stage3D(rawValue: options.stage.rawValue - 1)! } } label: { Image(systemName: "chevron.left") }
                        .disabled(options.stage == .site)
                    Slider(value: Binding(get: { Double(options.stage.rawValue) }, set: { options.stage = Stage3D(rawValue: Int($0.rounded())) ?? .finish }),
                           in: 0...Double(Stage3D.allCases.count - 1), step: 1)
                        .frame(width: 220)
                    Button { if options.stage != .finish { options.stage = Stage3D(rawValue: options.stage.rawValue + 1)! } } label: { Image(systemName: "chevron.right") }
                        .disabled(options.stage == .finish)
                    Text("\(options.stage.rawValue + 1). \(options.stage.title)").frame(width: 230, alignment: .leading)
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
