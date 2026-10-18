import Foundation

/// Готовый проект дома: форма, размеры, стены, кровля, планировка, окна/двери и тип фундамента
struct HousePreset: Identifiable {
    let id: String
    let name: String
    let summary: String
    let shape: HouseShape
    let foundation: FoundationKind
    let build: (Project) -> Void

    /// Проект строится и сразу подгоняется под модуль стандартных материалов
    func apply(_ p: Project) {
        build(p)
        p.sheathing = .osb
        p.fitToModule()
        // тёмные коридоры и комнаты — дополнительные окна по месту
        Daylight.improve(p)
    }

    /// Площадь застройки по осям стен и общая (с учётом этажей)
    func area() -> (footprint: Double, total: Double, floors: Int) {
        let p = Project()
        apply(p)
        let a = Geo.area(p.rings)
        return (a, a * Double(p.floors), p.floors)
    }
}

/// Помощник построения планировки в координатах дома (м)
struct PresetBuilder {
    let p: Project

    func setup(_ shape: HouseShape, L: Double, W: Double, a: Double = 4, b: Double = 4, il: Double = 4, iw: Double = 4,
               wall: WallMaterial, floors: Int = 1, fh: Double = 3.0, roof: RoofType, covering: RoofCovering = .seam,
               angle: Double? = nil, overhang: Double = 0.4, foundation: FoundationKind, floor: FloorType = .woodJoists,
               facade: FacadeFinish = .imitationTimber) {
        p.shape = shape
        p.edgeConfigs = [:]
        p.partitions = []
        p.openings = []
        p.length = L; p.width = W; p.wingA = a; p.wingB = b; p.innerL = il; p.innerW = iw
        p.defaultMaterial = wall
        p.floors = floors; p.floorHeight = fh
        p.roofType = roof; p.covering = covering
        p.roofAngleAuto = angle == nil
        if let angle { p.roofAngle = angle }
        p.overhang = roof == .flat ? 0 : overhang
        p.ridgeAlongLong = true
        p.flatSlab = .wood
        p.roofInsulated = true
        p.selectedFoundation = foundation
        p.floorType = floor
        p.groundFloor = foundation == .slab ? .onGround : .wood
        p.floorSystem = foundation == .slab ? .semiDry : .osbJoists
        p.floorHeating = foundation == .slab ? .water : .none
        p.floorFinish = foundation == .slab ? .spc : .laminate
        p.interiorFinish = .gkl
        p.roomMarks = []
        p.facade = facade
        p.darkFrames = true
    }

    /// Перегородка; несущие получают свой фундамент (под лентой — отдельная лента)
    func wall(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ m: WallMaterial = .frame150, bearing: Bool = false) {
        p.partitions.append(Partition(a: V2(x1, y1), b: V2(x2, y2), material: m, onFoundation: bearing))
    }

    /// Проём с центром в точке (x, y) на стене или перегородке
    func open(_ k: OpeningKind, _ x: Double, _ y: Double, w: Double? = nil, h: Double? = nil, sill: Double? = nil) {
        let pt = V2(x, y)
        var host: OpeningHost?
        var a = V2(0, 0), b = V2(0, 0)
        if let pt0 = p.partitions.first(where: { Geo.distToSegment(pt, $0.a, $0.b) < 0.02 }) {
            host = .partition(pt0.id); a = pt0.a; b = pt0.b
        } else if let (i, e) = p.edges.enumerated().first(where: { Geo.distToSegment(pt, $0.element.a, $0.element.b) < 0.02 }) {
            host = .edge(i); a = e.a; b = e.b
        }
        guard let host else { return }
        var o = Opening.make(k, host: host, pos: dot2(pt - a, (b - a).unit))
        if let w { o.width = w }
        if let h { o.height = h }
        if let sill { o.sill = sill }
        p.openings.append(o)
    }

    // Типовые размеры
    /// Назначение комнаты по точке внутри неё
    func room(_ t: RoomType, _ x: Double, _ y: Double) { p.roomMarks.append(RoomMark(at: V2(x, y), type: t)) }

    func bathWindow(_ x: Double, _ y: Double) { open(.window, x, y, w: 0.8, h: 0.6, sill: 1.5) }
    func techWindow(_ x: Double, _ y: Double) { open(.window, x, y, w: 0.8, h: 0.8, sill: 1.2) }
}

extension HousePreset {
    static let all: [HousePreset] = [
        // ───────── Квадрат ─────────
        HousePreset(id: "cube81", name: "Куб с плоской кровлей",
                    summary: "Каркасный куб 8.75×8.75 м (7×2 листа ОСП по стене), каркас 200 мм со штукатурным фасадом и плоской кровлей по деревянным балкам: кухня-гостиная 33 м² с окном в пол и порталом, 2 спальни с панорамными окнами, санузел, прихожая. Несущая каркасная стена посередине сокращает пролёт балок до 5.5 м.",
                    shape: .square, foundation: .slab) { p in
            let b = PresetBuilder(p: p)
            b.setup(.square, L: 9, W: 9, wall: .frame200, roof: .flat, foundation: .slab, facade: .plaster)
            b.wall(5.5, 0, 5.5, 9, .frame150, bearing: true)
            b.wall(5.5, 4.5, 9, 4.5)
            b.wall(0, 3, 5.5, 3)
            b.wall(3, 0, 3, 3)
            b.open(.glassDoor, 1.5, 0)
            b.bathWindow(4.25, 0)
            b.open(.window, 7.25, 0, w: 1.2)
            b.open(.panoramic, 9, 2.25, w: 1.8)
            b.open(.panoramic, 9, 6.75, w: 1.8)
            b.open(.window, 7.25, 9, w: 1.2)
            b.open(.panoramic, 2.75, 9, w: 3.0)
            b.open(.glassDoor, 0, 6.2, w: 2.4)
            b.open(.window, 0, 3.9, w: 1.2, h: 1.2, sill: 0.9)
            b.open(.door, 5.5, 3.8)
            b.open(.door, 5.5, 5.3)
            b.open(.door, 3, 1.6)
            b.open(.glassDoor, 1.5, 3, w: 0.9)
        },
        HousePreset(id: "sq100", name: "Под вальмой с кирпичной облицовкой",
                    summary: "Каркас 200 мм с облицовкой кирпичом, 10×10 м по каркасу (8 листов ОСП на стену): кухня-гостиная 30 м² с выходом на террасу, 2 спальни, санузел, котельная. Облицовка опирается на ленту — она тяжелее, чем у других каркасных фасадов.",
                    shape: .square, foundation: .strip) { p in
            let b = PresetBuilder(p: p)
            b.setup(.square, L: 10, W: 10, wall: .frame200, fh: 2.9, roof: .hip, covering: .softShingle, overhang: 0.5, foundation: .strip, facade: .facingBrick)
            b.wall(0, 5, 10, 5, .frame150, bearing: true)
            b.wall(3.8, 0, 3.8, 5)
            b.wall(6.2, 0, 6.2, 5)
            b.wall(6.2, 2.5, 10, 2.5)
            b.wall(6, 5, 6, 10)
            b.open(.glassDoor, 5.0, 0)
            b.open(.window, 1.9, 0, w: 1.5)
            b.techWindow(8.1, 0)
            b.bathWindow(10, 3.75)
            b.open(.panoramic, 10, 7.5, w: 1.8)
            b.open(.window, 8, 10, w: 1.5)
            b.open(.panoramic, 3, 10, w: 3.0)
            b.open(.glassDoor, 0, 7.5, w: 2.4)
            b.open(.window, 0, 2.5, w: 1.5)
            b.open(.door, 3.8, 4.2)
            b.open(.door, 6.2, 3.8)
            b.open(.door, 6.2, 1.2)
            b.open(.glassDoor, 5.0, 5, w: 1.2)
            b.open(.door, 6, 5.8)
        },

        // ───────── Прямоугольник ─────────
        HousePreset(id: "barn84", name: "Барнхаус",
                    summary: "Барнхаус 12.5×7.5 м по каркасу: каркас 200 мм, фиброцементный фасад, кровля 40° из фальца без свесов. Кухня-гостиная 38 м² с порталом в торце и окнами в пол, 2 спальни с панорамными окнами, санузел.",
                    shape: .rectangle, foundation: .slab) { p in
            let b = PresetBuilder(p: p)
            b.setup(.rectangle, L: 12, W: 7, wall: .frame200, roof: .gable, covering: .seam, angle: 40, overhang: 0.15, foundation: .slab, facade: .fiberCement)
            b.wall(5.5, 0, 5.5, 7)
            b.wall(7.5, 0, 7.5, 7)
            b.wall(7.5, 3.5, 12, 3.5)
            b.wall(5.5, 4.5, 7.5, 4.5)
            b.open(.glassDoor, 6.5, 0)
            b.open(.panoramic, 2.75, 0, w: 2.0)
            b.open(.panoramic, 2.75, 7, w: 2.0)
            b.open(.glassDoor, 0, 3.5, w: 2.8)
            b.open(.panoramic, 12, 1.75, w: 1.5)
            b.open(.panoramic, 12, 5.25, w: 1.5)
            b.bathWindow(6.5, 7)
            b.open(.window, 9.75, 0, w: 1.2)
            b.open(.glassDoor, 5.5, 2.2, w: 0.9)
            b.open(.door, 7.5, 2.8)
            b.open(.door, 7.5, 4.0)
            b.open(.door, 6.5, 4.5)
        },
        HousePreset(id: "scandi112", name: "Скандинавский дом",
                    summary: "Тёплый каркас 250 мм (с перекрёстным утеплением) и имитация бруса, 13.75×8.75 м по каркасу. 3 спальни, кухня-гостиная 40 м² с порталом и окнами в пол на сад, санузел, прачечная, котельная.",
                    shape: .rectangle, foundation: .strip) { p in
            let b = PresetBuilder(p: p)
            b.setup(.rectangle, L: 14, W: 8, wall: .frame250, fh: 2.8, roof: .gable, covering: .compositeTile, overhang: 0.5, foundation: .strip)
            b.wall(0, 4, 14, 4, .frame150, bearing: true)
            b.wall(4, 0, 4, 4)
            b.wall(4, 4, 4, 8)
            b.wall(6.5, 0, 6.5, 4)
            b.wall(9, 0, 9, 4)
            b.wall(11, 0, 11, 4)
            b.open(.glassDoor, 5.25, 0)
            b.open(.window, 2, 0, w: 1.5)
            b.bathWindow(7.75, 0)
            b.techWindow(10, 0)
            b.open(.window, 12.5, 0, w: 1.5)
            b.open(.window, 14, 2, w: 1.2)
            b.open(.window, 14, 6, w: 1.5)
            b.open(.panoramic, 6.5, 8, w: 2.4)
            b.open(.glassDoor, 9.25, 8, w: 2.0)
            b.open(.panoramic, 12, 8, w: 2.0)
            b.open(.panoramic, 2, 8, w: 1.6)
            b.open(.window, 0, 6, w: 1.5)
            b.open(.window, 0, 2, w: 1.2)
            b.open(.door, 4, 3.3)
            b.open(.door, 6.5, 3.3)
            b.open(.glassDoor, 5.25, 4, w: 1.2)
            b.open(.door, 4, 4.8)
            b.open(.door, 10, 4)
            b.open(.door, 12.5, 4)
        },
        HousePreset(id: "two144", name: "Двухэтажный каркасный",
                    summary: "Компактный каркасный 8.75×8.75 м в 2 этажа (≈ 150 м²), сайдинг, перекрытие по балкам со стяжкой под тёплый пол: внизу кухня-гостиная с окном в пол, прихожая, санузел, кабинет; на 2-м этаже — спальни.",
                    shape: .rectangle, foundation: .strip) { p in
            let b = PresetBuilder(p: p)
            b.setup(.rectangle, L: 9, W: 8, wall: .frame200, floors: 2, fh: 2.8, roof: .gable, covering: .metalTile, overhang: 0.5,
                    foundation: .strip, floor: .woodScreed, facade: .siding)
            b.wall(0, 4.2, 9, 4.2, .frame150, bearing: true)
            b.wall(4.5, 0, 4.5, 4.2)
            b.wall(3, 4.2, 3, 8)
            b.open(.glassDoor, 2.25, 0)
            b.open(.window, 6.75, 0, w: 1.5)
            b.open(.window, 9, 2.1, w: 1.2)
            b.open(.window, 9, 6.1, w: 1.5)
            b.open(.panoramic, 6, 8, w: 2.4)
            b.open(.window, 1.5, 8, w: 1.2)
            b.open(.window, 0, 6.1, w: 1.2)
            b.open(.window, 0, 2.1, w: 1.2)
            b.open(.door, 4.5, 3.4)
            b.open(.glassDoor, 2.25, 4.2, w: 1.2)
            b.open(.door, 3, 5.0)
            b.room(.hall, 2.2, 2.0)
            b.room(.office, 6.6, 2.0)
        },

        // ───────── Г-образные (плита, скатная кровля) ─────────
        HousePreset(id: "l97", name: "Г-образный с односкатной кровлей",
                    summary: "Каркас 200 мм со штукатурным фасадом. Ночная зона в длинном крыле: 2 спальни и галерея-коридор с окнами в пол на террасу. Кухня-гостиная 40 м² в коротком крыле с порталом.",
                    shape: .lShape, foundation: .slab) { p in
            let b = PresetBuilder(p: p)
            b.setup(.lShape, L: 12, W: 11, a: 6, b: 5, wall: .frame200, roof: .shed, covering: .seam, overhang: 0.4, foundation: .slab, facade: .plaster)
            b.wall(0, 3, 5, 3)
            b.wall(2.5, 0, 2.5, 3)
            b.wall(5, 0, 5, 4.6)
            b.wall(5, 4.6, 12, 4.6)
            b.wall(8.5, 0, 8.5, 4.6)
            b.open(.glassDoor, 1.25, 0)
            b.bathWindow(3.75, 0)
            b.open(.window, 6.75, 0, w: 1.5)
            b.open(.window, 10.25, 0, w: 1.5)
            b.open(.panoramic, 12, 2.3, w: 1.6)
            b.open(.panoramic, 7, 6, w: 2.0)
            b.open(.panoramic, 10, 6, w: 2.0)
            b.open(.glassDoor, 5, 7.5, w: 2.4)
            b.open(.panoramic, 5, 9.8, w: 1.6)
            b.open(.panoramic, 2.5, 11, w: 3.0)
            b.open(.window, 0, 6.5, w: 1.5, h: 1.2, sill: 0.9)
            b.open(.glassDoor, 1.25, 3, w: 0.9)
            b.open(.door, 2.5, 1.5)
            b.open(.door, 6.75, 4.6)
            b.open(.door, 10.25, 4.6)
        },
        HousePreset(id: "l114", name: "Г-образный с двускатной кровлей",
                    summary: "Каркас 200 мм, имитация бруса. Дневное крыло с кухней-гостиной 42 м² и порталом во двор, ночное крыло с 2 спальнями. Прихожая-гардероб, санузел, котельная. Кровля 25° с ендовой.",
                    shape: .lShape, foundation: .slab) { p in
            let b = PresetBuilder(p: p)
            b.setup(.lShape, L: 13, W: 12, a: 6, b: 6, wall: .frame200, roof: .gable, covering: .compositeTile, angle: 25, overhang: 0.4, foundation: .slab)
            b.wall(3, 0, 3, 6)
            b.wall(0, 3.5, 3, 3.5)
            b.wall(0, 6, 3, 6)
            b.wall(6, 0, 6, 6)
            b.wall(0, 7.2, 6, 7.2)
            b.wall(3.2, 7.2, 3.2, 12)
            b.open(.glassDoor, 4.5, 0)
            b.techWindow(1.5, 0)
            b.open(.panoramic, 9.5, 0, w: 2.5)
            b.open(.panoramic, 13, 3, w: 2.4)
            b.open(.glassDoor, 11.3, 6, w: 2.8)
            b.open(.panoramic, 8.8, 6, w: 1.4)
            b.open(.panoramic, 6, 9.6, w: 2.0)
            b.open(.window, 1.6, 12, w: 1.5)
            b.open(.window, 0, 9.6, w: 1.5)
            b.bathWindow(0, 4.75)
            b.open(.door, 3, 1.5)
            b.open(.door, 3, 4.5)
            b.open(.glassDoor, 6, 3, w: 1.4)
            b.open(.door, 1.6, 7.2)
            b.open(.door, 4.6, 7.2)
        },
        HousePreset(id: "l147", name: "Г-образный с вальмовой кровлей",
                    summary: "Тёплый каркас 250 мм с фиброцементным фасадом: кухня-гостиная 56 м² с панорамным остеклением на террасу, 2 спальни в ночном крыле, санузел, прачечная, котельная, коридор-галерея.",
                    shape: .lShape, foundation: .slab) { p in
            let b = PresetBuilder(p: p)
            b.setup(.lShape, L: 15, W: 13, a: 7, b: 7, wall: .frame250, roof: .hip, covering: .seam, overhang: 0.5, foundation: .slab, facade: .fiberCement)
            b.wall(3, 0, 3, 7)
            b.wall(0, 3.5, 3, 3.5)
            b.wall(4.4, 3.5, 7, 3.5)
            b.wall(4.4, 3.5, 4.4, 7)
            b.wall(7, 0, 7, 7)
            b.wall(0, 7, 3, 7)
            b.wall(4.4, 7, 7, 7)
            b.wall(0, 8.3, 7, 8.3)
            b.wall(3.5, 8.3, 3.5, 13)
            b.open(.glassDoor, 5, 0)
            b.techWindow(1.5, 0)
            b.open(.panoramic, 11, 0, w: 3.0)
            b.open(.panoramic, 15, 3.5, w: 2.4)
            b.open(.glassDoor, 11, 7, w: 3.0)
            b.open(.panoramic, 8.6, 7, w: 1.6)
            b.open(.panoramic, 13.6, 7, w: 1.6)
            b.open(.panoramic, 7, 10.65, w: 2.0)
            b.open(.window, 1.75, 13, w: 1.5)
            b.open(.window, 5.25, 13, w: 1.5)
            b.open(.window, 0, 10.65, w: 1.5)
            b.bathWindow(0, 5.25)
            b.open(.door, 3, 1.75)
            b.open(.door, 3, 5.25)
            b.open(.door, 4.4, 5.25)
            b.open(.glassDoor, 7, 1.75, w: 1.2)
            b.open(.door, 1.75, 8.3)
            b.open(.door, 5.25, 8.3)
            // внутренняя комната без наружных стен — гардеробная/кладовая, ей окно не нужно
            b.room(.storage, 5.7, 5.25)
        },

        HousePreset(id: "lfam", name: "Г-образный семейный с сауной",
                    summary: "Каркас 200 мм, имитация бруса, кровля 25° с ендовой. Мастер-спальня с гардеробной и своей ванной с туалетом, 2 детские по 14 м², кухня-гостиная с порталом во двор и проходом к спальням, прихожая с гардеробной, техпомещение (котёл, щит), сауна с душевой и туалетом — она же гостевой санузел.",
                    shape: .lShape, foundation: .slab) { p in
            let b = PresetBuilder(p: p)
            b.setup(.lShape, L: 13.75, W: 13.75, a: 8.75, b: 6.25, wall: .frame200, roof: .gable, covering: .compositeTile, angle: 25, overhang: 0.4, foundation: .slab)
            // хозблок вдоль западной стены: техпомещение → душевая → сауна
            b.wall(2.5, 0, 2.5, 7.5)
            b.wall(0, 2.5, 2.5, 2.5)
            b.wall(0, 5, 2.5, 5)
            b.wall(0, 7.5, 2.5, 7.5)
            // прихожая и её гардеробная
            b.wall(4.75, 0, 4.75, 2.5)
            b.wall(4.75, 2.5, 6.25, 2.5)
            b.wall(6.25, 0, 6.25, 3.75)
            // ночная зона: проход из гостиной вдоль несущей стены, детские по обе стороны
            b.wall(2.5, 3.75, 10, 3.75, .frame150, bearing: true)
            b.wall(6.25, 5, 10, 5)
            b.wall(6.25, 5, 6.25, 8.75)
            // мастер-блок: спальня, гардеробная, ванная
            b.wall(10, 0, 10, 8.75, .frame150, bearing: true)
            b.wall(10, 3.5, 13.75, 3.5)
            b.wall(11.75, 0, 11.75, 3.5)
            // фасад
            b.techWindow(1.25, 0)
            b.open(.glassDoor, 3.75, 0)
            b.open(.window, 8.1, 0, w: 1.5)
            b.bathWindow(12.75, 0)
            b.bathWindow(0, 3.75)
            b.open(.window, 0, 10.6, w: 1.5)
            b.open(.panoramic, 3.1, 13.75, w: 3.0)
            b.open(.window, 13.75, 6.1, w: 1.5)
            // двор
            b.open(.glassDoor, 6.25, 11.25, w: 2.4)
            b.open(.window, 8.1, 8.75, w: 1.5)
            b.open(.panoramic, 11.9, 8.75, w: 1.8)
            // двери
            b.open(.door, 2.5, 1.25)
            b.open(.door, 5.5, 2.5)
            b.open(.glassDoor, 3.75, 3.75)
            b.open(.door, 2.5, 4.4)
            b.open(.door, 1.25, 5, w: 0.7)
            b.open(.door, 7.0, 3.75)
            b.open(.door, 7.0, 5)
            b.open(.door, 10, 4.4)
            b.open(.door, 10.9, 3.5)
            b.open(.door, 12.75, 3.5)
            b.room(.boiler, 1.25, 1.25)
            b.room(.showerRoom, 1.25, 3.75)
            b.room(.sauna, 1.25, 6.25)
            b.room(.hall, 3.5, 2.0)
            b.room(.wardrobe, 5.5, 1.25)
            b.room(.kitchenLiving, 3.1, 10.6)
            b.room(.bedroom, 8.1, 1.9)
            b.room(.bedroom, 8.1, 6.9)
            b.room(.master, 11.9, 6.1)
            b.room(.wardrobe, 10.9, 1.75)
            b.room(.bath, 12.75, 1.75)
        },

        // ───────── П-образные (плита, скатная кровля) ─────────
        HousePreset(id: "u129", name: "П-образный с вальмовой кровлей",
                    summary: "Каркас 200 мм, сайдинг, дом вокруг патио: кухня-гостиная в левом крыле с порталом во двор, кабинет, 2 спальни в правом крыле за галереей с окнами в пол.",
                    shape: .uShape, foundation: .slab) { p in
            uLayout(p, L: 16, W: 10.5, d: 4.8, t: 4.4, wall: .frame200, roof: .hip, covering: .seam, facade: .siding)
        },
        HousePreset(id: "u150", name: "П-образный с двускатной кровлей",
                    summary: "Каркас 200 мм с имитацией бруса, патио во двор: кухня-гостиная 41 м² с порталом 3 м, холл с выходом во двор, кабинет, галерея и 2 спальни, санузел, кладовая, гостевой с/у. Кровля 25°.",
                    shape: .uShape, foundation: .slab) { p in
            uLayout(p, L: 17, W: 11.5, d: 5, t: 4.8, wall: .frame200, roof: .gable, covering: .compositeTile, angle: 25, facade: .imitationTimber)
        },

        HousePreset(id: "ufam", name: "П-образный семейный с сауной",
                    summary: "Каркас 200 мм, фиброцементный фасад, вальмовая кровля, дом вокруг патио. Ночное крыло за галереей с окнами в пол: мастер-спальня с гардеробной и своей ванной с туалетом, 2 детские. Дневное крыло — кухня-гостиная с порталом во двор. По фронту — прихожая с гардеробной, техпомещение, сауна с душевой и туалетом, галерея с окнами в пол на патио.",
                    shape: .uShape, foundation: .slab) { p in
            let b = PresetBuilder(p: p)
            b.setup(.uShape, L: 17.5, W: 13.75, a: 5, b: 5, wall: .frame200, roof: .hip, covering: .seam, overhang: 0.5, foundation: .slab, facade: .fiberCement)
            // фронт: детская 1 | сауна, душевая | гардеробная, прихожая | техпомещение; за ними — галерея вдоль патио
            b.wall(0, 3.75, 12.5, 3.75)
            b.wall(5, 0, 5, 3.75)
            b.wall(8, 0, 8, 3.75)
            b.wall(5, 1.75, 8, 1.75)
            b.wall(10, 0, 10, 2)
            b.wall(8, 2, 10, 2)
            b.wall(12.5, 0, 12.5, 5)
            b.wall(12.5, 2.5, 15, 2.5)
            b.wall(15, 0, 15, 2.5)
            // ночное крыло: детская 2 и мастер-блок, галерея вдоль патио ведёт в мастер-спальню
            b.wall(3.75, 3.75, 3.75, 10)
            b.wall(0, 7.5, 3.75, 7.5)
            b.wall(2.25, 7.5, 2.25, 10)
            b.wall(0, 10, 5, 10)
            // фасад
            b.open(.window, 2.5, 0, w: 1.5)
            b.open(.glassDoor, 11.25, 0)
            b.techWindow(13.75, 0)
            b.open(.window, 16.25, 0, w: 1.2)
            b.open(.window, 0, 5.6, w: 1.5)
            b.bathWindow(0, 8.75)
            b.open(.window, 0, 11.9, w: 1.5)
            b.open(.panoramic, 2.5, 13.75, w: 1.8)
            b.open(.panoramic, 15, 13.75, w: 3.0)
            b.open(.window, 17.5, 5, w: 1.5)
            b.open(.window, 17.5, 10.6, w: 1.5)
            // патио
            b.open(.panoramic, 5, 6.25, w: 1.6)
            b.open(.panoramic, 5, 8.75, w: 1.6)
            b.open(.panoramic, 5, 11.9, w: 1.6)
            b.open(.panoramic, 7.0, 5, w: 2.0)
            b.open(.panoramic, 10.5, 5, w: 2.0)
            b.open(.glassDoor, 12.5, 9.4, w: 2.4)
            // двери
            b.open(.door, 4.4, 3.75)
            b.open(.door, 3.75, 5.6)
            b.open(.door, 4.4, 10)
            b.open(.door, 1.1, 10)
            b.open(.door, 3.0, 10)
            b.open(.door, 7.4, 3.75)
            b.open(.door, 7.45, 1.75, w: 0.7)
            b.open(.door, 8.6, 2)
            b.open(.glassDoor, 10.5, 3.75)
            b.open(.door, 12.5, 1.25)
            b.open(.glassDoor, 12.5, 4.4)
            b.room(.bedroom, 2.5, 1.9)
            b.room(.bedroom, 1.9, 5.6)
            b.room(.corridor, 8.75, 4.4)
            b.room(.wardrobe, 3.0, 8.75)
            b.room(.bath, 1.1, 8.75)
            b.room(.master, 2.5, 11.9)
            b.room(.sauna, 6.5, 0.9)
            b.room(.showerRoom, 6.5, 2.75)
            b.room(.wardrobe, 9.0, 1.0)
            b.room(.hall, 11.25, 2.5)
            b.room(.boiler, 13.75, 1.25)
            b.room(.kitchenLiving, 15, 8)
        },

        // ───────── С двором (атриум) ─────────
        HousePreset(id: "atrium153", name: "Дом с атриумом",
                    summary: "СИП-панели, 13.75×13.75 м с остеклённым атриумом 3.75×3.75 и кольцевым коридором: прихожая, кухня-гостиная 50 м², 2 спальни, санузел, с/у. Плоская кровля по деревянным балкам.",
                    shape: .ring, foundation: .strip) { p in
            let b = PresetBuilder(p: p)
            b.setup(.ring, L: 13, W: 13, il: 4, iw: 4, wall: .sip, roof: .flat, foundation: .strip, facade: .plaster)
            b.wall(3.2, 0, 3.2, 3.2)
            b.wall(9.8, 0, 9.8, 3.2)
            b.wall(0, 3.2, 3.2, 3.2)
            b.wall(9.8, 3.2, 13, 3.2)
            b.wall(3.2, 3.2, 3.2, 9.8)
            b.wall(3.2, 9.8, 9.8, 9.8)
            b.wall(9.8, 3.2, 9.8, 13)
            b.wall(9.8, 6.5, 13, 6.5)
            b.bathWindow(1.6, 0)
            b.open(.glassDoor, 6.5, 0, w: 1.2)
            b.bathWindow(11.4, 0)
            b.open(.window, 13, 4.85, w: 1.5)
            b.open(.window, 13, 8.2, w: 1.5)
            b.open(.panoramic, 13, 11.4, w: 1.8)
            b.open(.window, 11.4, 13, w: 1.5)
            b.open(.panoramic, 6.5, 13, w: 3.0)
            b.open(.window, 1.6, 13, w: 1.5)
            b.open(.window, 0, 6.5, w: 1.5)
            b.open(.panoramic, 0, 10.2, w: 1.8)
            b.open(.glassDoor, 6.5, 4.5, w: 1.8)
            b.open(.panoramic, 8.5, 6.5, w: 2.4)
            b.open(.panoramic, 6.5, 8.5, w: 2.4)
            b.open(.panoramic, 4.5, 6.5, w: 2.4)
            b.open(.door, 3.2, 1.6)
            b.open(.door, 9.8, 1.6)
            b.open(.glassDoor, 3.2, 6.5, w: 1.4)
            b.open(.glassDoor, 6.5, 9.8, w: 1.6)
            b.open(.door, 9.8, 4.85)
            b.open(.door, 9.8, 8.2)
        },
    ]

    /// Типовая П-образная планировка: левое крыло — кухня-гостиная, центр — холл и кабинет,
    /// правое крыло — галерея-коридор вдоль двора и комнаты (санузел + 2 спальни)
    static func uLayout(_ p: Project, L: Double, W: Double, d: Double, t: Double, wall: WallMaterial,
                        roof: RoofType, covering: RoofCovering, angle: Double? = nil, facade: FacadeFinish) {
        let b = PresetBuilder(p: p)
        b.setup(.uShape, L: L, W: W, a: d, b: t, wall: wall, roof: roof, covering: covering, angle: angle, overhang: 0.4, foundation: .slab, facade: facade)
        let c1 = L - t, rx = c1 + 1.3, ym = (3.2 + W) / 2
        b.wall(0, 3, t, 3)
        b.wall(t / 2, 0, t / 2, 3)
        b.wall(t, 0, t, d)
        b.wall(t + 3, 0, t + 3, 3.2)
        b.wall(t + 3, 3.2, c1, 3.2)
        b.wall(c1, 0, c1, 3.2)
        b.wall(rx, 0, rx, W)
        b.wall(rx, 3.2, L, 3.2)
        b.wall(rx, ym, L, ym)
        b.room(.boiler, t / 4, 1.5)
        // фасад
        b.bathWindow(t * 0.75, 0)
        b.open(.glassDoor, t + 1.5, 0, w: 1.2)
        b.open(.window, (t + 3 + c1) / 2, 0, w: 1.5)
        b.bathWindow((rx + L) / 2, 0)
        b.open(.window, L, (3.2 + ym) / 2, w: 1.5)
        b.open(.panoramic, L, (ym + W) / 2, w: 1.8)
        b.open(.window, (rx + L) / 2, W, w: 1.2)
        // двор
        b.open(.panoramic, c1, d + (W - d) * 0.3, w: 2.0)
        b.open(.panoramic, c1, d + (W - d) * 0.72, w: 2.0)
        b.open(.panoramic, (t + 3 + c1) / 2, d, w: 2.0)
        b.open(.glassDoor, t + 1.5, d, w: 1.2)
        b.open(.glassDoor, t, d + (W - d) * 0.4, w: min(3.0, (W - d) * 0.45))
        b.open(.panoramic, t, d + (W - d) * 0.82, w: 1.6)
        b.open(.panoramic, t / 2, W, w: min(3.0, t - 1.0))
        b.open(.window, 0, 5, w: 1.5, h: 1.2, sill: 0.9)
        b.open(.window, 0, (5 + W) / 2 + 1, w: 1.5)
        // двери
        b.open(.door, t / 4, 3)
        b.open(.door, t, 1.5)
        b.open(.glassDoor, t, 4.1, w: 1.2)
        b.open(.door, (t + 3 + c1) / 2, 3.2)
        b.open(.door, rx, 1.6)
        b.open(.door, rx, 3.2 + (ym - 3.2) * 0.3)
        b.open(.door, rx, ym + 0.8)
    }
}
