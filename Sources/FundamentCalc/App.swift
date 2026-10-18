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
                print("\(pr.id): S=\(fmt(Geo.area(p.rings), 1)) эт=\(p.floors) уклон=\(Int(p.roofAngleEff)) проёмов \(ops.count)/\(p.openings.count) фундамент OK=\(ok)", issues.isEmpty ? "" : issues.joined(separator: "; "))
                if !ok {
                    let ch = pr.foundation == .strip ? r.strip.checks : r.slab.checks
                    for c in ch where !c.ok { print("   ✘", c.title, c.value) }
                }
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
        WindowGroup("Расчёт фундамента") {
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
    case view3D = "3D-модель", plan = "План", results = "Расчёт", works = "Работы"
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
