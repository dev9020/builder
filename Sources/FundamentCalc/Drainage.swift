import Foundation

/// Отмостка и дренаж — защита основания от замачивания и морозного пучения
struct DrainagePlan {
    var width = 1.0                 // ширина отмостки, м
    var slope = 2.0                 // уклон отмостки, %
    var insulated = false           // утеплённая отмостка
    var eps = 0.0                   // толщина ЭППС, мм
    var faceOffset = 0.2            // от оси стены до наружной грани цоколя/плиты, м
    var drainRequired = false
    var drainReason = ""
    var drainDepth = 1.0            // глубина низа трубы в верхней точке, м
    var drainDepthEnd = 1.2         // в нижней точке (у накопительного колодца), м
    var drainLength = 0.0
    var drainRing: [V2] = []        // трасса дренажа
    var wells: [V2] = []            // смотровые колодцы
    var collector = V2(0, 0)        // накопительный колодец
    var blindRings: [[V2]] = []     // контуры полосы отмостки (для 3D, even-odd)
    var blindArea = 0.0
    var downpipes: [V2] = []        // водосточные трубы
    var requirements: [Check] = []
    var steps: [String] = []
    var items: [WorkItem] = []
}

enum Drainage {
    static func make(_ p: Project, _ r: CalcResults, kind: FoundationKind? = nil) -> DrainagePlan {
        var d = DrainagePlan()
        let kind = kind ?? p.selectedFoundation
        let soil = p.soil
        let heaving = soil.heave != .none
        let rings = p.rings
        guard !rings.isEmpty else { return d }
        let maxT = p.segments.map { p.thickness($0.material) }.max() ?? 0.2

        // --- Отмостка ---
        let o = p.roofType == .flat ? 0 : p.overhang
        d.insulated = heaving || (kind == .strip && p.stripKind == .shallow) || kind == .slab
        d.width = roundUp(max(d.insulated ? 1.2 : 0.8, o + 0.3), 0.1)
        d.eps = !d.insulated ? 0 : soil.heave == .strong ? 100 : 50
        if kind == .slab && heaving { d.eps = 100 }
        d.slope = 2.5
        switch kind {
        case .strip: d.faceOffset = max(maxT / 2, (r.strip.ext?.stemW ?? 0.4) / 2) + 0.02
        case .slab: d.faceOffset = maxT / 2 + 0.12
        case .piles: d.faceOffset = max(maxT / 2, r.piles.bg / 2) + 0.02
        }
        var bands: [[V2]] = []
        let outer = rings[0]
        bands.append(Geo.offset(outer, by: d.faceOffset + d.width))
        bands.append(Geo.offset(outer, by: d.faceOffset))
        for hole in rings.dropFirst() {
            let (lo, hi) = Geo.bbox([hole])
            let maxW = max(0.3, min(hi.x - lo.x, hi.y - lo.y) / 2 - d.faceOffset - 0.5)
            bands.append(Geo.offset(hole, by: -d.faceOffset))
            bands.append(Geo.offset(hole, by: -(d.faceOffset + min(d.width, maxW))))
        }
        d.blindRings = bands
        d.blindArea = abs(Geo.signedArea(bands[0])) - abs(Geo.signedArea(bands[1]))
        if bands.count >= 4 { d.blindArea += abs(Geo.signedArea(bands[2])) - abs(Geo.signedArea(bands[3])) }

        // --- Дренаж ---
        let baseDepth: Double
        switch kind {
        case .strip: baseDepth = r.strip.depth + r.strip.cushion
        case .slab: baseDepth = max(0.3, r.slab.t - 0.15 + p.slabCushion)
        case .piles: baseDepth = 0.8
        }
        let clayey = soil.d0 < 0.25 || soil.name.lowercased().contains("супесь")
        var reasons: [String] = []
        if p.gwl < baseDepth + 1.5 { reasons.append("УГВ \(fmt(p.gwl, 1)) м — ближе 1.5 м к подошве") }
        if clayey { reasons.append("глинистый грунт: верховодка застаивается у фундамента") }
        if soil.heave == .medium || soil.heave == .strong { reasons.append("пучинистый грунт: замачивание усиливает пучение") }
        d.drainRequired = !reasons.isEmpty
        d.drainReason = reasons.isEmpty ? "Песчаный непучинистый грунт и низкий УГВ: достаточно отмостки и ливнёвки, дренаж — по желанию." : reasons.joined(separator: "; ")
        d.drainDepth = roundUp(baseDepth + 0.2, 0.05)
        d.drainRing = Geo.offset(outer, by: d.faceOffset + 0.4)
        d.drainLength = Geo.perimeter(d.drainRing)
        d.drainDepthEnd = d.drainDepth + 0.005 * d.drainLength / 2
        // колодцы: в углах через один, накопительный — за углом с наименьшими координатами
        let ring = d.drainRing
        for (i, v) in ring.enumerated() where i % 2 == 0 { d.wells.append(v) }
        let c0 = ring.min { $0.x + $0.y < $1.x + $1.y } ?? ring[0]
        let (blo, bhi) = Geo.bbox([outer])
        let ctr = (blo + bhi) / 2
        d.collector = c0 + (c0 - ctr).unit * 3.0
        d.drainLength += (d.collector - c0).len
        // водостоки — по выпуклым углам у карнизов
        if p.roofType != .flat {
            let model = RoofModel.of(p)
            for (i, v) in outer.enumerated() {
                let a = outer[(i - 1 + outer.count) % outer.count], b = outer[(i + 1) % outer.count]
                guard cross2(v - a, b - v) > 0 else { continue }   // выпуклый угол
                if model.onEave(a, v) || model.onEave(v, b) {
                    let d1 = (v - a).unit, d2 = (b - v).unit
                    let out = (V2(d1.y, -d1.x) + V2(d2.y, -d2.x)).unit   // наружная биссектриса (контур CCW)
                    d.downpipes.append(v + out * (maxT / 2 + 0.12))
                }
            }
        } else {
            d.downpipes = []
        }

        // --- Требования ---
        d.requirements = [
            Check(title: "Отмостка по всему периметру", value: "ширина \(Int(d.width * 100)) см (не менее свеса кровли + 20–30 см), уклон \(fmt(d.slope, 1)) % от дома, без разрывов на углах",
                  ok: true, ref: "СП 82.13330.2016; СП 22.13330.2016 разд. 6.8 (пучинистые грунты)"),
            Check(title: d.insulated ? "Утеплённая отмостка" : "Отмостка без утепления",
                  value: d.insulated ? "ЭППС \(Int(d.eps)) мм (≥ 30 кг/м³) под отмосткой и по цоколю — грунт под фундаментом не промерзает" : "грунт непучинистый — утепление не обязательно",
                  ok: true, ref: "СП 22.13330.2016 разд. 6.8; Пособие по проектированию МЗЛФ"),
            Check(title: "Примыкание к цоколю", value: "через демпферную ленту / деформационный шов 10–20 мм, отмостку не связывать с фундаментом арматурой",
                  ok: true, ref: "СП 82.13330.2016"),
            Check(title: d.drainRequired ? "Пристенный дренаж — обязателен" : "Пристенный дренаж — рекомендуется",
                  value: d.drainReason, ok: true, ref: "СП 22.13330.2016; СП 250.1325800.2016"),
            Check(title: "Трасса дренажа", value: "труба Ø110 в геофильтре на \(Int(0.4 * 100)) см от грани фундамента, низ трубы \(fmt(d.drainDepth)) м → \(fmt(d.drainDepthEnd)) м (на 0.2 м ниже подошвы/подушки), уклон ≥ 0.5 % к колодцу, щебень 20–40 в геотекстиле",
                  ok: true, ref: "СП 250.1325800.2016"),
            Check(title: "Колодцы", value: "\(d.wells.count) смотровых на поворотах + накопительный/поглощающий в \(fmt((d.collector - c0).len, 0)) м от угла дома",
                  ok: true, ref: "СП 250.1325800.2016"),
            Check(title: "Ливнёвка отдельно от дренажа", value: "водостоки (\(d.downpipes.count) шт.) → точечные дождеприёмники → отдельная труба Ø110 в колодец; в дренажную трубу дождевую воду не сбрасывать",
                  ok: true, ref: "СП 32.13330.2018"),
        ]

        // --- Работы ---
        d.steps = [
            "Дренаж прокладывают до обратной засыпки пазух: траншея шириной 0.4 м вдоль фундамента на глубину \(fmt(d.drainDepth))…\(fmt(d.drainDepthEnd)) м с уклоном 5 мм на 1 м к накопительному колодцу (проверять нивелиром).",
            "Траншею застелить геотекстилем с запасом на обёртку, отсыпать щебень 20–40 слоем 10 см, уложить трубу, обсыпать щебнем на 20 см и завернуть геотекстиль внахлёст.",
            "Колодцы установить на поворотах трассы (\(d.wells.count) шт.) и накопительный за пределами отмостки — для промывки и сброса воды в ливнёвку/поглощающий колодец/канаву.",
            "Ливнёвку от водостоков прокладывать отдельной трубой Ø110 с уклоном 1–2 %, в ту же траншею выше дренажа или параллельно.",
            "Пазухи засыпать песком послойно с трамбовкой. Под отмосткой: уплотнённый грунт → геотекстиль → щебень 100 мм → \(d.insulated ? "ЭППС \(Int(d.eps)) мм → " : "")песок/ЦПС 50 мм → плитка 60 мм (или бетон 80–100 мм по сетке с деформационными швами через 2 м).",
            "Уклон отмостки \(fmt(d.slope, 1)) % от дома, у цоколя — демпферная лента; по краю — бордюр.",
        ]
        let per = Geo.perimeter(bands[0])
        let wallPer = Geo.perimeter(bands[1]) + (bands.count >= 4 ? Geo.perimeter(bands[2]) : 0)
        let trench = d.drainLength * 0.4 * (d.drainDepth + d.drainDepthEnd) / 2
        d.items = [
            WorkItem(name: "Тротуарная плитка 60 мм (отмостка)", qty: d.blindArea * 1.05, unit: "м²", digits: 1, price: Price.pavingM2),
            WorkItem(name: "Бордюр садовый", qty: per * 1.03, unit: "м.п.", digits: 0, price: Price.curbM),
            WorkItem(name: "ЦПС для укладки плитки", qty: (d.blindArea * 1.4).rounded(.up), unit: "мешок 40 кг", digits: 0, price: Price.dryMixBag),
            WorkItem(name: "Щебень 20–40 (основание отмостки + дренаж)", qty: d.blindArea * 0.1 + d.drainLength * 0.4 * 0.35, unit: "м³", digits: 1, price: Price.gravelM3),
            WorkItem(name: "Песок (подложка отмостки)", qty: d.blindArea * 0.15 * 1.2, unit: "м³", digits: 1, price: Price.sandM3),
            WorkItem(name: "Геотекстиль (отмостка + обёртка дренажа)", qty: d.blindArea * 1.1 + d.drainLength * 1.6, unit: "м²", digits: 0, price: Price.geotextileM2),
            WorkItem(name: "Демпферная лента у цоколя", qty: wallPer, unit: "м.п.", digits: 0, price: Price.damperTapeM),
            WorkItem(name: "Дренажная труба Ø110 в геофильтре", qty: d.drainLength * 1.05, unit: "м", digits: 0, price: Price.drainPipeM),
            WorkItem(name: "Смотровые колодцы Ø315", qty: Double(d.wells.count), unit: "шт", digits: 0, price: Price.drainWell),
            WorkItem(name: "Накопительный колодец", qty: 1, unit: "шт", digits: 0, price: Price.collectorWell),
            WorkItem(name: "Ливнёвка: труба Ø110", qty: per * 0.6 + 10, unit: "м", digits: 0, price: Price.stormPipeM),
            WorkItem(name: "Точечные дождеприёмники", qty: Double(max(d.downpipes.count, 2)), unit: "шт", digits: 0, price: Price.rainInlet),
            WorkItem(name: "Земляные работы под дренаж (объём)", qty: trench, unit: "м³", digits: 1),
        ]
        if d.insulated {
            d.items.insert(WorkItem(name: "ЭППС \(Int(d.eps)) мм под отмостку", qty: d.blindArea * 1.05, unit: "м²", digits: 1,
                                    price: d.eps >= 100 ? Price.eps100M2 : Price.eps50M2), at: 3)
        }
        return d
    }
}
