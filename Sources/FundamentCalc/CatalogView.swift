import SwiftUI

struct CatalogView: View {
    @EnvironmentObject var p: Project
    @Environment(\.dismiss) private var dismiss
    @State private var shape: HouseShape?
    @State private var foundation: FoundationKind?

    var filtered: [HousePreset] {
        HousePreset.all.filter { (shape == nil || $0.shape == shape) && (foundation == nil || $0.foundation == foundation) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Готовые проекты").font(.title2.bold())
                    Text("Все проекты — из стандартных материалов: шаг 625, стойка 3000, размеры кратны листу 1250, типовые окна и двери").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Форма", selection: $shape) {
                    Text("Все формы").tag(HouseShape?.none)
                    ForEach(HouseShape.allCases) { Text($0.title).tag(HouseShape?.some($0)) }
                }
                .fixedSize()
                Picker("Фундамент", selection: $foundation) {
                    Text("Любой").tag(FoundationKind?.none)
                    Text("Ленточный").tag(FoundationKind?.some(.strip))
                    Text("Плита").tag(FoundationKind?.some(.slab))
                }
                .fixedSize()
                Button("Закрыть") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(14)
            Divider()
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                    ForEach(filtered) { preset in
                        PresetCard(preset: preset) {
                            preset.apply(p)
                            dismiss()
                        }
                    }
                }
                .padding(14)
            }
        }
        .frame(minWidth: 980, minHeight: 680)
    }
}

struct PresetCard: View {
    let preset: HousePreset
    let choose: () -> Void

    var body: some View {
        let demo: Project = { let d = Project(); preset.apply(d); return d }()
        let area = Geo.area(demo.rings)
        VStack(alignment: .leading, spacing: 8) {
            PlanThumb(project: demo)
                .frame(height: 190)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            HStack(alignment: .firstTextBaseline) {
                Text(preset.name).font(.headline)
                Spacer()
                Text(demo.floors > 1 ? "\(Int(area * Double(demo.floors))) м²" : "\(Int(area)) м²")
                    .font(.headline).foregroundStyle(Color.accentColor)
            }
            HStack(spacing: 6) {
                chip(demo.shape.title)
                chip("\(fmt(demo.length, 0))×\(fmt(demo.effW, 0)) м")
                chip(demo.floors > 1 ? "\(demo.floors) этажа" : "1 этаж")
                chip(preset.foundation == .slab ? "Плита" : "Лента")
            }
            HStack(spacing: 6) {
                chip(demo.defaultMaterial.short)
                chip(demo.roofType.title)
                if demo.roofType != .flat { chip(demo.covering.title) }
            }
            Text(preset.summary).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack {
                let ops = demo.validOpenings
                Text("Окон: \(ops.filter { !$0.kind.isDoor }.count) (в пол: \(ops.filter { $0.kind == .panoramic }.count)) · дверей: \(ops.filter { $0.kind.isDoor }.count)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Выбрать", action: choose).buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.25)))
    }

    func chip(_ s: String) -> some View {
        Text(s).font(.caption)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Color.gray.opacity(0.15)))
    }
}

/// Миниатюра плана: стены, перегородки, окна и двери
struct PlanThumb: View {
    let project: Project

    var body: some View {
        Canvas { ctx, size in
            let p = project
            let rings = p.rings
            let (lo, hi) = Geo.bbox(rings)
            let pad = 14.0
            let sc = min((size.width - 2 * pad) / (hi.x - lo.x), (size.height - 2 * pad) / (hi.y - lo.y))
            let ox = (size.width - (hi.x - lo.x) * sc) / 2, oy = (size.height + (hi.y - lo.y) * sc) / 2
            func P(_ v: V2) -> CGPoint { CGPoint(x: ox + (v.x - lo.x) * sc, y: oy - (v.y - lo.y) * sc) }
            var fill = Path()
            for r in rings { fill.addLines(r.map(P)); fill.closeSubpath() }
            ctx.fill(fill, with: .color(Color.accentColor.opacity(0.07)), style: FillStyle(eoFill: true))
            for s in p.segments {
                var l = Path(); l.move(to: P(s.a)); l.addLine(to: P(s.b))
                ctx.stroke(l, with: .color(s.material.planColor), style: StrokeStyle(lineWidth: max(p.thickness(s.material) * sc, 2.5), lineCap: .square))
            }
            for pt in p.partitions {
                var l = Path(); l.move(to: P(pt.a)); l.addLine(to: P(pt.b))
                ctx.stroke(l, with: .color(pt.material.planColor.opacity(0.9)), lineWidth: max(pt.thickness * sc, 1.5))
            }
            for o in p.validOpenings {
                guard let h = p.hostLine(o.host) else { continue }
                let d = (h.b - h.a).unit, c = h.a + d * o.pos
                var g = Path(); g.move(to: P(c - d * (o.width / 2))); g.addLine(to: P(c + d * (o.width / 2)))
                ctx.stroke(g, with: .color(Color(nsColor: .textBackgroundColor)), lineWidth: 0.42 * sc)
                ctx.stroke(g, with: .color(o.kind == .door ? .brown : .blue), lineWidth: o.kind == .panoramic || o.kind == .glassDoor ? 2 : 1)
            }
        }
    }
}
