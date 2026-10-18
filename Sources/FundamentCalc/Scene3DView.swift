import SwiftUI
import SceneKit

struct Scene3DView: NSViewRepresentable {
    let project: Project
    let results: CalcResults
    let options: SceneOptions
    let resetToken: Int

    final class Coordinator {
        let scene = SCNScene()
        let content = SCNNode()
        let camera = SCNNode()
        var key = ""
        var resetToken = -1
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SCNView {
        let c = context.coordinator
        let v = SCNView()
        v.scene = c.scene
        v.backgroundColor = NSColor(srgbRed: 0.83, green: 0.89, blue: 0.95, alpha: 1)
        v.antialiasingMode = .multisampling4X
        v.allowsCameraControl = true
        v.autoenablesDefaultLighting = false
        v.defaultCameraController.interactionMode = .orbitTurntable
        v.defaultCameraController.inertiaEnabled = true
        c.scene.rootNode.addChildNode(c.content)

        let cam = SCNCamera()
        cam.zNear = 0.05
        cam.zFar = 500
        cam.fieldOfView = 45
        c.camera.camera = cam
        c.scene.rootNode.addChildNode(c.camera)
        v.pointOfView = c.camera

        let amb = SCNNode()
        amb.light = SCNLight()
        amb.light!.type = .ambient
        amb.light!.intensity = 300
        c.scene.rootNode.addChildNode(amb)

        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light!.type = .directional
        sun.light!.intensity = 1150
        sun.light!.castsShadow = true
        sun.light!.shadowMode = .deferred
        sun.light!.shadowColor = NSColor(white: 0, alpha: 0.35)
        sun.eulerAngles = SCNVector3(-1.0, 0.7, 0)
        c.scene.rootNode.addChildNode(sun)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light!.type = .directional
        fill.light!.intensity = 300
        fill.eulerAngles = SCNVector3(-0.4, -2.4, 0)
        c.scene.rootNode.addChildNode(fill)
        return v
    }

    func updateNSView(_ v: SCNView, context: Context) {
        let c = context.coordinator
        let key = "\(results.id)-\(options.hashValue)"
        if key != c.key {
            c.key = key
            c.content.childNodes.forEach { $0.removeFromParentNode() }
            c.content.addChildNode(SceneBuilder.build(project, results, options))
        }
        if resetToken != c.resetToken {
            c.resetToken = resetToken
            let (lo, hi) = options.site ? SceneBuilder.plot(project) : Geo.bbox(project.rings)
            let center = (lo + hi) / 2
            let size = max(hi.x - lo.x, hi.y - lo.y)
            let dist = size * (options.site ? 0.7 : 0.95) + 5
            let target = SceneBuilder.v3(center, 1.5)
            c.camera.position = SceneBuilder.v3(center + V2(dist * 0.75, -dist * 0.9), dist * 0.85)
            c.camera.look(at: target)
            v.pointOfView = c.camera
            v.defaultCameraController.target = target
        }
    }
}
