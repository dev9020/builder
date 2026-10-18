import SwiftUI
import PDFKit

/// Вкладка «Проект дома»: этапы от участка до кровли с обоснованиями, схемами и материалами
struct BuildView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var p: Project
    var show3D: (Stage3D) -> Void = { _ in }
    @State private var sel = 0          // ≥ 0 — этап, −1 — сводка и закупка, −2 — нормативы
    @State private var pdf: Data?
    @State private var busy = false

    /// Только содержимое выбранного раздела, без списка и прокрутки (для отладочного рендера)
    var plainStage: Int? = nil

    var body: some View {
        let b = model.plan
        if let i = plainStage {
            VStack(alignment: .leading, spacing: 14) {
                toolbar(b)
                if i >= 0 { stage(b.stages[i], b) } else if i == -1 { summary(b) } else { norms }
            }
            .padding(16).frame(width: 1000, alignment: .leading)
        } else {
            full(b)
        }
    }

    func full(_ b: BuildPlan) -> some View {
        HStack(spacing: 0) {
            List(selection: Binding(get: { sel }, set: { sel = $0 ?? 0 })) {
                Section("Этапы строительства") {
                    ForEach(Array(b.stages.enumerated()), id: \.offset) { i, s in
                        Label { Text("\(s.number). \(s.title)").lineLimit(2) } icon: { Image(systemName: s.icon) }
                            .tag(i)
                    }
                }
                Section("Итоги") {
                    Label("Сводка и закупка", systemImage: "cart").tag(-1)
                    Label("Нормативные документы", systemImage: "books.vertical").tag(-2)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 270)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    toolbar(b)
                    if sel >= 0 && sel < b.stages.count {
                        stage(b.stages[sel], b)
                    } else if sel == -1 {
                        summary(b)
                    } else {
                        norms
                    }
                }
                .padding(16)
                .frame(maxWidth: 980, alignment: .leading)
            }
        }
        .sheet(isPresented: Binding(get: { pdf != nil }, set: { if !$0 { pdf = nil } })) {
            if let pdf { PDFPreview(data: pdf) { self.pdf = nil } }
        }
    }

    func toolbar(_ b: BuildPlan) -> some View {
        HStack(spacing: 12) {
            Button {
                busy = true
                DispatchQueue.main.async {
                    pdf = PDFExport.make(p, model.results, model.plan)
                    busy = false
                }
            } label: { Label("PDF проекта (предпросмотр)", systemImage: "doc.richtext") }
            .buttonStyle(.borderedProminent)
            .disabled(busy)
            if busy { ProgressView().controlSize(.small) }
            let nonStd = b.openings.filter { !$0.standard }.count
            if nonStd > 0 {
                Button { snapOpenings() } label: { Label("Подогнать \(nonStd) проём. под стандартные блоки", systemImage: "rectangle.dashed") }
                    .help("Размеры проёмов в каркасе станут равны черновым проёмам ближайших стандартных окон и дверей")
            }
            Spacer()
            Text("Материалы ≈ \(rub(b.total))").font(.headline).foregroundStyle(Color.accentColor)
        }
    }

    func snapOpenings() {
        let ext = Set(model.plan.openings.filter { !$0.wall.hasPrefix("П") }.map { $0.opening.id })
        p.openings = p.openings.map { o in
            var q = o
            let blk = StdBlock.nearest(o, exterior: ext.contains(o.id))
            q.width = (blk.roW * 1000).rounded() / 1000
            q.height = (blk.roH * 1000).rounded() / 1000
            return q
        }
    }

    // MARK: - Этап

    @ViewBuilder func stage(_ s: BuildStage, _ b: BuildPlan) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label("Этап \(s.number). \(s.title)", systemImage: s.icon).font(.title2.bold())
            Spacer()
            Button { show3D(s.scene) } label: { Label("Показать в 3D", systemImage: "cube.transparent") }
        }
        Text(s.goal).foregroundStyle(.secondary)
        GroupBox("Порядок работ") {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(s.steps.enumerated()), id: \.offset) { k, st in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(k + 1).").monospacedDigit().foregroundStyle(.secondary).frame(width: 22, alignment: .trailing)
                        Text(st).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(6)
        }
        if !s.decisions.isEmpty {
            GroupBox("Принятые решения и обоснование") {
                Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text("Решение").bold(); Text("Принято").bold(); Text("Почему").bold(); Text("Норматив").bold()
                    }
                    Divider()
                    ForEach(s.decisions) { d in
                        GridRow {
                            Text(d.title).frame(width: 140, alignment: .leading)
                            Text(d.value).bold().frame(width: 200, alignment: .leading)
                            Text(d.why).foregroundStyle(d.why.contains("НЕ ПРОХОДИТ") ? .red : .primary).frame(width: 300, alignment: .leading)
                            Text(d.ref).font(.caption).foregroundStyle(.blue).frame(width: 220, alignment: .leading)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(.callout)
                .textSelection(.enabled)
                .padding(6)
            }
        }
        if s.figures.contains(where: { if case .openingNode = $0.kind { return true }; return false }) { openingsTable(b) }
        let ctx = Drawings.Ctx(p: p, r: model.results, b: b)
        ForEach(s.figures) { f in
            VStack(alignment: .leading, spacing: 4) {
                Text(f.title).font(.headline)
                FigureView(kind: f.kind, ctx: ctx)
                    .aspectRatio(1 / f.aspect, contentMode: .fit)
                    .frame(maxWidth: 900)
            }
        }
        if !s.items.isEmpty {
            GroupBox("Материалы этапа (названия — как в магазине)") {
                ItemsGrid(items: s.items.filter { $0.qty > 0 }).padding(6)
            }
        }
    }

    func openingsTable(_ b: BuildPlan) -> some View {
        GroupBox("Проёмы: стандартные блоки и перемычки") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow { Text("Стена").bold(); Text("Тип").bold(); Text("В проекте").bold(); Text("Ближайший стандартный блок").bold(); Text("Черновой проём").bold(); Text("Перемычка").bold() }
                Divider()
                ForEach(b.openings) { o in
                    GridRow {
                        Text(o.wall)
                        Text(o.opening.kind.title)
                        Text("\(Drawings.mm(o.opening.width))×\(Drawings.mm(o.opening.height))").foregroundStyle(o.standard ? Color.primary : Color.orange)
                        Text(o.block.name).font(.caption).frame(width: 330, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                        Text("\(Drawings.mm(o.block.roW))×\(Drawings.mm(o.block.roH))").monospacedDigit()
                        Text(o.header.map { $0.title } ?? "—")
                    }
                }
            }
            .font(.callout)
            .padding(6)
            Text("Оранжевым — размеры, не совпадающие со стандартным черновым проёмом: такие окна делаются на заказ дороже и дольше.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Сводка

    @ViewBuilder func summary(_ b: BuildPlan) -> some View {
        Text("Сводка и закупка").font(.title2.bold())
        GroupBox("Ведомость пиломатериалов (по раскладке каркаса, хлысты 6 м)") {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                GridRow { Text("Сечение").bold(); Text("Назначение").bold(); Text("Погонаж, м").bold(); Text("Шт. по 6 м").bold(); Text("м³").bold() }
                Divider()
                ForEach(b.lumber) { r in
                    GridRow {
                        Text(r.sec.label).bold()
                        Text(r.use).font(.caption).frame(width: 420, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                        Text(fmt(r.totalLength, 0)).monospacedDigit()
                        Text("\(r.pieces)").monospacedDigit()
                        Text(fmt(r.volume, 2)).monospacedDigit()
                    }
                }
                Divider()
                GridRow {
                    Text("Итого").bold(); Text("")
                    Text(fmt(b.lumber.reduce(0) { $0 + $1.totalLength }, 0)).bold()
                    Text("\(b.lumber.reduce(0) { $0 + $1.pieces })").bold()
                    Text(fmt(b.lumber.reduce(0) { $0 + $1.volume }, 2)).bold()
                }
            }
            .padding(6)
        }
        ForEach(b.groups, id: \.title) { g in
            GroupBox(g.title) { ItemsGrid(items: g.items).padding(6) }
        }
        Text("Итого материалы ≈ \(rub(b.total)). \(Price.note)").font(.headline)
    }

    var norms: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Нормативные документы").font(.title2.bold())
            Text("Все решения в проекте сопровождаются ссылками на эти документы. Статус проверен по открытым реестрам на октябрь 2026 г.; перед строительством сверьте редакции в ФГИС ФЦС / «Техэксперт».")
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                ForEach(N.all) { n in
                    GridRow {
                        Text(n.code).bold().frame(width: 170, alignment: .leading)
                        Text(n.title).frame(width: 520, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                        Text(n.status).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .textSelection(.enabled)
        }
    }
}

struct ItemsGrid: View {
    let items: [WorkItem]
    var body: some View {
        let sum = items.reduce(0) { $0 + $1.cost }
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
            ForEach(items) { it in
                GridRow {
                    Text(it.name).frame(width: 380, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    Text(fmt(it.qty, it.digits)).bold().monospacedDigit().gridColumnAlignment(.trailing)
                    Text(it.unit).foregroundStyle(.secondary)
                    Text(it.price > 0 ? rub(it.cost) : "—").monospacedDigit().gridColumnAlignment(.trailing)
                    Text(it.note).font(.caption).foregroundStyle(.secondary).frame(width: 240, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                }
            }
            if sum > 0 {
                Divider()
                GridRow { Text("Итого").bold(); Text(""); Text(""); Text(rub(sum)).bold().monospacedDigit(); Text("") }
            }
        }
        .textSelection(.enabled)
    }
}

/// Схема на Canvas — тот же код, что и в PDF
struct FigureView: View {
    let kind: FigKind
    let ctx: Drawings.Ctx
    var body: some View {
        Canvas { g, size in
            g.withCGContext { cg in Drawings.render(kind, ctx, cg, CGRect(origin: .zero, size: size)) }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct PDFKitView: NSViewRepresentable {
    let data: Data
    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.document = PDFDocument(data: data)
        return v
    }
    func updateNSView(_ v: PDFView, context: Context) {}
}

struct PDFPreview: View {
    let data: Data
    let close: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Предпросмотр PDF · \(PDFDocument(data: data)?.pageCount ?? 0) стр. · \(data.count / 1024) КБ").font(.headline)
                Spacer()
                Button("Сохранить PDF…") { PDFExport.save(data) }.buttonStyle(.borderedProminent)
                Button("Закрыть", action: close).keyboardShortcut(.cancelAction)
            }
            .padding(10)
            Divider()
            PDFKitView(data: data)
        }
        .frame(minWidth: 820, minHeight: 760)
    }
}
