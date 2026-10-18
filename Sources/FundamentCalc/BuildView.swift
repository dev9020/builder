import SwiftUI
import PDFKit

/// Вкладка «Проект дома»: этапы от участка до кровли с обоснованиями, схемами и материалами
struct BuildView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var p: Project
    var show3D: (Stage3D, Int) -> Void = { _, _ in }
    @State private var sel = 0          // ≥ 0 — этап, −1 — сводка и закупка, −2 — нормативы, −3 — стандартные материалы, −4 — соединения
    @State private var pdf: Data?
    @State private var busy = false

    /// Только содержимое выбранного раздела, без списка и прокрутки (для отладочного рендера)
    var plainStage: Int? = nil

    var body: some View {
        let b = model.plan
        if let i = plainStage {
            VStack(alignment: .leading, spacing: 14) {
                page(i, b)
            }
            .padding(16).frame(width: 1000, alignment: .leading)
        } else {
            full(b)
        }
    }

    func full(_ b: BuildPlan) -> some View {
        HStack(spacing: 0) {
            List(selection: Binding(get: { sel }, set: { sel = $0 ?? 0 })) {
                Section("Дом своими руками") {
                    Label("Порядок строительства", systemImage: "list.number").tag(-5)
                    Label("Стандартные материалы", systemImage: "square.grid.3x3.square").tag(-3)
                    Label("Планировка, мебель, сантехника", systemImage: "sofa").tag(-6)
                    Label("Соединения и крепёж", systemImage: "link").tag(-4)
                }
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
                    page(sel, b)
                }
                .padding(16)
                .frame(maxWidth: 980, alignment: .leading)
            }
        }
        .sheet(isPresented: Binding(get: { pdf != nil }, set: { if !$0 { pdf = nil } })) {
            if let pdf { PDFPreview(data: pdf) { self.pdf = nil } }
        }
    }

    @ViewBuilder func page(_ i: Int, _ b: BuildPlan) -> some View {
        if i >= 0 && i < b.stages.count { stage(b.stages[i], b) }
        else if i == -1 { summary(b) }
        else if i == -3 { modulePage(b) }
        else if i == -4 { jointsPage(b) }
        else if i == -5 { orderPage(b) }
        else if i == -6 { layoutPage(b) }
        else { norms }
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
            let bad = b.checks.filter { !$0.ok }.count
            if bad > 0 {
                Button { p.fitToModule() } label: { Label("Подогнать под стандартные материалы (\(bad))", systemImage: "square.grid.3x3.square") }
                    .help("Размеры дома — кратно листу 1250, шаг 625, стойка 3000, проёмы — под стандартные окна и двери на сетке стоек")
            }
            Spacer()
            Text("Материалы ≈ \(rub(b.total))").font(.headline).foregroundStyle(Color.accentColor)
        }
    }


    // MARK: - Этап

    @ViewBuilder func stage(_ s: BuildStage, _ b: BuildPlan) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label("Этап \(s.number). \(s.title)", systemImage: s.icon).font(.title2.bold())
            Spacer()
            if plainStage == nil { Button { show3D(s.scene, Int.max) } label: { Label("Показать в 3D", systemImage: "cube.transparent") } }
        }
        Text(s.goal).foregroundStyle(.secondary)
        if !s.when.isEmpty {
            Label { Text("Когда: ").bold() + Text(s.when) } icon: { Image(systemName: "clock").foregroundStyle(.blue) }
                .font(.callout).fixedSize(horizontal: false, vertical: true)
        }
        let all3D = Steps3D.make(p, model.results, b.frame)
        let shots = all3D.enumerated().filter { $0.element.stage == s.scene }
        if shots.count > 1 {
            GroupBox("Шаги на 3D-модели (вкладка «3D», бегунок «Этап»)") {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(shots, id: \.offset) { k, st in
                        HStack(alignment: .top, spacing: 8) {
                            Button { show3D(st.stage, st.sub) } label: { Image(systemName: "cube.transparent") }
                                .buttonStyle(.borderless).help("Открыть этот шаг в 3D")
                            (Text("Шаг \(k + 1). \(st.title). ").bold() + Text(st.note).foregroundColor(.secondary))
                                .font(.callout).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }
        }
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
        if !s.tools.isEmpty {
            GroupBox("Инструмент") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), alignment: .topLeading)], alignment: .leading, spacing: 6) {
                    ForEach(s.tools, id: \.self) { t in
                        Label { Text(t).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "hammer").foregroundStyle(.orange) }
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(.callout).padding(6)
            }
        }
        if !s.fasteners.isEmpty {
            GroupBox("Крепёж: что крепим → чем → каким инструментом") { FastenerGrid(rows: s.fasteners).padding(6) }
        }
        ForEach(s.guides) { g in GuideBox(guide: g) }
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
        if let t = s.table { GroupBox(t.title) { StageTableView(table: t).padding(6) } }
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

    // MARK: - Стандартные материалы

    @ViewBuilder func modulePage(_ b: BuildPlan) -> some View {
        Label("Стандартные материалы: дом без лишних резов", systemImage: "square.grid.3x3.square").font(.title2.bold())
        Text("Все размеры дома подогнаны под то, что продаётся в магазине: шаг 625 мм, стойка — целая доска 3000, наружные размеры кратны листу 1250, окна и двери — типовые. Почти всё ставится целиком, а там, где рез неизбежен, он один и без отходов (лист или плита пополам).")
            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        GroupBox("Проверка проекта") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(b.checks) { c in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: c.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(c.ok ? .green : .orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.title).bold()
                            Text(c.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if b.checks.contains(where: { !$0.ok }) {
                    Button { p.fitToModule() } label: { Label("Подогнать всё под модуль", systemImage: "wand.and.stars") }.buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(6)
        }
        GroupBox("Карта материалов: размер → как ложится в модуль → резка") {
            Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 5) {
                GridRow { Text("Материал").bold(); Text("Стандартный размер").bold(); Text("Правило модуля").bold(); Text("Резка").bold(); Text("Кол-во").bold() }
                Divider()
                ForEach(b.kit) { k in
                    GridRow {
                        VStack(alignment: .leading, spacing: 1) { Text(k.material).bold(); Text(k.group).font(.caption2).foregroundStyle(.secondary) }.frame(width: 170, alignment: .leading)
                        Text(k.size).frame(width: 150, alignment: .leading)
                        Text(k.rule).font(.callout).frame(width: 260, alignment: .leading)
                        Label { Text(k.cut).font(.callout) } icon: { Image(systemName: k.whole ? "checkmark.seal" : "scissors").foregroundStyle(k.whole ? .green : .orange) }
                            .frame(width: 200, alignment: .leading)
                        Text(k.qty).font(.callout).monospacedDigit().frame(width: 150, alignment: .leading)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .textSelection(.enabled).padding(6)
        }
        let ctx = Drawings.Ctx(p: p, r: model.results, b: b)
        let w0 = BuildPlan.wallsExt0First(b.frame)
        figures([Figure(kind: .wallSection, title: "Разрез стены: брус, утеплитель, наружная и внутренняя отделка с размерами", aspect: 0.95),
                 Figure(kind: .wallPlan, title: "Стена в плане: шаг 625, плита 600 в распор, стык ОСП на стойке", aspect: 0.4)]
                + (w0.map { i in [0, 1, 2].map { Figure(kind: .sheetLayout(i, $0), title: ["Раскладка ОСП снаружи", "Раскладка утеплителя", "Раскладка ГКЛ изнутри"][$0] + " — стена \(b.frame.walls[i].name)", aspect: 0.42) } } ?? []), ctx)
    }

    @ViewBuilder func jointsPage(_ b: BuildPlan) -> some View {
        Label("Соединения и крепёж: чем и как соединять брус", systemImage: "link").font(.title2.bold())
        Text("Каркас собирается на гвоздях и саморезах по нормативной схеме — именно количество и шаг крепежа делают узел прочным. Гвозди держат на срез лучше саморезов того же диаметра; саморезы — там, где нужна стяжка или разборность.")
            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        GroupBox("Таблица соединений") {
            Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 5) {
                GridRow { Text("Узел").bold(); Text("Чем").bold(); Text("Сколько / шаг").bold(); Text("Инструмент").bold() }
                Divider()
                ForEach(Array(Kit.joints.enumerated()), id: \.offset) { _, j in
                    GridRow {
                        Text(j.what).bold().frame(width: 200, alignment: .leading)
                        Text(j.how).frame(width: 300, alignment: .leading)
                        Text(j.qty).frame(width: 160, alignment: .leading)
                        Text(j.tool).font(.callout).foregroundStyle(.secondary).frame(width: 200, alignment: .leading)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.callout).textSelection(.enabled).padding(6)
        }
        let ctx = Drawings.Ctx(p: p, r: model.results, b: b)
        figures([Figure(kind: .fasteners, title: "Основные узлы каркаса", aspect: 0.62),
                 Figure(kind: .rigidity, title: "Откуда жёсткость стены: временные укосины, раскосы, ОСП", aspect: 0.42)], ctx)
        GuideBox(guide: Fasteners.rule)
        GuideBox(guide: Guides.walls(p, b.frame)[2])
    }

    // MARK: - Планировка и сантехника

    @ViewBuilder func layoutPage(_ b: BuildPlan) -> some View {
        let L = b.layout
        Label("Планировка, мебель и сантехника", systemImage: "sofa").font(.title2.bold())
        Text("Комнаты найдены по стенам и перегородкам, назначение определено по площади, окнам и дверям — его можно поменять. По расстановке приборов выводятся точки воды и канализации, по ним — разводка, ввод от скважины и выпуск в септик.")
            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        GroupBox("Комнаты") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                ForEach(L.rooms) { r in
                    GridRow {
                        Text("\(fmt(r.area, 1)) м²").monospacedDigit().frame(width: 70, alignment: .trailing)
                        Picker("", selection: Binding(get: { r.type }, set: { t in
                            p.roomMarks.removeAll { m in Rooms.contains(r, m.at) }
                            p.roomMarks.append(RoomMark(at: r.seed, type: t))
                        })) { ForEach(RoomType.allCases) { Text($0.title).tag($0) } }
                        .labelsHidden().frame(width: 240)
                        Text(L.furniture.filter { $0.room == r.id }.map(\.name).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(6)
        }
        GroupBox("Очистное сооружение") {
            Picker("", selection: $p.septic) { ForEach(SepticType.allCases) { Text($0.title).tag($0) } }.labelsHidden().padding(6)
        }
        let ctx = Drawings.Ctx(p: p, r: model.results, b: b)
        figures([Figure(kind: .furniturePlan, title: "Планировка с мебелью", aspect: 0.7)], ctx)
        GroupBox("Точки воды и канализации (высоты от чистого пола)") {
            StageTableView(table: PlumbingWorks.pointsTable(L)).padding(6)
        }
        figures([Figure(kind: .plumbingPlan, title: "Разводка: коллектор, лучи PE-Xa, канализация Ø110/Ø50, ввод и выпуск", aspect: 0.75),
                 Figure(kind: .siteNetworks, title: "Участок: скважина, септик, трассы", aspect: 0.75),
                 Figure(kind: .sewerProfile, title: "Профиль канализации до септика", aspect: 0.4)], ctx)
    }

    // MARK: - Порядок строительства

    @ViewBuilder func orderPage(_ b: BuildPlan) -> some View {
        Label("Порядок строительства: что за чем", systemImage: "list.number").font(.title2.bold())
        Text("Этапы идут строго по порядку: каждый опирается на предыдущий. Нажмите этап слева — там порядок работ, инструмент, крепёж, инструкции, схемы и материалы.")
            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        GroupBox("Решить до начала стройки") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(BuildPlan.decideEarly(p).enumerated()), id: \.offset) { _, d in
                    Label { Text(d).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(6)
        }
        GroupBox("Пол: какой и на каком этапе") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(BuildPlan.floorTimeline(p, b).enumerated()), id: \.offset) { _, t in
                    HStack(alignment: .top) { Text(t.0).bold().frame(width: 230, alignment: .leading); Text(t.1).fixedSize(horizontal: false, vertical: true) }
                }
            }
            .font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(6)
        }
        GroupBox("Этапы") {
            Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 6) {
                ForEach(b.stages) { s in
                    GridRow {
                        Text("\(s.number)").font(.title3.bold()).foregroundStyle(Color.accentColor).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.title).bold()
                            Text(s.goal).font(.caption).foregroundStyle(.secondary)
                        }.frame(width: 360, alignment: .leading)
                        Text(s.when).font(.callout).frame(width: 420, alignment: .leading)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(6)
        }
    }

    func figures(_ fs: [Figure], _ ctx: Drawings.Ctx) -> some View {
        ForEach(fs) { f in
            VStack(alignment: .leading, spacing: 4) {
                Text(f.title).font(.headline)
                FigureView(kind: f.kind, ctx: ctx).aspectRatio(1 / f.aspect, contentMode: .fit).frame(maxWidth: 900)
            }
        }
    }

    // MARK: - Сводка

    @ViewBuilder func summary(_ b: BuildPlan) -> some View {
        Text("Сводка и закупка").font(.title2.bold())
        GroupBox("Ведомость пиломатериалов (стандартные длины 3 и 6 м)") {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                GridRow { Text("Доска").bold(); Text("Назначение").bold(); Text("Погонаж, м").bold(); Text("Шт.").bold(); Text("м³").bold() }
                Divider()
                ForEach(b.lumber) { r in
                    GridRow {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(r.sec.label)×\(Int(r.stock * 1000))").bold()
                            if r.whole { Text("целиком, без резки").font(.caption2).foregroundStyle(.green) }
                        }
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

struct StageTableView: View {
    let table: StageTable
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
            GridRow { ForEach(table.head, id: \.self) { Text($0).bold() } }
            Divider()
            ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                GridRow { ForEach(Array(row.enumerated()), id: \.offset) { _, c in Text(c) } }
            }
        }
        .font(.callout).textSelection(.enabled)
    }
}

struct FastenerGrid: View {
    let rows: [Fastener]
    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 5) {
            ForEach(rows) { f in
                GridRow {
                    Text(f.what).bold().frame(width: 220, alignment: .leading)
                    Text(f.item).frame(width: 380, alignment: .leading)
                    Label { Text(f.how) } icon: { Image(systemName: "wrench.adjustable").foregroundStyle(.secondary) }.foregroundStyle(.secondary).frame(width: 260, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.callout).textSelection(.enabled)
    }
}

struct GuideBox: View {
    let guide: Guide
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(guide.steps.enumerated()), id: \.offset) { k, st in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(k + 1)").font(.caption.bold()).foregroundStyle(.white).frame(width: 18, height: 18)
                            .background(Circle().fill(Color.accentColor))
                        Text(st).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                }
                if !guide.tip.isEmpty {
                    Label { Text(guide.tip).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "lightbulb.fill").foregroundStyle(.yellow) }
                        .font(.callout).padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.yellow.opacity(0.12)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(6)
        } label: {
            Label(guide.title, systemImage: "wrench.and.screwdriver").font(.headline)
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
