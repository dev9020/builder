import SwiftUI
import SceneKit
import Metal

/// Отладочный режим: `FundamentCalc --snapshot <папка>` — рендер 3D и экранов в PNG без окна.
enum Snapshot {
    @MainActor
    static func run(_ dir: String) {
        let p = Project()
        if let j = CommandLine.arguments.firstIndex(of: "--preset"), j + 1 < CommandLine.arguments.count,
           let pr = HousePreset.all.first(where: { $0.id == CommandLine.arguments[j + 1] }) { pr.apply(p) }
        if let j = CommandLine.arguments.firstIndex(of: "--foundation"), j + 1 < CommandLine.arguments.count,
           let k = FoundationKind(rawValue: CommandLine.arguments[j + 1]) { p.selectedFoundation = k }
        if let j = CommandLine.arguments.firstIndex(of: "--pile"), j + 1 < CommandLine.arguments.count,
           let t = PileType(rawValue: CommandLine.arguments[j + 1]) { p.pileType = t }
        func save(_ img: NSImage?, _ name: String) {
            guard let img, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { print("fail \(name)"); return }
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }
        func scene3D(_ name: String, _ o: SceneOptions, high: Double = 0.85, k: Double = 1, back: Bool = false) {
            let r = Calculator.run(p)
            let scene = SCNScene()
            scene.background.contents = NSColor(srgbRed: 0.83, green: 0.89, blue: 0.95, alpha: 1)
            scene.rootNode.addChildNode(SceneBuilder.build(p, r, o))
            let amb = SCNNode(); amb.light = SCNLight(); amb.light!.type = .ambient; amb.light!.intensity = 300
            let sun = SCNNode(); sun.light = SCNLight(); sun.light!.type = .directional; sun.light!.intensity = 1150
            sun.eulerAngles = SCNVector3(-1.0, 0.7, 0)
            scene.rootNode.addChildNode(amb); scene.rootNode.addChildNode(sun)
            let cam = SCNNode(); cam.camera = SCNCamera(); cam.camera!.zNear = 0.05; cam.camera!.zFar = 500
            let (lo, hi) = Geo.bbox(p.rings)
            let c = (lo + hi) / 2, d = (max(hi.x - lo.x, hi.y - lo.y) * 0.95 + 5) * k
            cam.position = SceneBuilder.v3(c + (back ? V2(-d * 0.6, d * 0.95) : V2(d * 0.75, -d * 0.9)), d * high)
            cam.look(at: SceneBuilder.v3(c, 1.5))
            scene.rootNode.addChildNode(cam)
            let rnd = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
            rnd.scene = scene
            rnd.pointOfView = cam
            save(rnd.snapshot(atTime: 0, with: CGSize(width: 1400, height: 900), antialiasingMode: .multisampling4X), name)
        }
        let model = AppModel()
        func view<V: View>(_ v: V, _ name: String, _ size: CGSize) {
            let host = v.environmentObject(model).environmentObject(model.project).environmentObject(EditorState())
                .frame(width: size.width, height: size.height).background(Color.white)
            let r = ImageRenderer(content: host)
            r.scale = 1
            save(r.nsImage, name)
        }
        if CommandLine.arguments.contains("--readme") {
            // картинки для README: 3D, экраны приложения, схемы
            func top<V: View>(_ v: V, _ name: String, _ size: CGSize) {
                view(v.frame(width: size.width, height: size.height, alignment: .top).clipped(), name, size)
            }
            func fig(_ k: FigKind, _ name: String, aspect: Double, width: Double = 1400) {
                let r = Calculator.run(model.project)
                let ctx = Drawings.Ctx(p: model.project, r: r, b: BuildPlan.make(model.project, r))
                let h = width * aspect
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(h), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                let cg = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
                cg.translateBy(x: 0, y: h); cg.scaleBy(x: 2, y: -2)
                Drawings.render(k, ctx, cg, CGRect(x: 0, y: 0, width: width / 2, height: h / 2))
                if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name)) }
            }
            HousePreset.all.first { $0.id == "scandi112" }!.apply(p)
            var o = SceneOptions(); o.site = true
            scene3D("hero.png", o, high: 0.55, k: 0.62)
            for (st, n) in [(Stage3D.walls, "stage_walls.png"), (.roof, "stage_roof.png"), (.rebar, "stage_foundation.png")] {
                var so = SceneOptions(); so.stage = st
                scene3D(n, so, high: 0.6, k: 0.6)
            }
            for id in ["barn84", "l147", "two144"] {
                HousePreset.all.first { $0.id == id }!.apply(p)
                var so = SceneOptions(); so.site = true
                scene3D("preset_\(id).png", so, high: 0.6, k: 0.7)
            }
            let w0 = BuildPlan.wallsExt0First(model.plan.frame) ?? 0
            fig(.wallSection, "fig_wall_section.png", aspect: 0.95, width: 1300)
            fig(.wallPlan, "fig_wall_plan.png", aspect: 0.4)
            fig(.sheetLayout(w0, 0), "fig_osb_layout.png", aspect: 0.42)
            fig(.sheetLayout(w0, 1), "fig_wool_layout.png", aspect: 0.42)
            fig(.fasteners, "fig_joints.png", aspect: 0.62)
            fig(.rigidity, "fig_rigidity.png", aspect: 0.42)
            fig(.sillSteps, "fig_sill_steps.png", aspect: 0.42)
            fig(.wallElevation(w0), "fig_wall_frame.png", aspect: 0.42)
            top(BuildView(plainStage: -3), "ui_materials.png", CGSize(width: 1000, height: 1250))
            top(BuildView(plainStage: 8), "ui_walls_stage.png", CGSize(width: 1000, height: 1500))
            top(BuildView(plainStage: 6), "ui_sill_stage.png", CGSize(width: 1000, height: 1500))
            top(BuildView(plainStage: -4), "ui_joints.png", CGSize(width: 1000, height: 900))
            top(BuildView(plainStage: -5), "ui_order.png", CGSize(width: 1000, height: 1300))
            let fl = model.plan.stages.firstIndex { $0.title.hasPrefix("Пол") } ?? 0
            fig(.floorSection, "fig_floor_wood.png", aspect: 0.55)
            HousePreset.all.first { $0.id == "l114" }!.apply(model.project)
            model.project.floorHeating = .water
            let r2 = Calculator.run(model.project)
            model.results = r2; model.plan = BuildPlan.make(model.project, r2)
            fig(.floorSection, "fig_floor_slab.png", aspect: 0.55)
            fig(.heatingLoop, "fig_heating_loop.png", aspect: 0.62)
            let fl2 = model.plan.stages.firstIndex { $0.title.hasPrefix("Пол") } ?? fl
            top(BuildView(plainStage: fl2), "ui_floor_stage.png", CGSize(width: 1000, height: 1500))
            HousePreset.all.first { $0.id == "scandi112" }!.apply(model.project)
            let r3 = Calculator.run(model.project)
            model.results = r3; model.plan = BuildPlan.make(model.project, r3)
            fig(.furniturePlan, "fig_furniture.png", aspect: 0.7)
            fig(.plumbingPlan, "fig_plumbing.png", aspect: 0.75)
            fig(.siteNetworks, "fig_site_networks.png", aspect: 0.75)
            fig(.sewerProfile, "fig_sewer_profile.png", aspect: 0.4)
            return
        }
        if CommandLine.arguments.contains("--weights-only") {
            let d = Project(); d.applyShapeDefault(.lShape)
            view(WeightsView(w: Weights.make(d, Calculator.run(d)), kind: d.selectedFoundation).padding(), "weights.png", CGSize(width: 980, height: 330))
            let rr = Calculator.run(d)
            view(DrainageBlock(d: Drainage.make(d, rr), kind: .strip, depth: rr.strip.depth, plinth: d.plinth).padding(), "drain.png", CGSize(width: 1000, height: 640))
            return
        }
        if CommandLine.arguments.contains("--ui") {
            for i in [6, 9, -1] { view(BuildView(plainStage: i), "ui_build\(i).png", CGSize(width: 1000, height: 3000)) }
            return
        }
        if CommandLine.arguments.contains("--stages") {
            let steps = Steps3D.make(p, Calculator.run(p), BuildPlan.make(p, Calculator.run(p)).frame)
            for (i, st) in steps.enumerated() {
                var o = SceneOptions(); o.stage = st.stage; o.sub = st.sub
                print(String(format: "stage_%02d", i), st.title, "—", st.note)
                let kk = CommandLine.arguments.firstIndex(of: "--k").flatMap { Double(CommandLine.arguments[$0 + 1]) } ?? 0.75
                if let only = CommandLine.arguments.firstIndex(of: "--only").flatMap({ Int(CommandLine.arguments[$0 + 1]) }), only != i { continue }
                scene3D(String(format: "stage_%02d.png", i), o, high: st.stage.isFoundation ? 0.8 * kk / 0.75 : 0.6, k: kk)
            }
            if CommandLine.arguments.contains("--preset") { return }
            p.roofType = .hip; p.shape = .lShape
            var o = SceneOptions(); o.stage = .roof
            scene3D("stage_hip_roof.png", o, high: 0.8, k: 0.8)
            o.stage = .battens
            scene3D("stage_hip_battens.png", o, high: 0.8, k: 0.8)
            return
        }
        if CommandLine.arguments.contains("--presets-only") {
            for pr in HousePreset.all {
                pr.apply(p)
                scene3D("pre_\(pr.id).png", SceneOptions(), high: 0.7, k: 0.8)
                scene3D("pre_\(pr.id)_back.png", SceneOptions(), high: 0.8, k: 0.8, back: true)
                let d = Project(); pr.apply(d)
                view(PlanThumb(project: d), "thumb_\(pr.id).png", CGSize(width: 420, height: 300))
            }
            return
        }
        scene3D("3d_strip.png", SceneOptions())
        scene3D("3d_close.png", SceneOptions(), high: 0.35, k: 0.55)
        p.covering = .softShingle; scene3D("3d_shingle.png", SceneOptions(), high: 0.6, k: 0.6)
        p.covering = .profiledSheet; p.facade = .siding; scene3D("3d_prof_frame.png", SceneOptions(), high: 0.6, k: 0.6)
        p.covering = .ceramicTile; p.facade = .imitationTimber; scene3D("3d_ceramic_timber.png", SceneOptions(), high: 0.6, k: 0.6)
        p.covering = .metalTile; p.facade = .fiberCement; scene3D("dbg_frame_metal.png", SceneOptions(roof: false), high: 0.6, k: 0.6)
        p.covering = .profiledSheet; p.facade = .facingBrick; scene3D("dbg_brick_prof.png", SceneOptions(roof: false), high: 0.6, k: 0.6)
        p.covering = .metalTile; p.facade = .plaster
        scene3D("3d_strip_rebar.png", SceneOptions(walls: false, roof: false, ground: false, rebar: true))
        p.selectedFoundation = .slab
        scene3D("3d_slab_rebar.png", SceneOptions(wallOpacity: 0.3, roof: false, rebar: true))
        p.selectedFoundation = .piles
        p.pileType = .boredEnlarged
        scene3D("3d_piles.png", SceneOptions(walls: false, roof: false, ground: false, rebar: true))
        p.selectedFoundation = .strip
        p.shape = .uShape; p.roofType = .hip
        scene3D("3d_u_hip.png", SceneOptions())
        scene3D("3d_u_hip_top.png", SceneOptions(), high: 1.6)
        p.roofType = .gable
        scene3D("3d_u_gable.png", SceneOptions(), high: 1.2)
        p.shape = .ring; p.roofType = .gable; p.floors = 2; p.facade = .facingBrick
        scene3D("3d_ring.png", SceneOptions())
        p.shape = .lShape; p.roofType = .shed
        scene3D("3d_l_shed.png", SceneOptions())
        view(PlanEditorView(), "plan.png", CGSize(width: 1100, height: 700))
        for k in FoundationKind.allCases {
            let pp = Project(); pp.selectedFoundation = k
            view(LayoutSchemeView(scheme: Works.plan(pp, Calculator.run(pp)).scheme, kind: k), "scheme_\(k.rawValue).png", CGSize(width: 640, height: 320))
        }
        let rr = Calculator.run(Project())
        if let e = rr.strip.ext { view(StripSectionView(sec: e, depth: rr.strip.depth), "sec_strip.png", CGSize(width: 320, height: 320)) }
        view(SlabSectionView(s: rr.slab), "sec_slab.png", CGSize(width: 360, height: 240))
        view(GrillageSectionView(s: rr.piles), "sec_pile.png", CGSize(width: 320, height: 340))
        let heavy = Project(); heavy.floors = 2; heavy.facade = .facingBrick; heavy.floorType = .woodScreed; heavy.soilPreset = 5
        let hr = Calculator.run(heavy)
        if let e = hr.strip.ext { view(StripSectionView(sec: e, depth: hr.strip.depth), "sec_strip_heavy.png", CGSize(width: 320, height: 320)) }
        print(Report.html(heavy, hr).replacingOccurrences(of: "<tr>", with: "\n").replacingOccurrences(of: "</td>", with: " | ").replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
        view(SidebarView(), "sidebar.png", CGSize(width: 380, height: 1400))
    }
}
