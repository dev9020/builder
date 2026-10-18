import SwiftUI

/// Блок «Вес дома и фундамент»
struct WeightsView: View {
    let w: WeightReport
    let kind: FoundationKind

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 18) {
                    tile("Дом (конструкции)", w.dead, .primary)
                    tile("Снег зимой", w.snow, .blue)
                    tile("Мебель, техника, люди", w.contentsSum, .orange, note: "оценка")
                    tile("Итого дом зимой", w.winter, .primary, bold: true)
                    Divider().frame(height: 50)
                    tile("Сам фундамент", w.foundationSelf, .gray)
                    tile("Фундамент выдержит", w.capacity, .green, bold: true)
                }
                bar
                HStack(spacing: 6) {
                    Image(systemName: w.reserve >= 1 ? "checkmark.seal.fill" : "xmark.octagon.fill")
                        .foregroundStyle(w.reserve >= 1 ? .green : .red)
                    Text(w.reserve >= 1
                         ? "Запас по несущей способности — в \(fmt(w.reserve, 1)) раза (нагрузка \(fmt(w.load / 9.81, 1)) т из \(fmt(w.capacity / 9.81, 1)) т)."
                         : "Фундамент перегружен: нагрузка \(fmt(w.load / 9.81, 1)) т больше допустимых \(fmt(w.capacity / 9.81, 1)) т.")
                        .bold()
                }
                Text("Самое нагруженное место — \(w.local) (\(Int((w.localRatio * 100).rounded())) % от допустимого). \(w.basis)")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Из чего складывается вес") {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                        ForEach(w.structure) { row($0) }
                        row(WeightItem(name: "Снег на кровле (зимой)", kN: w.snow, note: "по снеговому району и уклону"))
                        ForEach(w.contents) { row($0) }
                        Divider()
                        GridRow {
                            Text("Полезная нагрузка по нормам (СП 20)").foregroundStyle(.secondary)
                            Text("\(fmt(w.liveNorm / 9.81, 1)) т").monospacedDigit().gridColumnAlignment(.trailing)
                            Text("в расчёте фундамента закладывается 150 кг/м² на этаж — с запасом к реальной мебели и людям")
                                .foregroundStyle(.secondary)
                        }
                        GridRow {
                            Text("На грунт с фундаментом (зимой)").bold()
                            Text("\(fmt(w.onSoil / 9.81, 1)) т").bold().monospacedDigit()
                            Text("")
                        }
                    }
                    .padding(.top, 6)
                }
            }
            .padding(6)
        } label: {
            Label("Вес дома и несущая способность фундамента", systemImage: "scalemass").font(.headline)
        }
    }

    func tile(_ title: String, _ kN: Double, _ c: Color, note: String? = nil, bold: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(fmt(kN / 9.81, 1)) т").font(bold ? .title2.bold() : .title3.weight(.semibold)).foregroundStyle(c)
            Text(note ?? "\(fmt(kN, 0)) кН").font(.caption2).foregroundStyle(.secondary)
        }
    }

    func row(_ i: WeightItem) -> some View {
        GridRow {
            Text(i.name)
            Text("\(fmt(i.t, 2)) т").monospacedDigit().gridColumnAlignment(.trailing)
            Text(i.note).foregroundStyle(.secondary)
        }
    }

    /// Полоса: вес дома (конструкции, снег, содержимое) относительно того, что выдерживает фундамент
    var bar: some View {
        GeometryReader { geo in
            let maxV = max(w.capacity, w.winter, 1)
            let sc = geo.size.width / maxV
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5).fill(Color.green.opacity(0.15))
                    .frame(width: w.capacity * sc)
                HStack(spacing: 0) {
                    Rectangle().fill(Color.gray.opacity(0.75)).frame(width: w.dead * sc)
                    Rectangle().fill(Color.blue.opacity(0.7)).frame(width: w.snow * sc)
                    Rectangle().fill(Color.orange.opacity(0.75)).frame(width: w.contentsSum * sc)
                }
                .frame(height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                Rectangle().fill(Color.green).frame(width: 2, height: 26).offset(x: w.capacity * sc - 1)
            }
        }
        .frame(height: 26)
        .overlay(alignment: .bottomTrailing) {
            Text("зелёная зона — сколько выдерживает фундамент").font(.caption2).foregroundStyle(.secondary).offset(y: 14)
        }
        .padding(.bottom, 10)
    }
}
