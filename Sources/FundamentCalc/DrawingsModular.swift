import AppKit
import CoreGraphics

/// Схемы модульной системы: разрез и план стены с размерами слоёв, раскладка листов, узлы соединений
extension Drawings {
    static let osbFill = NSColor(srgbRed: 0.86, green: 0.70, blue: 0.45, alpha: 1)
    static let osbStrip = NSColor(srgbRed: 0.76, green: 0.58, blue: 0.34, alpha: 1)
    static let gklFill = NSColor(white: 0.93, alpha: 1)
    static let teal = NSColor(srgbRed: 0.1, green: 0.6, blue: 0.65, alpha: 1)
    static let okFill = NSColor(srgbRed: 0.80, green: 0.93, blue: 0.78, alpha: 1)
    static let warnFill = NSColor(srgbRed: 1.0, green: 0.82, blue: 0.62, alpha: 1)

    struct WallLayers {
        let facade: Double, gap: Double, osb: Double, stud: Double, batten: Double, gkl: Double
        var total: Double { facade + gap + osb + stud + batten + gkl }
    }

    static func layersOf(_ c: Ctx) -> WallLayers {
        let brick = c.p.facade == .facingBrick, plaster = c.p.facade == .plaster
        // штукатурный фасад (СФТК): минвата 100 + штукатурка 10, без вентзазора
        return WallLayers(facade: brick ? 0.12 : plaster ? 0.11 : 0.02, gap: brick ? 0.04 : plaster ? 0 : 0.025, osb: c.p.sheathing.hasOSB ? 0.009 : 0,
                          stud: c.b.frame.studExt.wm, batten: 0.025, gkl: c.p.interiorFinish.t)
    }

    // MARK: - Разрез стены по высоте

    static func wallSection(_ c: Ctx, _ cg: CGContext, _ rect: CGRect) {
        let F = c.b.frame
        let L = layersOf(c)
        let k = 3.0                                   // толщина стены показана ×3
        let H = F.wallHeights.first ?? Module.frameH
        let mod = c.p.modular
        // x (м, истинные) снаружи внутрь: 0 — наружная грань фасада
        let xF = 0.0, xG = L.facade, xO = xG + L.gap, xS = xO + L.osb, xI = xS + L.stud, xB = xI + L.batten, xK = xB + L.gkl
        func X(_ x: Double) -> Double { x * k }
        let s = Sk(cg, rect, lo: V2(-1.05, -0.42), hi: V2(X(xK) + 0.15, H + 0.55), pad: 10, right: 205)
        let fin = c.p.interiorFinish
        let gb = c.p.gklBase
        let chain = [(L.facade, "фасад"), (L.gap, "вентзазор"), (L.osb, "ОСП"), (L.stud, "стойка+утеплитель"), (L.batten, "рейка"), (L.gkl, fin.short)].filter { $0.0 > 0 }
        Sk.text("Разрез между стойками (по толщине — масштаб ×3), мм. Снаружи внутрь: " + chain.map { "\($0.1) \(fmt($0.0 * 1000, $0.0 * 1000 == ($0.0 * 1000).rounded() ? 0 : 1))" }.joined(separator: " · ") + " = \(fmt(L.total * 1000, 1))",
                CGPoint(x: rect.minX + 8, y: rect.minY + 9), size: 7, color: .darkGray, maxW: rect.width - 16)
        // перекрытие / основание
        let slab = c.p.selectedFoundation == .slab && c.p.groundFloor != .wood
        s.box(X(xO) - 0.05, -0.3, X(xK) + 0.12, 0, slab ? .concrete : .board)
        s.label(slab ? "плита" : "платформа пола: ОСП 22 по балкам", V2(X(xS) + 0.05, -0.15), size: 6.5, bg: true)
        // перекрытие сверху
        s.box(X(xS), H, X(xK) + 0.12, H + 0.2, .board)
        s.box(X(xI), H - 0.025, X(xK) + 0.12, H, fill: Sk.fillFor(.wood))
        s.box(X(xI), H - 0.0375, X(xK) + 0.12, H - 0.025, fill: gklFill)
        s.label("перекрытие", V2(X(xS) + 0.02, H + 0.12), size: 6.5, bg: true)
        // фасад
        s.box(X(xF), -0.05, X(xG), H + 0.2, c.p.facade == .facingBrick ? .concrete : c.p.facade == .plaster ? .insulation : .board)
        // контррейка (по стойке — за плоскостью разреза)
        if L.gap > 0 { s.box(X(xG), 0.0, X(xO), Module.studLen, fill: NSColor(white: 0.97, alpha: 1), stroke: .gray, w: 0.4) }
        // мембрана
        if c.p.facade != .plaster { s.line(V2(X(xO) - 0.004, -0.02), V2(X(xO) - 0.004, H + 0.05), 1.6, teal) }
        // цокольный отлив с капельником: из-под мембраны наружу за плоскость фасада
        let fl = NSColor(srgbRed: 0.35, green: 0.38, blue: 0.42, alpha: 1)
        s.poly([V2(X(xO), -0.07), V2(X(xF) - 0.05, -0.12), V2(X(xF) - 0.05, -0.15)], fill: nil, stroke: fl, w: 1.8, close: false)
        if L.gap > 0 { s.line(V2(X(xG), -0.04), V2(X(xO), -0.04), 2.2, .darkGray, dash: [2, 2]) }
        // ОСП
        if L.osb > 0 {
            let top = mod ? Module.seamZ + 2.5 : H
            if mod {
                s.box(X(xO), 0, X(xS), Module.seamZ - 0.0015, fill: osbStrip)
                s.box(X(xO), Module.seamZ + 0.0015, X(xS), top, fill: osbFill)
            } else {
                s.box(X(xO), 0, X(xS), top, fill: osbFill)
            }
        }
        // каркас: обвязки, распорка, утеплитель
        s.box(X(xS), 0, X(xI), Module.plate, .timberCut)
        s.box(X(xS), H - 2 * Module.plate, X(xI), H - Module.plate, .timberCut)
        s.box(X(xS), H - Module.plate, X(xI), H, .timberCut)
        let wool: [(Double, Double, String)]
        if mod {
            let zs = Module.seamZ - Module.plate / 2
            s.box(X(xS), zs, X(xI), zs + Module.plate, .timberCut)
            wool = [(Module.plate, zs, "600×600"), (zs + Module.plate, zs + Module.plate + 1.2, "1200×600"), (zs + Module.plate + 1.2, H - 2 * Module.plate, "1200×600")]
        } else {
            wool = [(Module.plate, H - 2 * Module.plate, "")]
        }
        for (z0, z1, _) in wool { s.box(X(xS), z0, X(xI), z1, .insulation) }
        // пароизоляция, обрешётка, ГКЛ
        s.line(V2(X(xI) + 0.004, 0.0), V2(X(xI) + 0.004, H - 0.03), 1.6, blue)
        var zb = 0.3
        while zb < H - 0.1 { s.box(X(xI), zb - 0.025, X(xB), zb + 0.025, .timberCut); zb += 0.6 }
        switch fin {
        case .boards:
            s.box(X(xB), 0.01, X(xK), 3.01, .board)
        case .osb:
            s.box(X(xB), 0, X(xK), Module.seamZ - 0.0015, fill: osbStrip)
            s.box(X(xB), Module.seamZ + 0.0015, X(xK), min(H, Module.seamZ + 2.5), fill: osbFill)
        case .gkl:
            if mod && gb < 0.001 {
                s.box(X(xB), 0.01, X(xK), 0.61, fill: NSColor(white: 0.86, alpha: 1))
                s.box(X(xB), 0.612, X(xK), 3.11, fill: gklFill)
            } else if mod {
                s.box(X(xB), gb + 0.01, X(xK), gb + 2.51, fill: gklFill)
                s.box(X(xB), gb + 2.512, X(xK), 3.11, fill: NSColor(white: 0.86, alpha: 1))
            } else {
                s.box(X(xB), 0.01, X(xK), H - 0.04, fill: gklFill)
            }
        }
        if gb > 0.001 { s.box(X(xI) + 0.01, 0, X(xK) + 0.12, gb, fill: NSColor(white: 0.8, alpha: 1)); s.label("стяжка", V2(X(xK) + 0.01, gb / 2), size: 6, bg: true) }

        // размеры: толщины поверху
        let yT = H + 0.3
        var x0 = 0.0
        for (t, _) in chain {
            s.dim(V2(X(x0), yT), V2(X(x0 + t), yT), off: 0, t < 0.05 ? "" : mm(t), size: 6.5)
            x0 += t
        }
        s.dim(V2(X(0), yT + 0.16), V2(X(xK), yT + 0.16), off: 0, "\(fmt(L.total * 1000, 1))", size: 7)
        // слева — ОСП, справа — ГКЛ
        if mod {
            if L.osb > 0 {
                s.dim(V2(X(xF) - 0.08, 0), V2(X(xF) - 0.08, Module.seamZ), off: 0, "625", size: 6.5)
            }
        }
        if mod && fin == .gkl && gb > 0.001 {
            s.dim(V2(X(xK) + 0.06, gb + 0.01), V2(X(xK) + 0.06, gb + 2.51), off: 0, "ГКЛ 2500", size: 6.5)
            s.dim(V2(X(xK) + 0.06, gb + 2.51), V2(X(xK) + 0.06, 3.11), off: 0, mm(3.11 - gb - 2.51), size: 6.5)
        } else if mod && fin == .boards {
            s.dim(V2(X(xK) + 0.06, 0.01), V2(X(xK) + 0.06, 3.01), off: 0, "доска 3000", size: 6.5)
        }
        if mod {
            if L.osb > 0 {
                s.dim(V2(X(xF) - 0.08, Module.seamZ), V2(X(xF) - 0.08, Module.seamZ + 2.5), off: 0, "лист ОСП 2500", size: 6.5)
            }
            let xd = (X(xS) + X(xI)) / 2
            s.dim(V2(xd, Module.plate), V2(xd, H - 2 * Module.plate), off: 0, "стойка 3000", size: 6.5)
            if fin == .gkl && gb < 0.001 {
                s.dim(V2(X(xK) + 0.06, 0.01), V2(X(xK) + 0.06, 0.61), off: 0, "600", size: 6.5)
                s.dim(V2(X(xK) + 0.06, 0.61), V2(X(xK) + 0.06, 3.11), off: 0, "ГКЛ 2500", size: 6.5)
            }
            s.dim(V2(X(xK) + 0.13, 0), V2(X(xK) + 0.13, H), off: 0, "каркас \(mm(H))", size: 6.5)
        } else {
            s.dim(V2(X(xK) + 0.1, 0), V2(X(xK) + 0.1, H), off: 0, "каркас \(mm(H))", size: 6.5)
        }

        // выноски слева — наружные слои
        let lx = -0.3
        s.leader(V2(X(xF + L.facade / 2), H * 0.92), V2(lx, H * 0.95), "\(c.p.facade.title)\n\(Kit.facadeSize(c.p.facade))", size: 6.5, maxW: 150)
        if L.gap > 0 {
            s.leader(V2(X(xG + L.gap / 2), H * 0.78), V2(lx, H * 0.8), "Контррейка 25×50×3000 по каждой стойке — вентзазор \(mm(L.gap)), открыт вверху и внизу", size: 6.5, maxW: 150)
            s.leader(V2(X(xG + L.gap / 2), -0.04), V2(lx, 0.07), "Перфорированная планка: вход воздуха, от грызунов", size: 6.5, maxW: 150)
        }
        if c.p.facade == .plaster {
            s.leader(V2(X(xO) - 0.004, H * 0.63), V2(lx, H * 0.64), "Без мембраны: минвата СФТК по ОСП, стыки ОСП — диффузионная лента; штукатурка только минеральная", size: 6.5, maxW: 150)
        } else {
            s.leader(V2(X(xO) - 0.004, H * 0.63), V2(lx, H * 0.64), "Ветрозащитная мембрана, рулон 1.5 м, нахлёст 150", size: 6.5, maxW: 150)
        }
        s.leader(V2(X(xF) - 0.03, -0.11), V2(lx, -0.17), c.p.facade == .plaster ? "Цокольный профиль СФТК + отлив с капельником" : "Цокольный отлив с капельником под мембраной", size: 6.5, maxW: 150)
        if L.osb > 0 {
            s.leader(V2(X(xO + L.osb / 2), H * 0.45), V2(lx, H * 0.47), mod ? "ОСП-3 9 мм: лист 2500×1250 вертикально" : "ОСП-3 9 мм", size: 6.5, maxW: 150)
            if mod { s.leader(V2(X(xO + L.osb / 2), 0.3), V2(lx, 0.3), "Полоса ОСП 625 (лист пополам вдоль)", size: 6.5, maxW: 150) }
        }
        // справа — каркас и внутренние слои
        let rx = X(xK) + 0.22
        let layerTxt = Kit.woolLayers(c.b.woolWall, depth: L.stud).map { "\(mm($0))" }.joined(separator: "+")
        s.leader(V2((X(xS) + X(xI)) / 2, H - 0.05), V2(rx, H + 0.05), "Верхняя обвязка 2 ряда \(F.studExt.label)×6000", size: 6.5)
        if mod {
            s.leader(V2((X(xS) + X(xI)) / 2, 2.4), V2(rx, H * 0.83), "Минвата 1200×600×\(layerTxt) — 2 плиты по 1200 в распор", size: 6.5)
            s.leader(V2((X(xS) + X(xI)) / 2, Module.seamZ), V2(rx, H * 0.27), "Распорка \(F.studExt.label)×575 на 600–650 — опора стыков ОСП и ГКЛ", size: 6.5)
            s.leader(V2((X(xS) + X(xI)) / 2, 0.35), V2(rx, H * 0.13), "Половинка плиты 600×600", size: 6.5)
        } else {
            s.leader(V2((X(xS) + X(xI)) / 2, H / 2), V2(rx, H * 0.7), "Минвата \(mm(c.b.woolWall))", size: 6.5)
        }
        s.leader(V2(X(xI) + 0.004, 2.0), V2(rx, H * 0.66), "Пароизоляция, швы на ленте", size: 6.5)
        s.leader(V2((X(xI) + X(xB)) / 2, 1.5), V2(rx, H * 0.55), "Обрешётка 25×50 горизонтально шаг 600", size: 6.5)
        let finTxt: String
        switch fin {
        case .gkl: finTxt = !mod ? "ГКЛ 12.5 мм" : gb > 0.001 ? "ГКЛ 12.5: лист 2500 от стяжки + полоса \(mm(3.11 - gb - 2.51))" : "ГКЛ 12.5: полоса 600 + лист 2500×1200"
        case .boards: finTxt = "Вагонка 14×96×3000 вертикально — без подрезки (не диафрагма → раскосы во внутренних стенах)"
        case .osb: finTxt = "ОСП-3 12 шлиф.: полоса 625 + лист 2500 (вторая диафрагма)"
        }
        s.leader(V2((X(xB) + X(xK)) / 2, 1.2), V2(rx, H * 0.43), finTxt, size: 6.5)
        s.leader(V2((X(xS) + X(xI)) / 2, Module.plate / 2), V2(rx, -0.03), "Нижняя обвязка \(F.studExt.label)", size: 6.5)
        s.label("снаружи", V2(X(xF), -0.38), size: 7, color: .gray)
        s.label("внутри", V2(X(xK) - 0.05, -0.38), size: 7, color: .gray)
    }

    // MARK: - План стены (горизонтальный разрез)

    static func wallPlan(_ c: Ctx, _ cg: CGContext, _ rect: CGRect) {
        let L = layersOf(c)
        let step = c.p.studStep
        let span = step * 4
        let D = L.stud
        let s = Sk(cg, rect, lo: V2(-0.12, -L.facade - L.gap - L.osb - 0.42), hi: V2(span + 0.12, D + L.batten + L.gkl + 0.36), pad: 10, right: 150)
        // наружные слои (y < 0)
        let yO = -L.osb, yG = yO - L.gap, yF = yG - L.facade
        s.box(-0.1, yF, span + 0.1, yG, c.p.facade == .facingBrick ? .concrete : .board)
        if L.osb > 0 {
            var u = 0.0, n = 0
            while u < span - 0.01 {
                s.box(max(u, -0.1) + 0.0015, yO, min(u + 1.25, span + 0.1) - 0.0015, 0, fill: n % 2 == 0 ? osbFill : osbStrip)
                u += 1.25; n += 1
            }
            s.box(-0.1, yO, -0.0015, 0, fill: osbStrip)
        }
        s.line(V2(-0.1, yO - 0.002), V2(span + 0.1, yO - 0.002), 1.4, teal)
        // каркас
        for i in 0...4 {
            let u = Double(i) * step
            s.box(u - 0.025, 0, u + 0.025, D, .timberCut)
            s.box(u - 0.025, yG, u + 0.025, yO - 0.003, .timberCut)       // контррейка
            if i < 4 { s.box(u + 0.025, 0, u + step - 0.025, D, .insulation) }
        }
        // плита утеплителя 600 до установки (пунктир)
        s.poly([V2(step + 0.0125, 0.01), V2(step + 0.6125, 0.01), V2(step + 0.6125, D - 0.01), V2(step + 0.0125, D - 0.01)], fill: nil, stroke: orange, w: 0.9, dash: [3, 2])
        // внутренние слои
        s.line(V2(-0.1, D + 0.002), V2(span + 0.1, D + 0.002), 1.4, blue)
        s.box(-0.1, D + 0.003, span + 0.1, D + L.batten, fill: NSColor(white: 0.97, alpha: 1), stroke: .gray, w: 0.3)
        s.box(-0.1, D + L.batten, 1.2 - 0.001, D + L.batten + L.gkl, fill: gklFill)
        s.box(1.2 + 0.001, D + L.batten, span + 0.1, D + L.batten + L.gkl, fill: gklFill)
        // размеры
        for i in 0..<4 { s.dim(V2(Double(i) * step, yF - 0.02), V2(Double(i + 1) * step, yF - 0.02), off: -0.08, mm(step), size: 6.5) }
        if L.osb > 0 { s.dim(V2(0, yF - 0.02), V2(1.25, yF - 0.02), off: -0.22, "лист ОСП 1250 = 2 шага", size: 6.5) }
        s.dim(V2(step + 0.025, D + L.batten + L.gkl + 0.02), V2(2 * step - 0.025, D + L.batten + L.gkl + 0.02), off: 0.1, "в свету \(mm(step - 0.05))", size: 6.5)
        s.dim(V2(0, D + L.batten + L.gkl + 0.02), V2(1.2, D + L.batten + L.gkl + 0.02), off: 0.25, "ГКЛ 1200 (на рейках)", size: 6.5)
        // выноски справа
        let rx = span + 0.2
        s.leader(V2(2 * step + 0.3, D / 2), V2(rx, D * 0.8), "Плита 600 → просвет \(mm(step - 0.05)): в распор, без подрезки", size: 6.5)
        s.leader(V2(3 * step, D / 2), V2(rx, D * 0.4), "Стойка \(c.b.frame.studExt.label) шаг \(mm(step))", size: 6.5)
        if L.osb > 0 { s.leader(V2(1.25, yO / 2), V2(rx, 0.0), "Стык листов ОСП — по оси стойки", size: 6.5) }
        if L.gap > 0 { s.leader(V2(3 * step, (yG + yO) / 2), V2(rx, -0.07), "Контррейка 25×50 по стойке", size: 6.5) }
        s.leader(V2(3.3 * step, (yF + yG) / 2), V2(rx, -0.13), c.p.facade.title, size: 6.5)
        s.leader(V2(3.3 * step, D + L.batten + L.gkl / 2), V2(rx, D + 0.08), "ГКЛ 12.5 по рейкам 25×50", size: 6.5)
        s.label("снаружи", V2(-0.1, yF - 0.36), size: 7, color: .gray)
        s.label("внутри", V2(-0.1, D + L.batten + L.gkl + 0.32), size: 7, color: .gray)
    }

    // MARK: - Раскладка листов и плит на стене

    /// layer: 0 — ОСП снаружи, 1 — утеплитель, 2 — ГКЛ изнутри
    static func sheetLayout(_ c: Ctx, _ cg: CGContext, _ rect: CGRect, _ i: Int, _ layer: Int) {
        let F = c.b.frame
        guard i < F.walls.count else { return }
        let w = F.walls[i]
        let D = w.depth
        let mod = c.p.modular
        let H = w.height
        let through = abs(w.origin) < 0.01
        // наружная грань стены по длине (u в координатах развёртки)
        let o0 = through ? 0.0 : -D, o1 = through ? w.length : w.length + D
        // внутренняя грань
        let i0 = through ? D : 0.0, i1 = through ? w.length - D : w.length
        let lo = layer == 0 ? o0 : i0, hi = layer == 0 ? o1 : i1
        let s = Sk(cg, rect, lo: V2(lo - 0.3, -0.5), hi: V2(hi + 0.3, H + 0.45), pad: 10)
        // снаружи вид зеркальный
        func U(_ u: Double) -> Double { layer == 0 ? lo + hi - u : u }
        func rectU(_ u0: Double, _ u1: Double) -> (Double, Double) { let a = U(u0), b = U(u1); return (min(a, b), max(a, b)) }
        let studs = w.rects.filter { [.stud, .cornerStud, .king, .jack].contains($0.kind) }
        func hitsOpening(_ u0: Double, _ u1: Double, _ z0: Double, _ z1: Double) -> Bool {
            w.openings.contains { $0.u0 < u1 - 0.01 && $0.u1 > u0 + 0.01 && $0.z0 < z1 - 0.01 && $0.z1 > z0 + 0.01 }
        }
        // каркас — тонко
        for r in studs { let (a, b) = rectU(r.u0, r.u1); s.box(a, r.z0, b, r.z1, fill: NSColor(white: 0.9, alpha: 1), stroke: NSColor(white: 0.75, alpha: 1), w: 0.3) }

        var full = 0, strips = 0, cut = 0, odd: [Double] = []
        switch layer {
        case 2 where c.p.interiorFinish == .boards:
            var u = lo
            while u < hi - 0.01 {
                let (a, b) = rectU(u, min(u + 0.088, hi))
                s.box(a, 0.01, b, 3.01, fill: Sk.fillFor(.wood), stroke: NSColor(srgbRed: 0.6, green: 0.45, blue: 0.25, alpha: 1), w: 0.3)
                full += 1
                u += 0.088
            }
            for r in w.braces { s.line(V2(U(r.u0), r.z0), V2(U(r.u1), r.z1), 2.5, color(.brace)) }
        case 0, 2:
            let interiorOSB = layer == 2 && c.p.interiorFinish == .osb
            let cw = layer == 0 || interiorOSB ? 1.25 : 1.2
            let gb = c.p.gklBase
            let rows: [(Double, Double, Bool)] = mod ? (layer == 0 || interiorOSB ? [(0, Module.seamZ, true), (Module.seamZ, Module.seamZ + 2.5, false)]
                                                                : gb > 0.001 ? [(gb + 0.01, gb + 2.51, false), (gb + 2.51, 3.11, true)] : [(0.01, 0.61, true), (0.61, 3.11, false)])
                                                     : [(0, min(2.5, H), false), (2.5, H, true)]
            var u = lo
            var n = 0
            while u < hi - 0.01 {
                let u1 = min(u + cw, hi)
                let partial = u1 - u < cw - 0.01
                if partial { odd.append(u1 - u) }
                for (z0, z1, strip) in rows where z1 > z0 + 0.01 {
                    let (a, b) = rectU(u, u1)
                    let hole = hitsOpening(u, u1, z0, z1)
                    var fill = strip ? (layer == 0 ? osbStrip : NSColor(white: 0.84, alpha: 1)) : (layer == 0 ? osbFill : gklFill)
                    if partial { fill = warnFill }
                    s.box(a + 0.006, z0 + 0.003, b - 0.006, z1 - 0.003, fill: fill.withAlphaComponent(0.85), stroke: .black, w: 0.6)
                    if hole { cut += 1 }
                    if strip { strips += 1 } else { full += 1 }
                    n += 1
                    s.label("\(n)", V2((a + b) / 2, (z0 + z1) / 2 + (strip ? 0 : 0.6)), size: 7, ax: 0.5, bold: true, color: NSColor(white: 0.25, alpha: 1))
                }
                u = u1
            }
        default:
            // утеплитель по пролётам между стойками
            let xs = Array(Set(studs.map { ($0.u0 + $0.u1) / 2 }.map { ($0 * 1000).rounded() / 1000 })).sorted()
            let zones: [(Double, Double)] = mod ? [(Module.plate, Module.seamZ - Module.plate / 2), (Module.seamZ + Module.plate / 2, Module.seamZ + Module.plate / 2 + 1.2),
                                                   (Module.seamZ + Module.plate / 2 + 1.2, H - 2 * Module.plate)]
                                                : [(Module.plate, H - 2 * Module.plate)]
            for k in 1..<max(xs.count, 1) {
                let a0 = xs[k - 1] + 0.025, a1 = xs[k] - 0.025
                guard a1 - a0 > 0.05 else { continue }
                let fits = abs((a1 - a0) - (c.p.studStep - 0.05)) < 0.012
                for (z0, z1) in zones {
                    if hitsOpening(a0, a1, z0, z1) { continue }
                    let (a, b) = rectU(a0, a1)
                    s.box(a, z0, b, z1, .insulation, fill: fits ? okFill : warnFill, stroke: NSColor(white: 0.4, alpha: 1), w: 0.4)
                    if fits { full += 1 } else { odd.append(a1 - a0) }
                }
            }
            for r in w.rects where [.header, .sillPiece, .cripple, .nogging, .bottomPlate, .topPlate, .capPlate].contains(r.kind) {
                let (a, b) = rectU(r.u0, r.u1)
                s.box(a, r.z0, b, r.z1, fill: color(r.kind), stroke: NSColor(white: 0.4, alpha: 1), w: 0.3)
            }
        }
        // проёмы
        for o in w.openings {
            let (a, b) = rectU(o.u0, o.u1)
            s.box(a, o.z0, b, o.z1, fill: NSColor(white: 1, alpha: 0.92), stroke: blue, w: 1)
            s.label(o.label, V2((a + b) / 2, (o.z0 + o.z1) / 2), size: 6, ax: 0.5, color: blue)
        }
        // размеры
        s.dim(V2(lo, 0), V2(hi, 0), off: -0.3, "\(layer == 0 ? "по наружной грани" : "по внутренней грани") \(mm(hi - lo))", size: 7)
        switch layer {
        case 0:
            if mod {
                s.dim(V2(hi, 0), V2(hi, Module.seamZ), off: -0.12, "625", size: 6.5)
                s.dim(V2(hi, Module.seamZ), V2(hi, Module.seamZ + 2.5), off: -0.12, "2500", size: 6.5)
            }
            s.dim(V2(hi - 1.25, H), V2(hi, H), off: 0.12, "1250", size: 6.5)
        case 2:
            if mod && c.p.interiorFinish == .gkl {
                let gb = c.p.gklBase
                if gb > 0.001 {
                    s.dim(V2(hi, gb + 0.01), V2(hi, gb + 2.51), off: -0.12, "2500", size: 6.5)
                    s.dim(V2(hi, gb + 2.51), V2(hi, 3.11), off: -0.12, mm(3.11 - gb - 2.51), size: 6.5)
                } else {
                    s.dim(V2(hi, 0.01), V2(hi, 0.61), off: -0.12, "600", size: 6.5)
                    s.dim(V2(hi, 0.61), V2(hi, 3.11), off: -0.12, "2500", size: 6.5)
                }
                s.dim(V2(lo, H), V2(lo + 1.2, H), off: 0.12, "1200", size: 6.5)
            } else if c.p.interiorFinish == .boards {
                s.dim(V2(hi, 0.01), V2(hi, 3.01), off: -0.12, "3000", size: 6.5)
            }
        default:
            if mod {
                s.dim(V2(hi + 0.05, Module.plate), V2(hi + 0.05, Module.seamZ - 0.025), off: -0.12, "550", size: 6.5)
                s.dim(V2(hi + 0.05, Module.seamZ + 0.025), V2(hi + 0.05, Module.seamZ + 1.225), off: -0.12, "1200", size: 6.5)
                s.dim(V2(hi + 0.05, Module.seamZ + 1.225), V2(hi + 0.05, H - 0.1), off: -0.12, "1200", size: 6.5)
            }
        }
        let summary: String
        switch layer {
        case 0: summary = "Снаружи (вид с улицы). Целых листов 2500×1250: \(full), полос 625 (½ листа): \(strips) → \(full + (strips + 1) / 2) листов. Листов с вырезом под проём: \(cut)" + (odd.isEmpty ? ". Доборов нет — стена кратна листу." : ". ⚠︎ Доборный лист шириной \(odd.map { mm($0) }.joined(separator: ", ")) мм — подогнать размер под модуль.")
                case 2 where c.p.interiorFinish == .boards: summary = "Изнутри. Вагонка 14×96×3000 вертикально: ≈ \(full) досок на стену, по длине не режется. " + (w.braces.isEmpty ? "Вагонка жёсткости не даёт: у этой наружной стены её даёт ОСП снаружи, во внутренних стенах — врезные раскосы (см. развёртки П)." : "Красным — раскосы в каркасе (вагонка жёсткости не даёт).")
        case 2: summary = "Изнутри. Целых листов: \(full), полос: \(strips) → \(full + (strips + 1) / 2) листов" + (odd.isEmpty ? "" : "; добор \(odd.map { mm($0) }.joined(separator: ", ")) мм (у угла режется по месту)")
        default: summary = "Изнутри. Зелёное — плита встаёт целиком (\(full) мест), оранжевое — нужна подрезка (\(odd.count) мест: у углов, проёмов и примыканий)."
        }
        Sk.text(summary, CGPoint(x: rect.minX + 8, y: rect.minY + 9), size: 7, color: .darkGray, maxW: rect.width - 16)
        _ = s
    }

    // MARK: - Соединения

    static func fasteners(_ c: Ctx, _ cg: CGContext, _ rect: CGRect) {
        let cols = 3, rows = 2
        let cw = rect.width / CGFloat(cols), ch = rect.height / CGFloat(rows)
        let D = c.b.frame.studExt
        let nail = NSColor(white: 0.2, alpha: 1)
        func panel(_ i: Int, _ title: String, _ lo: V2, _ hi: V2, _ draw: (Sk) -> Void) {
            let r = CGRect(x: rect.minX + CGFloat(i % cols) * cw, y: rect.minY + CGFloat(i / cols) * ch, width: cw, height: ch)
            cg.saveGState()
            cg.setStrokeColor(NSColor(white: 0.85, alpha: 1).cgColor); cg.setLineWidth(0.5); cg.stroke(r.insetBy(dx: 2, dy: 2))
            let s = Sk(cg, r, lo: lo, hi: hi, pad: 12, top: 26)
            draw(s)
            cg.restoreGState()
            Sk.text("\(i + 1). " + title, CGPoint(x: r.minX + 8, y: r.minY + 8), size: 7, ay: 0, maxW: cw - 16)
        }
        func nailV(_ s: Sk, _ x: Double, _ y0: Double, _ y1: Double) {
            s.line(V2(x, y0), V2(x, y1), 1.4, nail)
            s.line(V2(x - 0.012, y0), V2(x + 0.012, y0), 2, nail)
        }
        // 1. стойка в обвязку
        panel(0, "Стойка → обвязка: 2 гвоздя 4×100 в торец через обвязку", V2(-0.05, -0.12), V2(0.65, 0.55)) { s in
            s.box(0, 0, 0.6, 0.05, fill: color(.bottomPlate))
            s.box(0.275, 0.05, 0.325, 0.5, fill: color(.stud))
            nailV(s, 0.29, -0.01, 0.09); nailV(s, 0.31, -0.01, 0.09)
            s.label("обвязка \(D.label)", V2(0.02, -0.06), size: 6.5)
            s.label("стойка", V2(0.34, 0.35), size: 6.5)
        }
        // 2. двойная стойка
        panel(1, "Угловая / двойная стойка: гвозди 4×100 шаг 300 вразбежку", V2(-0.3, -0.05), V2(0.45, 1.05)) { s in
            s.box(0, 0, 0.05, 1.0, fill: color(.cornerStud)); s.box(0.05, 0, 0.1, 1.0, fill: color(.stud))
            for (k, z) in [0.15, 0.45, 0.75].enumerated() { s.dot(V2(k % 2 == 0 ? 0.035 : 0.065, z), 2.4, nail) }
            s.dim(V2(0.12, 0.15), V2(0.12, 0.45), off: -0.08, "300", size: 6.5)
        }
        // 3. перевязка верхней обвязки
        panel(2, "Верхняя обвязка: 2-й ряд перекрывает угол и стыки ≥ 1250, гвозди 4×100 шаг 400", V2(-0.1, -0.1), V2(1.3, 1.1)) { s in
            let w = D.wm
            // 1-й ряд (ниже, смещён для наглядности): проходная доска по X, примыкающая — по Y
            let o = 0.06
            s.box(o, -o, 1.2 + o, w - o, fill: color(.topPlate).withAlphaComponent(0.5), stroke: .gray)
            s.box(o, w - o, w + o, 1.0 - o, fill: color(.topPlate).withAlphaComponent(0.5), stroke: .gray)
            // 2-й ряд: наоборот — проходная по Y, стыки сдвинуты
            s.box(0, 0, w, 1.0, fill: color(.capPlate), stroke: .black)
            s.box(w, 0, 1.2, w, fill: color(.capPlate), stroke: .black)
            for x in [0.35, 0.75, 1.1] { s.dot(V2(x, w / 2), 2.2, nail) }
            for y in [0.4, 0.8] { s.dot(V2(w / 2, y), 2.2, nail) }
            s.label("1-й ряд — стыкуется в углу", V2(0.3, 0.55), size: 6.5)
            s.label("2-й ряд — внахлёст через угол", V2(0.3, 0.42), size: 6.5, color: .brown)
        }
        // 4. балка на обвязке
        panel(3, "Балка → обвязка: опора/уголок 90×90×65 ×2 на анкерных гвоздях 4×40", V2(-0.1, -0.1), V2(0.9, 0.45)) { s in
            s.box(0, 0, 0.3, 0.05, fill: color(.capPlate))
            s.box(0.05, 0.05, 0.85, 0.25, fill: color(.joist))
            s.poly([V2(0.12, 0.05), V2(0.2, 0.05)], stroke: NSColor.darkGray, w: 3, close: false)
            s.poly([V2(0.2, 0.05), V2(0.2, 0.14)], stroke: NSColor.darkGray, w: 3, close: false)
            for z in [0.08, 0.12] { s.dot(V2(0.2, z), 1.6, nail) }
            s.label("опора ≥ 100", V2(0.05, -0.06), size: 6.5)
        }
        // 5. стропило
        panel(4, "Стропило → обвязка: запил ≤ ⅓h, 2 уголка + ветровая скоба к стойке", V2(-0.1, -0.35), V2(1.0, 0.6)) { s in
            let a = 0.55
            s.box(0, -0.1, 0.25, 0, fill: color(.capPlate))
            s.box(0.1, -0.35, 0.15, -0.1, fill: color(.stud))
            // нижняя грань стропила проходит через внутренний край обвязки; запил: горизонт. площадка + вертикальный рез
            let t = tan(a), n = V2(-sin(a), cos(a)) * 0.2 / cos(a) * cos(a)
            func yb(_ x: Double) -> Double { (x - 0.25) * t }
            let A = V2(-0.08, yb(-0.08)), B = V2(0, yb(0)), C = V2(0, 0), Dp = V2(0.25, 0), E = V2(0.95, yb(0.95))
            s.poly([A, B, C, Dp, E, E + n, A + n], fill: color(.rafter), stroke: .black, w: 0.6)
            s.poly([V2(0.2, -0.3), V2(0.2, 0.05), V2(0.3, 0.12)], stroke: NSColor.darkGray, w: 2, close: false)
            s.label("скоба", V2(0.22, -0.25), size: 6.5)
        }
        // 6. ОСП
        panel(5, "ОСП → каркас: гвозди 2.5×50 шаг 150 по краю, 300 в поле, 10 от кромки", V2(-0.1, -0.1), V2(1.4, 2.6)) { s in
            for x in [0.0, 0.625, 1.25] { s.box(x - 0.025, 0, x + 0.025, 2.5, fill: color(.stud)) }
            s.box(0, 0, 1.25, 2.5, fill: osbFill.withAlphaComponent(0.55), stroke: .black)
            var z = 0.075
            while z < 2.5 { s.dot(V2(0.012, z), 1.3, nail); s.dot(V2(1.238, z), 1.3, nail); z += 0.15 }
            z = 0.15
            while z < 2.4 { s.dot(V2(0.625, z), 1.3, nail); z += 0.3 }
            s.dim(V2(1.3, 0.075), V2(1.3, 0.225), off: -0.02, "150", size: 6)
        }
    }

    // MARK: - Гидроизоляция под брус: последовательность

    static func sillSteps(_ c: Ctx, _ cg: CGContext, _ rect: CGRect) {
        let slab = c.p.selectedFoundation == .slab
        let F = c.b.frame
        let stem = slab ? 0.5 : (c.p.selectedFoundation == .strip ? (c.r.strip.ext?.stemW ?? 0.4) : c.r.piles.bg)
        let bw = slab ? F.studExt.wm : F.sillSec.wm
        let bh = slab ? 0.05 : F.sillSec.tm
        let titles = ["1. Очистить, загрунтовать праймером", "2. Наплавить 2 слоя полосой на 50 шире бруса", "3. Лента ППЭ 8 мм, анкеры М12", "4. Брус, шайба DIN 9021, гайка"]
        let pw = rect.width / 4
        for i in 0..<4 {
            let r = CGRect(x: rect.minX + CGFloat(i) * pw, y: rect.minY, width: pw, height: rect.height)
            let s = Sk(cg, r, lo: V2(-0.12, -0.32), hi: V2(stem + 0.12, 0.3), pad: 8, top: 22)
            Sk.text(titles[i], CGPoint(x: r.minX + 6, y: r.minY + 6), size: 7, ay: 0, maxW: pw - 12)
            let x0 = (stem - bw) / 2 * 0
            s.box(0, -0.3, stem, 0, .concrete)
            s.line(V2(0, 0.003), V2(stem, 0.003), 2, NSColor(srgbRed: 0.35, green: 0.22, blue: 0.1, alpha: 1))
            if i >= 1 {
                s.box(x0 - 0.05, 0.004, x0 + bw + 0.05, 0.012, fill: .black)
                s.box(x0 - 0.05, 0.012, x0 + bw + 0.05, 0.02, fill: NSColor(white: 0.25, alpha: 1))
            }
            if i >= 2 {
                s.box(x0 + bw * 0.2, 0.02, x0 + bw * 0.8, 0.028, fill: blue)
                s.line(V2(x0 + bw / 2, -0.15), V2(x0 + bw / 2, 0.02 + bh + 0.04), 2.2, NSColor(white: 0.4, alpha: 1))
            }
            if i >= 3 {
                s.box(x0, 0.028, x0 + bw, 0.028 + bh, .timberCut)
                s.box(x0 + bw / 2 - 0.025, 0.028 + bh, x0 + bw / 2 + 0.025, 0.035 + bh, fill: .darkGray)
                s.box(x0 + bw / 2 - 0.013, 0.035 + bh, x0 + bw / 2 + 0.013, 0.05 + bh, fill: .black)
            }
            if i == 1 { s.dim(V2(x0 - 0.05, 0.02), V2(x0, 0.02), off: 0.06, "50", size: 6) }
        }
    }

    // MARK: - Жёсткость каркаса

    static func rigidity(_ c: Ctx, _ cg: CGContext, _ rect: CGRect) {
        let pw = rect.width / 4
        let items: [(String, Int)] = [("Без диагоналей каркас складывается от ветра", 0), ("Временные укосины — до обшивки", 1),
                                      ("Врезной раскос 25×100 под 45–60°", 2), ("ОСП по контуру = раскос по всей площади (диафрагма)", 3)]
        for (i, it) in items.enumerated() {
            let r = CGRect(x: rect.minX + CGFloat(i) * pw, y: rect.minY, width: pw, height: rect.height)
            let s = Sk(cg, r, lo: V2(-0.4, -0.15), hi: V2(2.1, 2.9), pad: 8, top: 26)
            Sk.text(it.0, CGPoint(x: r.minX + 6, y: r.minY + 6), size: 7, ay: 0, maxW: pw - 12)
            let skew = it.1 == 0 ? 0.45 : 0.0
            let H = 2.6, W = 1.875
            s.box(-0.1, -0.1, W + 0.1, 0, .board)
            // рама
            s.poly([V2(0, 0), V2(W, 0), V2(W + skew, H), V2(skew, H)], fill: nil, stroke: NSColor(white: 0.3, alpha: 1), w: 1.2)
            for k in 0...3 { let x = Double(k) * 0.625; s.line(V2(x, 0), V2(x + skew, H), 3, color(.stud)) }
            s.line(V2(skew, H), V2(W + skew, H), 4, color(.topPlate))
            s.line(V2(0, 0.02), V2(W, 0.02), 4, color(.bottomPlate))
            switch it.1 {
            case 0:
                s.poly([V2(-0.35, H * 0.8), V2(-0.05, H * 0.8)], stroke: blue, w: 2, close: false)
                s.poly([V2(-0.12, H * 0.84), V2(-0.05, H * 0.8), V2(-0.12, H * 0.76)], stroke: blue, w: 2, close: false)
                s.label("ветер", V2(-0.38, H * 0.88), size: 6.5, color: blue)
                s.label("✕", V2(W / 2 + skew / 2, H / 2), size: 22, ax: 0.5, bold: true, color: red)
            case 1:
                s.line(V2(W, H * 0.65), V2(W + 0.0, H * 0.65), 1)
                s.line(V2(0.625, H * 0.65), V2(-0.35, 0), 3, color(.tempBrace))
                s.line(V2(1.25, H * 0.65), V2(2.05, 0), 3, color(.tempBrace))
            case 2:
                s.line(V2(0.05, 0.05), V2(1.4, H - 0.05), 4, color(.brace))
            default:
                s.box(0, 0, 1.25, 0.625, fill: osbStrip.withAlphaComponent(0.7))
                s.box(1.25, 0, W, 0.625, fill: osbStrip.withAlphaComponent(0.7))
                s.box(0, 0.625, 1.25, H, fill: osbFill.withAlphaComponent(0.7))
                s.box(1.25, 0.625, W, H, fill: osbFill.withAlphaComponent(0.7))
                var z = 0.1
                while z < H { s.dot(V2(0.02, z), 1, .black); s.dot(V2(1.25, z), 1, .black); z += 0.15 }
            }
        }
    }
}
