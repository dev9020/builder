import SwiftUI

struct PlanTransform {
    let scale: Double
    let lo: V2
    let origin: CGPoint

    init(rings: [[V2]], size: CGSize) {
        let (l, h) = Geo.bbox(rings)
        lo = l - V2(2, 2)
        let span = (h + V2(2, 2)) - lo
        scale = max(1, min((Double(size.width) - 40) / span.x, (Double(size.height) - 40) / span.y))
        origin = CGPoint(x: (Double(size.width) - span.x * scale) / 2,
                         y: Double(size.height) - (Double(size.height) - span.y * scale) / 2)
    }
    func s(_ v: V2) -> CGPoint { CGPoint(x: origin.x + (v.x - lo.x) * scale, y: origin.y - (v.y - lo.y) * scale) }
    func w(_ p: CGPoint) -> V2 { V2(lo.x + (p.x - origin.x) / scale, lo.y + (origin.y - p.y) / scale) }
}

private enum PlanHit {
    case opening(UUID)
    case partition(UUID)
    case segment(WallSegment)
}

private enum PlanDrag {
    case edge(Int, DragSnapshot)
    case partition(UUID, Partition)
    case opening(UUID)
}

struct PlanEditorView: View {
    @EnvironmentObject var p: Project
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var ed: EditorState
    @State private var frozen: PlanTransform?
    @State private var drag: PlanDrag?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Picker("", selection: $ed.mode) {
                        ForEach(EditorState.Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    if ed.mode == .draw {
                        Picker("", selection: $ed.drawMaterial) {
                            ForEach(WallMaterial.allCases) { Text($0.short).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        Toggle("Несущая", isOn: $ed.drawOnFoundation).toggleStyle(.checkbox).fixedSize()
                            .help("Несущая перегородка получает свой фундамент")
                    }
                    if ed.mode == .opening {
                        Picker("", selection: $ed.openingKind) {
                            ForEach(OpeningKind.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    Spacer(minLength: 0)
                    Text(hint).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .controlSize(.small)
                .padding(.horizontal, 8).padding(.vertical, 4)
                GeometryReader { geo in
                    canvas(geo.size)
                }
                .background(Color(nsColor: .textBackgroundColor))
            }
            Divider()
            inspector.frame(width: 290)
        }
        .onChange(of: ed.drawMaterial) { _, m in ed.drawOnFoundation = m.isMasonry }
    }

    var hint: String {
        switch ed.mode {
        case .select: return "Тяните стену — меняется размер дома; тяните перегородку, окно или дверь — перемещение"
        case .draw: return "Протяните мышью от стены до стены"
        case .opening: return "Кликните по стене, чтобы поставить: \(ed.openingKind.title.lowercased())"
        }
    }

    // MARK: - Холст

    func canvas(_ size: CGSize) -> some View {
        let rings = p.rings
        let tr = frozen ?? PlanTransform(rings: rings, size: size)
        let segs = p.segments
        let res = model.results
        let lineNames = Dictionary(uniqueKeysWithValues: res.loads.lines.map { ($0.id, $0.name) })
        let ops = p.validOpenings
        let bg = Color(nsColor: .textBackgroundColor)
        return Canvas { ctx, sz in
            // сетка 1 м
            let (lo, hi) = (tr.w(CGPoint(x: 0, y: sz.height)), tr.w(CGPoint(x: sz.width, y: 0)))
            var grid = Path()
            var x = lo.x.rounded(.down)
            while x <= hi.x { grid.move(to: tr.s(V2(x, lo.y))); grid.addLine(to: tr.s(V2(x, hi.y))); x += 1 }
            var y = lo.y.rounded(.down)
            while y <= hi.y { grid.move(to: tr.s(V2(lo.x, y))); grid.addLine(to: tr.s(V2(hi.x, y))); y += 1 }
            ctx.stroke(grid, with: .color(.gray.opacity(0.15)), lineWidth: 0.5)

            // контур фундамента
            let fcol = Color.gray.opacity(0.28)
            switch p.selectedFoundation {
            case .strip:
                for sl in res.strip.lines {
                    guard let sec = res.strip.section(sl.line) else { continue }
                    var path = Path()
                    let ext = sl.line.dir * (sec.b / 2)
                    path.move(to: tr.s(sl.line.a - ext)); path.addLine(to: tr.s(sl.line.b + ext))
                    ctx.stroke(path, with: .color(fcol), lineWidth: sec.b * tr.scale)
                }
            case .slab:
                var path = Path()
                for r in res.slab.rings { path.addLines(r.map(tr.s)); path.closeSubpath() }
                ctx.fill(path, with: .color(fcol), style: FillStyle(eoFill: true))
            case .piles:
                for pl in res.piles.lines {
                    var path = Path()
                    path.move(to: tr.s(pl.line.a)); path.addLine(to: tr.s(pl.line.b))
                    ctx.stroke(path, with: .color(fcol), lineWidth: res.piles.bg * tr.scale)
                }
                for pos in res.piles.positions {
                    let r = max(res.piles.D / 2 * tr.scale, 4)
                    let c = tr.s(pos)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(.black.opacity(0.55)))
                }
            }

            // площадь дома
            var fill = Path()
            for r in rings { fill.addLines(r.map(tr.s)); fill.closeSubpath() }
            ctx.fill(fill, with: .color(.accentColor.opacity(0.05)), style: FillStyle(eoFill: true))

            // стены
            for s in segs {
                var path = Path()
                path.move(to: tr.s(s.a)); path.addLine(to: tr.s(s.b))
                let wpx = max(p.thickness(s.material) * tr.scale, 3)
                if ed.selectedSegment == s.id {
                    ctx.stroke(path, with: .color(.yellow), lineWidth: wpx + 6)
                }
                ctx.stroke(path, with: .color(s.material.planColor), style: StrokeStyle(lineWidth: wpx, lineCap: .square))
                let mid = (s.a + s.b) / 2
                let n = V2(-(s.b - s.a).unit.y, (s.b - s.a).unit.x)
                let inward = Geo.contains(mid + n * 0.3, rings) ? n : -n
                let pos = tr.s(mid - inward * (0.45 + p.thickness(s.material) / 2))
                ctx.draw(Text("\(lineNames[s.id] ?? "") \(fmt(s.length)) м").font(.system(size: 10)).foregroundColor(.secondary), at: pos)
            }
            for s in segs where s.sub > 0 {
                let c = tr.s(s.a)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(.black))
            }
            // перегородки
            for (i, pt) in p.partitions.enumerated() {
                var path = Path()
                path.move(to: tr.s(pt.a)); path.addLine(to: tr.s(pt.b))
                let wpx = max(pt.thickness * tr.scale, 2)
                if ed.selectedPartition == pt.id {
                    ctx.stroke(path, with: .color(.yellow), lineWidth: wpx + 6)
                }
                ctx.stroke(path, with: .color(pt.material.planColor.opacity(pt.onFoundation ? 1 : 0.6)),
                           style: StrokeStyle(lineWidth: wpx, dash: pt.onFoundation ? [] : [6, 3]))
                let mid = tr.s((pt.a + pt.b) / 2)
                ctx.draw(Text("П\(i + 1) \(fmt(pt.length))").font(.system(size: 10, weight: .medium)),
                         at: CGPoint(x: mid.x + 5, y: mid.y - 9), anchor: .leading)
            }
            // проёмы
            for o in ops {
                guard let l = p.hostLine(o.host) else { continue }
                let dir = (l.b - l.a).unit
                let c = l.a + dir * o.pos
                let a = c - dir * (o.width / 2), b = c + dir * (o.width / 2)
                var t = 0.2
                var inward = V2(-dir.y, dir.x)
                switch o.host {
                case .edge(let ei):
                    if let s = segs.first(where: { $0.edge == ei && Geo.distToSegment(c, $0.a, $0.b) < 1e-6 }) {
                        t = p.thickness(s.material)
                    }
                    if !Geo.contains(c + inward * 0.3, rings) { inward = -inward }
                case .partition(let id):
                    t = p.partitions.first { $0.id == id }?.thickness ?? 0.1
                }
                var gap = Path(); gap.move(to: tr.s(a)); gap.addLine(to: tr.s(b))
                if ed.selectedOpening == o.id { ctx.stroke(gap, with: .color(.yellow), lineWidth: t * tr.scale + 8) }
                ctx.stroke(gap, with: .color(bg), lineWidth: t * tr.scale + 1)
                let n = V2(-dir.y, dir.x)
                var ends = Path()
                for e in [a, b] { ends.move(to: tr.s(e - n * (t / 2))); ends.addLine(to: tr.s(e + n * (t / 2))) }
                ctx.stroke(ends, with: .color(.primary), lineWidth: 1)
                if !o.kind.isDoor {
                    var gl = Path()
                    let ks: [Double] = o.kind == .panoramic ? [-0.25, 0, 0.25] : [-0.15, 0.15]
                    for k in ks { gl.move(to: tr.s(a + n * (t * k))); gl.addLine(to: tr.s(b + n * (t * k))) }
                    ctx.stroke(gl, with: .color(.blue), lineWidth: o.kind == .panoramic ? 1.6 : 1.2)
                } else if o.kind == .glassDoor && o.width >= 1.6 {
                    // раздвижной портал: две створки со смещением
                    var gl = Path()
                    let m = (a + b) / 2
                    gl.move(to: tr.s(a + n * (t * 0.15))); gl.addLine(to: tr.s(m + dir * 0.1 + n * (t * 0.15)))
                    gl.move(to: tr.s(m - dir * 0.1 - n * (t * 0.15))); gl.addLine(to: tr.s(b - n * (t * 0.15)))
                    ctx.stroke(gl, with: .color(.blue), lineWidth: 2.5)
                } else {
                    let hinge = a + inward * (t / 2), tip = hinge + inward * o.width
                    var leaf = Path(); leaf.move(to: tr.s(hinge)); leaf.addLine(to: tr.s(tip))
                    ctx.stroke(leaf, with: .color(o.kind == .glassDoor ? .blue : .brown), lineWidth: 2)
                    var arc = Path()
                    arc.move(to: tr.s(tip))
                    for k in 1...12 {
                        let ang = Double(k) / 12 * .pi / 2
                        arc.addLine(to: tr.s(hinge + inward * (o.width * cos(ang)) + dir * (o.width * sin(ang))))
                    }
                    ctx.stroke(arc, with: .color(.brown.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
            }
            // габариты
            let (blo, bhi) = Geo.bbox(rings)
            var dim = Path()
            let yy = bhi.y + 1.2, xx = blo.x - 1.2
            dim.move(to: tr.s(V2(blo.x, yy))); dim.addLine(to: tr.s(V2(bhi.x, yy)))
            dim.move(to: tr.s(V2(xx, blo.y))); dim.addLine(to: tr.s(V2(xx, bhi.y)))
            for v in [V2(blo.x, yy), V2(bhi.x, yy)] { dim.move(to: tr.s(v - V2(0, 0.15))); dim.addLine(to: tr.s(v + V2(0, 0.15))) }
            for v in [V2(xx, blo.y), V2(xx, bhi.y)] { dim.move(to: tr.s(v - V2(0.15, 0))); dim.addLine(to: tr.s(v + V2(0.15, 0))) }
            ctx.stroke(dim, with: .color(.primary.opacity(0.6)), lineWidth: 1)
            ctx.draw(Text("\(fmt(bhi.x - blo.x)) м").font(.system(size: 12, weight: .semibold)), at: tr.s(V2((blo.x + bhi.x) / 2, yy + 0.35)))
            ctx.draw(Text("\(fmt(bhi.y - blo.y)) м").font(.system(size: 12, weight: .semibold)), at: tr.s(V2(xx - 0.5, (blo.y + bhi.y) / 2)))

            // черновик перегородки
            if let a = ed.draftA, let b = ed.draftB {
                var path = Path()
                path.move(to: tr.s(a)); path.addLine(to: tr.s(b))
                ctx.stroke(path, with: .color(ed.drawMaterial.planColor),
                           style: StrokeStyle(lineWidth: max(ed.drawMaterial.partitionThickness(bearing: ed.drawOnFoundation) * tr.scale, 3)))
                ctx.draw(Text("\(fmt((b - a).len)) м").font(.system(size: 12, weight: .bold)), at: tr.s(b) + CGPoint(x: 10, y: -12), anchor: .leading)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in onDrag(v, tr) }
                .onEnded { v in onDragEnd(v, tr) }
        )
    }

    // MARK: - Жесты

    func onDrag(_ v: DragGesture.Value, _ tr: PlanTransform) {
        switch ed.mode {
        case .draw:
            let a = snap(tr.w(v.startLocation))
            ed.draftA = a
            ed.draftB = ortho(a, snap(tr.w(v.location)))
        case .opening:
            break
        case .select:
            if drag == nil {
                guard hypot(v.translation.width, v.translation.height) >= 4, let h = hit(tr.w(v.startLocation), tr) else { return }
                frozen = tr
                switch h {
                case .segment(let s):
                    drag = .edge(s.edge, p.snapshot(edge: s.edge))
                    ed.selectedSegment = s.id; ed.selectedPartition = nil; ed.selectedOpening = nil
                case .partition(let id):
                    if let pt = p.partitions.first(where: { $0.id == id }) { drag = .partition(id, pt) }
                    ed.selectedPartition = id; ed.selectedSegment = nil; ed.selectedOpening = nil
                case .opening(let id):
                    drag = .opening(id)
                    ed.selectedOpening = id; ed.selectedSegment = nil; ed.selectedPartition = nil
                }
            }
            let w0 = tr.w(v.startLocation), w1 = tr.w(v.location)
            switch drag {
            case .edge(let e, let snap):
                let horizontal = abs(snap.edge.b.y - snap.edge.a.y) < 1e-9
                let d = ((horizontal ? w1.y - w0.y : w1.x - w0.x) * 10).rounded() / 10
                p.applyEdgeDrag(edge: e, delta: d, from: snap)
            case .partition(let id, let orig):
                let dir = (orig.b - orig.a).unit, n = V2(-dir.y, dir.x)
                let d = (dot2(w1 - w0, n) * 10).rounded() / 10
                if let i = p.partitions.firstIndex(where: { $0.id == id }) {
                    p.partitions[i].a = orig.a + n * d
                    p.partitions[i].b = orig.b + n * d
                }
            case .opening(let id):
                if let i = p.openings.firstIndex(where: { $0.id == id }), let l = p.hostLine(p.openings[i].host) {
                    let len = (l.b - l.a).len, w = p.openings[i].width
                    let u = (dot2(w1 - l.a, (l.b - l.a).unit) * 20).rounded() / 20
                    p.openings[i].pos = min(max(u, w / 2 + 0.05), len - w / 2 - 0.05)
                }
            case .none: break
            }
        }
    }

    func onDragEnd(_ v: DragGesture.Value, _ tr: PlanTransform) {
        defer { drag = nil; frozen = nil }
        switch ed.mode {
        case .draw:
            if let a = ed.draftA, let b = ed.draftB, (b - a).len >= 0.3 {
                let np = Partition(a: a, b: b, material: ed.drawMaterial, onFoundation: ed.drawOnFoundation)
                p.partitions.append(np)
                ed.selectedPartition = np.id
                ed.selectedSegment = nil; ed.selectedOpening = nil
            }
            ed.draftA = nil; ed.draftB = nil
        case .opening:
            addOpening(at: tr.w(v.location), tr)
        case .select:
            if drag == nil && hypot(v.translation.width, v.translation.height) < 4 {
                select(tr.w(v.location), tr)
            }
        }
    }

    func addOpening(at wpt: V2, _ tr: PlanTransform) {
        let tol = max(12 / tr.scale, 0.2)
        var best: (host: OpeningHost, dist: Double, pos: Double)?
        for (i, e) in p.edges.enumerated() {
            let d = Geo.distToSegment(wpt, e.a, e.b)
            if d < tol && d < (best?.dist ?? .infinity) { best = (.edge(i), d, dot2(wpt - e.a, (e.b - e.a).unit)) }
        }
        for pt in p.partitions {
            let d = Geo.distToSegment(wpt, pt.a, pt.b)
            if d < tol && d < (best?.dist ?? .infinity) { best = (.partition(pt.id), d, dot2(wpt - pt.a, (pt.b - pt.a).unit)) }
        }
        guard let b = best, let l = p.hostLine(b.host) else { return }
        var o = Opening.make(ed.openingKind, host: b.host, pos: (b.pos * 20).rounded() / 20)
        let len = (l.b - l.a).len
        guard len > o.width + 0.2 else { return }
        o.pos = min(max(o.pos, o.width / 2 + 0.05), len - o.width / 2 - 0.05)
        p.openings.append(o)
        ed.selectedOpening = o.id; ed.selectedSegment = nil; ed.selectedPartition = nil
    }

    private func hit(_ v: V2, _ tr: PlanTransform) -> PlanHit? {
        let tol = max(10 / tr.scale, 0.12)
        for o in p.validOpenings {
            guard let l = p.hostLine(o.host) else { continue }
            let dir = (l.b - l.a).unit, c = l.a + dir * o.pos
            if Geo.distToSegment(v, c - dir * (o.width / 2), c + dir * (o.width / 2)) < tol { return .opening(o.id) }
        }
        let pBest = p.partitions.min { Geo.distToSegment(v, $0.a, $0.b) < Geo.distToSegment(v, $1.a, $1.b) }
        let sBest = p.segments.min { Geo.distToSegment(v, $0.a, $0.b) < Geo.distToSegment(v, $1.a, $1.b) }
        let dp = pBest.map { Geo.distToSegment(v, $0.a, $0.b) } ?? .infinity
        let ds = sBest.map { Geo.distToSegment(v, $0.a, $0.b) } ?? .infinity
        if dp <= ds, dp < tol, let pb = pBest { return .partition(pb.id) }
        if ds < tol, let sb = sBest { return .segment(sb) }
        return nil
    }

    func select(_ v: V2, _ tr: PlanTransform) {
        ed.selectedSegment = nil; ed.selectedPartition = nil; ed.selectedOpening = nil
        switch hit(v, tr) {
        case .opening(let id): ed.selectedOpening = id
        case .partition(let id): ed.selectedPartition = id
        case .segment(let s):
            ed.selectedSegment = s.id
            ed.splitDistance = (s.length / 2 * 10).rounded() / 10
        case .none: break
        }
    }

    func snap(_ v: V2) -> V2 {
        var pts: [V2] = p.rings.flatMap { $0 }
        pts += p.segments.map(\.a)
        pts += p.partitions.flatMap { [$0.a, $0.b] }
        if let best = pts.min(by: { ($0 - v).len < ($1 - v).len }), (best - v).len < 0.3 { return best }
        let g = V2((v.x * 10).rounded() / 10, (v.y * 10).rounded() / 10)
        var lines: [(V2, V2)] = p.segments.map { ($0.a, $0.b) }
        lines += p.partitions.map { ($0.a, $0.b) }
        if let l = lines.min(by: { Geo.distToSegment(g, $0.0, $0.1) < Geo.distToSegment(g, $1.0, $1.1) }),
           Geo.distToSegment(g, l.0, l.1) < 0.25 {
            return Geo.project(g, l.0, l.1)
        }
        return g
    }

    func ortho(_ a: V2, _ b: V2) -> V2 {
        let d = b - a
        if abs(d.y) < abs(d.x) * 0.14 { return V2(b.x, a.y) }
        if abs(d.x) < abs(d.y) * 0.14 { return V2(a.x, b.y) }
        return b
    }

    // MARK: - Инспектор

    var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let id = ed.selectedOpening, let idx = p.openings.firstIndex(where: { $0.id == id }) {
                    openingInspector(idx)
                } else if let id = ed.selectedSegment, let seg = p.segments.first(where: { $0.id == id }) {
                    segmentInspector(seg)
                } else if let id = ed.selectedPartition, let idx = p.partitions.firstIndex(where: { $0.id == id }) {
                    partitionInspector(idx)
                } else {
                    Text("Редактор плана").font(.headline)
                    Text("• Тяните наружную стену мышью, чтобы изменить размер дома (шаг 0.1 м).\n• Клик по стене: выбор материала, деление на участки.\n• «Нарисовать перегородку»: протяните мышью, есть привязка к углам и стенам.\n• «Окна и двери»: клик по стене ставит проём; в режиме выбора его можно двигать вдоль стены.\n• Сплошные перегородки — несущие (со своим фундаментом), пунктирные опираются на перекрытие.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Divider()
                Text("Перегородки").font(.headline)
                if p.partitions.isEmpty { Text("Нет").foregroundStyle(.secondary) }
                ForEach(Array(p.partitions.enumerated()), id: \.element.id) { i, pt in
                    HStack {
                        Circle().fill(pt.material.planColor).frame(width: 10, height: 10)
                        Text("П\(i + 1): \(pt.material.short) \(Int(pt.thickness * 1000)), \(fmt(pt.length)) м\(pt.onFoundation ? ", несущ." : "")")
                            .font(.callout)
                        Spacer()
                        Button { selectPartition(pt.id) } label: { Image(systemName: "scope") }.buttonStyle(.borderless)
                        Button(role: .destructive) {
                            if ed.selectedPartition == pt.id { ed.selectedPartition = nil }
                            p.removePartition(pt.id)
                        } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    }
                }
                Text("Окон: \(p.validOpenings.filter { !$0.kind.isDoor }.count), дверей: \(p.validOpenings.filter { $0.kind.isDoor }.count)")
                    .font(.callout).foregroundStyle(.secondary)
                Divider()
                Text("Легенда").font(.headline)
                ForEach(WallMaterial.allCases) { m in
                    HStack {
                        RoundedRectangle(cornerRadius: 2).fill(m.planColor).frame(width: 22, height: 8)
                        Text(m.title).font(.caption)
                    }
                }
                HStack {
                    Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 22, height: 8)
                    Text("Фундамент (\(p.selectedFoundation.title.lowercased()))").font(.caption)
                }
            }
            .padding(12)
        }
    }

    func selectPartition(_ id: UUID) { ed.selectedPartition = id; ed.selectedSegment = nil; ed.selectedOpening = nil }

    func segmentInspector(_ seg: WallSegment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            let name = model.results.loads.lines.first { $0.id == seg.id }?.name ?? ""
            Text("Наружная стена \(name)").font(.headline)
            Text("Длина участка: \(fmt(seg.length)) м · толщина \(Int(p.thickness(seg.material) * 1000)) мм").foregroundStyle(.secondary)
            Picker("Материал", selection: Binding(get: { seg.material }, set: { p.setMaterial(seg, $0) })) {
                ForEach(WallMaterial.allCases) { Text($0.title).tag($0) }
            }
            if let ll = model.results.loads.lines.firstIndex(where: { $0.id == seg.id }) {
                let q = model.results.loads.stripLoads[ll]
                Text("Нагрузка на фундамент: \(fmt(q.char, 1)) кН/м (норм.), \(fmt(q.design, 1)) кН/м (расч.)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Text("Разделить участок").font(.subheadline.weight(.semibold))
            NumField(title: "От начала", value: $ed.splitDistance, range: 0.3...max(0.3, seg.length - 0.3), step: 0.1)
            HStack {
                Button("Разделить") { p.split(seg, at: ed.splitDistance); ed.selectedSegment = "e\(seg.edge)-\(seg.sub)" }
                Button("Объединить сторону") { p.mergeEdge(seg.edge); ed.selectedSegment = "e\(seg.edge)-0" }
            }
            Button("Применить материал ко всем наружным") { p.setAllExterior(seg.material) }
        }
    }

    func partitionInspector(_ idx: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Перегородка П\(idx + 1)").font(.headline)
            Text("Длина: \(fmt(p.partitions[idx].length)) м").foregroundStyle(.secondary)
            Picker("Материал", selection: Binding(get: { p.partitions[idx].material }, set: { m in
                p.partitions[idx].material = m
                p.partitions[idx].thickness = m.partitionThickness(bearing: p.partitions[idx].onFoundation)
            })) {
                ForEach(WallMaterial.allCases) { Text($0.title).tag($0) }
            }
            NumField(title: "Толщина", value: $p.partitions[idx].thickness, range: 0.06...0.6, step: 0.01, digits: 3)
            Toggle("Несущая — на свой фундамент", isOn: Binding(get: { p.partitions[idx].onFoundation }, set: { v in
                p.partitions[idx].onFoundation = v
                p.partitions[idx].thickness = p.partitions[idx].material.partitionThickness(bearing: v)
            }))
            Text(p.partitions[idx].onFoundation
                 ? "Под стеной устраивается лента / ростверк, на неё опираются перекрытия."
                 : "Вес перегородки передаётся на перекрытие (для плиты — на плиту).")
                .font(.caption).foregroundStyle(.secondary)
            Button(role: .destructive) {
                let id = p.partitions[idx].id
                ed.selectedPartition = nil
                p.removePartition(id)
            } label: { Label("Удалить", systemImage: "trash") }
        }
    }

    func openingInspector(_ idx: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(p.openings[idx].kind.title).font(.headline)
            Picker("Тип", selection: Binding(get: { p.openings[idx].kind }, set: { k in
                let o = p.openings[idx]
                var n = Opening.make(k, host: o.host, pos: o.pos)
                n.id = o.id
                p.openings[idx] = n
            })) {
                ForEach(OpeningKind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            NumField(title: "Ширина", value: $p.openings[idx].width, range: 0.4...6, step: 0.05)
            NumField(title: "Высота", value: $p.openings[idx].height, range: 0.4...2.6, step: 0.05)
            if !p.openings[idx].kind.isDoor {
                NumField(title: "Высота подоконника", value: $p.openings[idx].sill, range: 0...1.8, step: 0.05)
            }
            NumField(title: "Центр от начала стены", value: $p.openings[idx].pos, range: 0.2...40, step: 0.05)
            Text("Проёмы уменьшают вес стен в сборе нагрузок. Окна повторяются на всех этажах, наружные двери — только на 1-м.")
                .font(.caption).foregroundStyle(.secondary)
            Button(role: .destructive) {
                let id = p.openings[idx].id
                ed.selectedOpening = nil
                p.openings.removeAll { $0.id == id }
            } label: { Label("Удалить", systemImage: "trash") }
        }
    }
}

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
}
