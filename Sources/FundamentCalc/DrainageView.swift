import SwiftUI

/// Блок требований к отмостке и дренажу с разрезом узла
struct DrainageBlock: View {
    let d: DrainagePlan
    let kind: FoundationKind
    let depth: Double      // глубина подошвы фундамента, м
    let plinth: Double     // высота цоколя, м

    var body: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 18) {
                DrainSectionView(d: d, kind: kind, depth: depth, plinth: plinth)
                    .frame(width: 380, height: 260)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(d.requirements) { ch in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.shield.fill").foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(ch.title).bold()
                                Text(ch.value).fixedSize(horizontal: false, vertical: true)
                                Text(ch.ref).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(6)
        } label: {
            Label("Отмостка и дренаж — обязательные требования (защита от пучения)", systemImage: "drop.triangle").font(.headline)
        }
    }
}

/// Разрез: фундамент, отмостка с уклоном и утеплением, дренаж ниже подошвы
struct DrainSectionView: View {
    let d: DrainagePlan
    let kind: FoundationKind
    let depth: Double
    let plinth: Double

    var body: some View {
        Canvas { ctx, size in
            let top = plinth + 0.6
            let W = d.width + 1.6, Htot = top + d.drainDepthEnd + 0.4
            let sc = min((size.width - 40) / W, (size.height - 30) / Htot)
            let x0 = 20.0, y0 = 15 + top * sc
            func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x0 + x * sc, y: y0 - y * sc) }   // y вверх, 0 — земля
            // грунт
            var soil = Path(); soil.addRect(CGRect(origin: P(0, 0), size: CGSize(width: W * sc, height: (d.drainDepthEnd + 0.5) * sc)))
            ctx.fill(soil, with: .color(.brown.opacity(0.15)))
            // фундамент
            let fw = 0.4
            var f = Path()
            switch kind {
            case .strip: f.addRect(CGRect(origin: P(0, plinth), size: CGSize(width: fw * sc, height: (plinth + depth) * sc)))
            case .slab: f.addRect(CGRect(origin: P(0, 0.15), size: CGSize(width: 0.6 * sc, height: 0.3 * sc)))
            case .piles: f.addRect(CGRect(origin: P(0, plinth), size: CGSize(width: fw * sc, height: plinth * sc)))
            }
            ctx.fill(f, with: .color(.gray.opacity(0.5))); ctx.stroke(f, with: .color(.primary), lineWidth: 1)
            let fx = kind == .slab ? 0.6 : fw
            // стена
            var wall = Path(); wall.addRect(CGRect(origin: P(0.05, top), size: CGSize(width: (fx - 0.1) * sc, height: 0.6 * sc)))
            ctx.fill(wall, with: .color(.orange.opacity(0.3)))
            // отмостка: щебень, ЭППС, плитка с уклоном
            let x1 = fx + d.width, drop = d.width * d.slope / 100
            var gravel = Path(); gravel.addLines([P(fx, -0.05), P(x1, -0.05 - drop), P(x1, -0.2 - drop), P(fx, -0.2)]); gravel.closeSubpath()
            ctx.fill(gravel, with: .color(.gray.opacity(0.4)))
            if d.insulated {
                let e = d.eps / 1000
                var eps = Path(); eps.addLines([P(fx, -0.05 + e), P(x1, -0.05 - drop + e), P(x1, -0.05 - drop), P(fx, -0.05)]); eps.closeSubpath()
                ctx.fill(eps, with: .color(.pink.opacity(0.6)))
                ctx.draw(Text("ЭППС \(Int(d.eps))").font(.system(size: 9)), at: P(fx + d.width / 2, -0.05 + e / 2 - drop / 2))
            }
            var tile = Path(); tile.addLines([P(fx, 0.08), P(x1, 0.08 - drop), P(x1, 0.02 - drop), P(fx, 0.02)]); tile.closeSubpath()
            ctx.fill(tile, with: .color(.gray)); ctx.stroke(tile, with: .color(.primary), lineWidth: 0.8)
            ctx.draw(Text("отмостка \(Int(d.width * 100)) см, \(fmt(d.slope, 1)) %").font(.system(size: 10, weight: .semibold)), at: P(fx + d.width / 2 + 0.1, 0.4), anchor: .bottomLeading)
            // дренаж
            let dx = fx + 0.4, dy = -d.drainDepth
            var tr = Path(); tr.addRect(CGRect(origin: P(dx - 0.2, dy + 0.35), size: CGSize(width: 0.4 * sc, height: 0.4 * sc)))
            ctx.fill(tr, with: .color(.gray.opacity(0.55))); ctx.stroke(tr, with: .color(.green.opacity(0.7)), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
            let pc = P(dx, dy + 0.1), r = 0.055 * sc
            ctx.fill(Path(ellipseIn: CGRect(x: pc.x - r, y: pc.y - r, width: 2 * r, height: 2 * r)), with: .color(.black))
            ctx.draw(Text("дренаж Ø110, низ −\(fmt(d.drainDepth)) м").font(.system(size: 10)), at: P(dx + 0.3, dy + 0.1), anchor: .leading)
            ctx.draw(Text("щебень в геотекстиле").font(.system(size: 9)).foregroundColor(.secondary), at: P(dx + 0.3, dy - 0.05), anchor: .leading)
            // подошва
            if kind != .piles {
                var base = Path(); base.move(to: P(0, -depth)); base.addLine(to: P(W, -depth))
                ctx.stroke(base, with: .color(.blue.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                ctx.draw(Text("подошва −\(fmt(depth)) м").font(.system(size: 9)).foregroundColor(.blue), at: P(W - 0.05, -depth + 0.03), anchor: .bottomTrailing)
            }
            var g = Path(); g.move(to: P(0, 0)); g.addLine(to: P(W, 0))
            ctx.stroke(g, with: .color(.green), lineWidth: 1.5)
        }
    }
}
