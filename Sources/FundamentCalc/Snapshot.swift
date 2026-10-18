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
            for st in Stage3D.allCases {
                var o = SceneOptions(); o.stage = st
                scene3D("stage_\(st.rawValue).png", o, high: 0.6, k: 0.75)
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
