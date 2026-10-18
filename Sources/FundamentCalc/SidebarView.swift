import SwiftUI

struct NumField: View {
    let title: String
    @Binding var value: Double
    var unit = "м"
    var range: ClosedRange<Double> = 0...100
    var step = 0.1
    var digits = 2

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Spacer()
            TextField("", value: $value, format: .number.precision(.fractionLength(0...digits)))
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
            Text(unit).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
            Stepper("", value: $value, in: range, step: step).labelsHidden()
        }
        .onChange(of: value) { _, v in
            if v < range.lowerBound { value = range.lowerBound } else if v > range.upperBound { value = range.upperBound }
        }
    }
}

struct ShapeIcon: View {
    let shape: HouseShape
    var body: some View {
        Canvas { ctx, size in
            let rings = Project.ringsFor(shape, L: 10, W: shape == .square ? 10 : 7, a: 3, b: 3.5, il: 4, iw: 2.4)
            let (lo, hi) = Geo.bbox(rings)
            let s = min((size.width - 6) / (hi.x - lo.x), (size.height - 6) / (hi.y - lo.y))
            let ox = (size.width - (hi.x - lo.x) * s) / 2, oy = (size.height + (hi.y - lo.y) * s) / 2
            var path = Path()
            for r in rings {
                path.addLines(r.map { CGPoint(x: ox + ($0.x - lo.x) * s, y: oy - ($0.y - lo.y) * s) })
                path.closeSubpath()
            }
            ctx.fill(path, with: .color(.accentColor.opacity(0.3)), style: FillStyle(eoFill: true))
            ctx.stroke(path, with: .color(.primary), lineWidth: 1.5)
        }
        .frame(width: 46, height: 36)
    }
}

struct SidebarView: View {
    @EnvironmentObject var p: Project
    @EnvironmentObject var model: AppModel

    var roofNote: String {
        let a = p.roofAngleEff, c = p.covering
        var t = "Мин. уклон для «\(c.title.lowercased())» — \(Int(c.minSlope))°. "
        if a < c.minSlope { return t + "Уклон меньше допустимого — протечки!" }
        t += a >= c.snowSlideSlope
            ? "Снег сходит самостоятельно (≥ \(Int(c.snowSlideSlope))°) — нужны снегозадержатели над входом."
            : "Снег будет задерживаться (сход от ~\(Int(c.snowSlideSlope))°): нагрузка учтена полностью, μ = \(fmt(model.results.loads.snowMu))."
        return t
    }

    var body: some View {
        Form {
            shapeSection
            frameSection
            floorsSection
            roofSection
            climateSection
            soilSection
            foundationSection
            miscSection
        }
        .formStyle(.grouped)
    }

    func shapeButton(_ s: HouseShape) -> some View {
        let on = p.shape == s
        let fillC: Color = on ? Color.accentColor.opacity(0.2) : Color.clear
        let strokeC: Color = on ? Color.accentColor : Color.gray.opacity(0.3)
        return Button { p.applyShapeDefault(s) } label: {
            VStack(spacing: 2) {
                ShapeIcon(shape: s)
                Text(s.title).font(.caption2)
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 6).fill(fillC))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(strokeC))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder var shapeSection: some View {
        Section("Форма дома (размеры по осям стен)") {
            HStack(spacing: 4) {
                ForEach(HouseShape.allCases) { s in shapeButton(s) }
            }
            NumField(title: p.shape == .square ? "Сторона" : "Длина (X)", value: $p.length, range: 3...40, step: 0.5)
            if p.shape != .square {
                NumField(title: "Ширина (Y)", value: $p.width, range: 3...40, step: 0.5)
            }
            switch p.shape {
            case .lShape:
                NumField(title: "Ширина нижнего крыла", value: $p.wingA, range: 1.5...30, step: 0.5)
                NumField(title: "Ширина левого крыла", value: $p.wingB, range: 1.5...30, step: 0.5)
            case .uShape:
                NumField(title: "Глубина основания", value: $p.wingA, range: 1.5...30, step: 0.5)
                NumField(title: "Ширина боковых крыльев", value: $p.wingB, range: 1.5...20, step: 0.5)
            case .ring:
                NumField(title: "Двор: длина", value: $p.innerL, range: 1...30, step: 0.5)
                NumField(title: "Двор: ширина", value: $p.innerW, range: 1...30, step: 0.5)
            default: EmptyView()
            }
            Text("Площадь застройки по осям: \(fmt(model.results.loads.floorArea, 1)) м². При выборе формы загружается типовой проект с полной планировкой — остальные варианты в «Готовых проектах».")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder var frameSection: some View {
        Section("Этажность и каркас") {
            Stepper("Этажей: \(p.floors)", value: $p.floors, in: 1...3)
            NumField(title: "Высота этажа", value: $p.floorHeight, range: 2.2...4.5, step: 0.1)
            Picker("Каркас наружных стен", selection: $p.defaultMaterial) {
                ForEach(WallMaterial.allCases) { Text($0.title).tag($0) }
            }
            ForEach(p.usedMaterials) { m in
                NumField(title: "Толщина: \(m.short)", value: Binding(get: { p.thickness(m) }, set: { p.thicknesses[m] = $0 }),
                         range: 0.08...0.8, step: 0.025, digits: 3)
            }
            Toggle("Рамы окон и дверей — антрацит", isOn: $p.darkFrames)
            Picker("Облицовка фасада", selection: $p.facade) {
                ForEach(FacadeFinish.allCases) { Text($0.title).tag($0) }
            }
            Text("Материал отдельных участков и перегородки задаются на вкладке «План».")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder var floorsSection: some View {
        Section("Перекрытия") {
            Picker("Межэтажное / чердачное", selection: $p.floorType) {
                ForEach(FloorType.allCases) { Text($0.title).tag($0) }
            }
            Picker("Пол 1-го этажа", selection: $p.groundFloor) {
                ForEach(GroundFloorType.allCases) { Text($0.title).tag($0) }
            }
        }
    }

    @ViewBuilder var roofSection: some View {
        Section("Кровля") {
            Picker("Тип", selection: $p.roofType) {
                ForEach(RoofType.allCases) { Text($0.title).tag($0) }
            }
            if p.roofType == .flat {
                Picker("Конструкция", selection: $p.flatSlab) {
                    ForEach(FlatRoofSlab.allCases) { Text($0.title).tag($0) }
                }
            } else {
                Picker("Покрытие", selection: $p.covering) {
                    ForEach(RoofCovering.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Уклон автоматически", isOn: $p.roofAngleAuto)
                if p.roofAngleAuto {
                    LabeledContent("Уклон", value: "\(Int(p.roofAngleEff))°")
                } else {
                    NumField(title: "Уклон", value: $p.roofAngle, unit: "°", range: 5...60, step: 1, digits: 0)
                }
                if p.roofType == .shed {
                    LabeledContent("Перепад высот стен", value: "\(fmt(p.shedDrop)) м")
                }
                Text(roofNote).font(.caption).foregroundStyle(p.roofAngleEff < p.covering.minSlope ? .red : .secondary)
                NumField(title: "Свес", value: $p.overhang, range: 0...1.2, step: 0.1)
                Toggle("Утеплённая (мансардная) кровля", isOn: $p.roofInsulated)
                if p.shape == .square || p.shape == .rectangle {
                    Toggle("Конёк вдоль длинной стороны", isOn: $p.ridgeAlongLong)
                }
            }
        }
    }

    @ViewBuilder var climateSection: some View {
        Section("Климат") {
            Picker("Город", selection: $p.cityIndex) {
                ForEach(cities.indices, id: \.self) { Text(cities[$0].name).tag($0) }
                Text("Свои значения").tag(-1)
            }
            NumField(title: "Mt (сумма отриц. t°)", value: $p.mt, unit: "°C", range: 0...120, step: 1, digits: 1)
            Picker("Снеговой район", selection: $p.snowRegion) {
                ForEach(SnowRegion.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Дом отапливаемый", isOn: $p.heated)
            Text("Нормативная глубина промерзания dfn = \(fmt(model.results.strip.dfn)) м, расчётная df = \(fmt(model.results.strip.df)) м. Снег на кровле S = \(fmt(model.results.loads.snowS)) кПа (μ = \(fmt(model.results.loads.snowMu))). Данные по городам ориентировочные — сверьте с СП 131 и картой СП 20.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder var soilSection: some View {
        Section("Грунт основания") {
            Picker("Тип грунта", selection: $p.soilPreset) {
                ForEach(Soil.presets.indices, id: \.self) { Text(Soil.presets[$0].name).tag($0) }
            }
            NumField(title: "Уровень грунтовых вод", value: $p.gwl, range: 0...20, step: 0.5)
            DisclosureGroup("Характеристики (из изысканий)") {
                NumField(title: "γ, удельный вес", value: $p.soil.gamma, unit: "кН/м³", range: 14...23, step: 0.5, digits: 1)
                NumField(title: "φ, угол трения", value: $p.soil.phi, unit: "°", range: 5...45, step: 1, digits: 0)
                NumField(title: "c, сцепление", value: $p.soil.c, unit: "кПа", range: 0...150, step: 1, digits: 0)
                NumField(title: "E, модуль деформации", value: $p.soil.E, unit: "МПа", range: 2...80, step: 1, digits: 0)
                NumField(title: "γc1", value: $p.soil.gammaC1, unit: "", range: 1...1.4, step: 0.05)
                NumField(title: "k, коэф. постели", value: $p.soil.kSub, unit: "кН/м³", range: 2000...80000, step: 1000, digits: 0)
                NumField(title: "f, трение по боковой", value: $p.soil.fSide, unit: "кПа", range: 5...80, step: 1, digits: 0)
                NumField(title: "R под острием сваи", value: $p.soil.rTip, unit: "кПа", range: 100...5000, step: 50, digits: 0)
                Picker("Пучинистость", selection: $p.soil.heave) {
                    ForEach(HeaveClass.allCases) { Text($0.title).tag($0) }
                }
            }
        }
    }

    @ViewBuilder var foundationSection: some View {
        Section("Фундамент") {
            Picker("Бетон", selection: $p.concrete) {
                ForEach(ConcreteClass.allCases) { Text($0.title).tag($0) }
            }
            Picker("Арматура", selection: $p.rebar) {
                ForEach(RebarClass.allCases) { Text($0.rawValue).tag($0) }
            }
            switch p.selectedFoundation {
            case .strip:
                Picker("Лента", selection: $p.stripKind) {
                    ForEach(StripKind.allCases) { Text($0.title).tag($0) }
                }
                if p.stripKind == .shallow {
                    NumField(title: "Глубина заложения", value: $p.shallowDepth, range: 0.3...1.0, step: 0.05)
                }
                NumField(title: "Высота цоколя над землёй", value: $p.plinth, range: 0.1...1.0, step: 0.05)
                Toggle("Бетонная подготовка 50 мм", isOn: $p.concretePrep)
                NumField(title: "Снятие растит. слоя", value: $p.topsoil, range: 0...0.6, step: 0.05)
            case .slab:
                NumField(title: "Мин. толщина плиты", value: $p.slabMinThickness, range: 0.15...0.5, step: 0.05)
                NumField(title: "Песчаная подушка", value: $p.slabCushion, range: 0.1...1.0, step: 0.05)
                NumField(title: "Снятие растит. слоя", value: $p.topsoil, range: 0...0.6, step: 0.05)
            case .piles:
                Picker("Тип свай", selection: $p.pileType) {
                    ForEach(PileType.allCases) { Text($0.title).tag($0) }
                }
                Picker("Диаметр ствола", selection: $p.pileDiameter) {
                    ForEach(p.pileType == .screw ? [0.089, 0.108, 0.133] : [0.2, 0.25, 0.3, 0.4], id: \.self) {
                        Text("\(Int(($0 * 1000).rounded())) мм").tag($0)
                    }
                }
                if p.pileType != .bored {
                    Picker(p.pileType == .screw ? "Диаметр лопасти" : "Диаметр уширения", selection: $p.pileEnlarge) {
                        ForEach(p.pileType == .screw ? [0.2, 0.25, 0.3, 0.35] : [0.4, 0.5, 0.6, 0.8], id: \.self) {
                            Text("\(Int(($0 * 1000).rounded())) мм").tag($0)
                        }
                    }
                }
                Toggle("Длина сваи — авто (ниже промерзания)", isOn: $p.pileLengthAuto)
                if !p.pileLengthAuto {
                    NumField(title: "Длина сваи", value: $p.pileLength, range: 1.5...8, step: 0.25)
                }
                NumField(title: "Мин. высота ростверка", value: $p.grillageH, range: 0.3...0.8, step: 0.05)
                NumField(title: "Снятие растит. слоя", value: $p.topsoil, range: 0...0.6, step: 0.05)
            }
        }
    }

    @ViewBuilder var miscSection: some View {
        Section {
            Button("Дом по умолчанию (каркас 10×8)") { p.loadDefault() }
            Text("Готовые каркасные проекты 80–150 м² — ссылка «Готовые проекты» на панели окна.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
