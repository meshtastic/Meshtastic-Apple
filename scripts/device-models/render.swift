// Copyright(c) Garth Vander Houwen 10/14/26.
//
// Renders a .usdz to PNG for review with studio lighting.
// usage: render <in.usdz> <out.png> [size] [three-quarter|front|side|back|back-three-quarter]
import AppKit
import SceneKit

let args = CommandLine.arguments
guard args.count >= 3 else {
	FileHandle.standardError.write("usage: render.swift <in.usdz> <out.png> [size]\n".data(using: .utf8)!)
	exit(2)
}
let size = args.count > 3 ? Int(args[3]) ?? 800 : 800
let scene = try SCNScene(url: URL(fileURLWithPath: args[1]))

let (lo, hi) = scene.rootNode.boundingBox
let center = SCNVector3((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (lo.z + hi.z) / 2)
let extent = max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z)

let camera = SCNCamera()
camera.usesOrthographicProjection = true
camera.orthographicScale = Double(extent) * 0.62
camera.zNear = 0.0001
camera.zFar = 100
let cameraNode = SCNNode()
cameraNode.camera = camera
let view = args.count > 4 ? args[4] : "three-quarter"
let dir: SCNVector3 = switch view {
case "front": SCNVector3(0, 0, 1)
case "side": SCNVector3(1, 0, 0)
// Not exactly (0, 0, -1): look(at:) can't turn the camera exactly halfway round and renders nothing.
case "back": SCNVector3(0.001, 0, -1)
case "back-three-quarter": SCNVector3(-0.55, 0.25, -1.0)
default: SCNVector3(0.55, 0.25, 1.0)
}
cameraNode.position = SCNVector3(center.x + dir.x * extent * 3, center.y + dir.y * extent * 3, center.z + dir.z * extent * 3)
cameraNode.look(at: center)
scene.rootNode.addChildNode(cameraNode)

let key = SCNNode()
key.light = SCNLight()
key.light!.type = .directional
key.light!.intensity = 900
// Lit from over the viewer's shoulder, so back views get the same light as front ones.
key.eulerAngles = SCNVector3(-0.7, view.hasPrefix("back") ? 0.5 + .pi : 0.5, 0)
scene.rootNode.addChildNode(key)
let fill = SCNNode()
fill.light = SCNLight()
fill.light!.type = .ambient
fill.light!.intensity = 450
scene.rootNode.addChildNode(fill)

let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
renderer.scene = scene
renderer.pointOfView = cameraNode
scene.background.contents = NSColor(white: 0.93, alpha: 1)
let image = renderer.snapshot(atTime: 0, with: CGSize(width: size, height: size), antialiasingMode: .multisampling4X)
guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: args[2]))
