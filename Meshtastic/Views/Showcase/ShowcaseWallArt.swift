//
//  ShowcaseWallArt.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
#if os(visionOS)
import OSLog
import RealityKit
import UIKit

/// Along the right wall: a giant Chirpy on a pedestal, turned toward the seat, and nearer
/// the seat a small plaque for Meshtastic Solutions.
extension ShowcaseRoom {
	/// Where Chirpy's pedestal stands on the floor, and how tall he is from feet to antenna tip, in meters.
	static let chirpySpot = SIMD3<Float>(1.2, 0, -1.6)
	static let chirpyHeight: Float = 1.15
	/// The pedestal under him: wide enough for his gloves, deep enough for his feet.
	static let pedestalSize = SIMD3<Float>(0.75, 0.8, 0.4)
	/// The plaque's center on the right wall, and its size in meters.
	static let plaqueCenter = SIMD3<Float>(ShowcaseRoomGeometry.width / 2, 1.3, -0.55)
	static let plaqueSize = SIMD2<Float>(0.36, 0.2)

	func addWallArt() async {
		// Turns a board's face, +Z, to -X: out of the right wall into the room.
		let facingIn = simd_quatf(angle: -.pi / 2, axis: [0, 1, 0])
		await addChirpy()
		if let image = Self.solutionsPlaque(), let plaque = await Self.board(image, size: Self.plaqueSize, depth: 0.012, edge: Self.plaqueColor) {
			plaque.name = "SolutionsPlaque"
			plaque.position = Self.plaqueCenter - [0.006, 0, 0]
			plaque.orientation = facingIn
			root.addChild(plaque)
		}
	}

	/// Pixels per meter the boards' faces are drawn at.
	private static let pixelsPerMeter: CGFloat = 1000
	/// Dark charcoal, the app's primary text color.
	private static let plaqueColor = UIColor(red: 0.17, green: 0.18, blue: 0.24, alpha: 1)

	/// Chirpy's real-size model, bundled with the device models, scaled up to `chirpyHeight` and turned to
	/// look at the seat. He's the room's mascot, not a device, so he isn't on a table.
	private func addChirpy() async {
		let chirpy: Entity
		do {
			guard let url = Bundle.main.url(forResource: DeviceModelCatalog.chirpy, withExtension: "usdz") else { return }
			chirpy = try await Entity(contentsOf: url)
		} catch {
			Logger.services.error("📻 [Showcase] Chirpy failed to load: \(error.localizedDescription, privacy: .public)")
			return
		}
		let bounds = chirpy.visualBounds(relativeTo: nil)
		guard bounds.extents.y > 0 else { return }
		let scale = Self.chirpyHeight / bounds.extents.y
		// Feet on the pedestal, centered over it, whatever the model's own origin.
		chirpy.scale = SIMD3(repeating: scale)
		chirpy.position = SIMD3(-bounds.center.x, -bounds.min.y, -bounds.center.z) * scale + [0, Self.pedestalSize.y, 0]
		let pedestal = ModelEntity(
			mesh: .generateBox(size: Self.pedestalSize, cornerRadius: 0.01),
			materials: [SimpleMaterial(color: .white, roughness: 0.5, isMetallic: false)]
		)
		pedestal.name = "ChirpyPedestal"
		pedestal.position = [0, Self.pedestalSize.y / 2, 0]
		let stand = Entity()
		stand.name = "GiantChirpy"
		stand.addChild(pedestal)
		stand.addChild(chirpy)
		stand.position = Self.chirpySpot
		// The model faces +Z; turn him about Y toward the seat.
		let toSeat = ShowcaseRoomGeometry.seatedEye - Self.chirpySpot
		stand.orientation = simd_quatf(angle: atan2(toSeat.x, toSeat.z), axis: [0, 1, 0])
		root.addChild(stand)
	}

	/// "Brought to you by" over the Meshtastic Solutions mark and name, in white on charcoal.
	private static func solutionsPlaque() -> CGImage? {
		guard let mark = UIImage(named: "MeshtasticSolutionsMark")?.withTintColor(.white, renderingMode: .alwaysOriginal) else { return nil }
		// Drawn at four times the poster's density: the plaque is small and read up close.
		let density = pixelsPerMeter * 4
		let size = CGSize(width: CGFloat(plaqueSize.x) * density, height: CGFloat(plaqueSize.y) * density)
		let byLine = String(localized: "Brought to you by", comment: "Showcase: plaque on the wall naming who made the showcase, above the Meshtastic Solutions name")
		let name = "Meshtastic Solutions"
		return render(size) { bounds in
			plaqueColor.setFill()
			UIRectFill(bounds)
			UIColor.white.withAlphaComponent(0.35).setStroke()
			let border = UIBezierPath(roundedRect: bounds.insetBy(dx: 28, dy: 28), cornerRadius: 18)
			border.lineWidth = 4
			border.stroke()
			let small: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 64, weight: .medium), .foregroundColor: UIColor.white.withAlphaComponent(0.7)]
			let byLineSize = (byLine as NSString).size(withAttributes: small)
			(byLine as NSString).draw(at: CGPoint(x: bounds.midX - byLineSize.width / 2, y: 170), withAttributes: small)
			// As large as fits inside the border.
			var fontSize: CGFloat = 112
			var large: [NSAttributedString.Key: Any] = [:]
			var nameSize = CGSize.zero
			var markHeight: CGFloat = 0
			var markWidth: CGFloat = 0
			let gap: CGFloat = 32
			repeat {
				large = [.font: UIFont.systemFont(ofSize: fontSize, weight: .semibold), .foregroundColor: UIColor.white]
				nameSize = (name as NSString).size(withAttributes: large)
				markHeight = fontSize * 1.2
				markWidth = markHeight * mark.size.width / max(mark.size.height, 1)
				fontSize -= 4
			} while markWidth + gap + nameSize.width > bounds.width - 140 && fontSize > 48
			let left = bounds.midX - (markWidth + gap + nameSize.width) / 2
			let rowMid: CGFloat = 470
			mark.draw(in: CGRect(x: left, y: rowMid - markHeight / 2, width: markWidth, height: markHeight))
			(name as NSString).draw(at: CGPoint(x: left + markWidth + gap, y: rowMid - nameSize.height / 2), withAttributes: large)
		}
	}

	private static func render(_ size: CGSize, draw: (CGRect) -> Void) -> CGImage? {
		let format = UIGraphicsImageRendererFormat()
		format.scale = 1
		format.opaque = true
		return UIGraphicsImageRenderer(size: size, format: format).image { _ in
			draw(CGRect(origin: .zero, size: size))
		}.cgImage
	}

	/// A thin board `size` wide and high with `image` on its face, which looks down +Z. The room's
	/// light falls on it like paint.
	private static func board(_ image: CGImage, size: SIMD2<Float>, depth: Float, edge: UIColor) async -> Entity? {
		guard let texture = try? await TextureResource(image: image, options: .init(semantic: .color)) else { return nil }
		let board = ModelEntity(
			mesh: .generateBox(width: size.x, height: size.y, depth: depth, cornerRadius: min(depth / 2, 0.004)),
			materials: [SimpleMaterial(color: edge, roughness: 0.8, isMetallic: false)]
		)
		var material = PhysicallyBasedMaterial()
		material.baseColor = .init(texture: .init(texture))
		material.roughness = 0.85
		let face = ModelEntity(mesh: .generatePlane(width: size.x, height: size.y, cornerRadius: min(depth / 2, 0.004)), materials: [material])
		face.position = [0, 0, depth / 2 + 0.0005]
		board.addChild(face)
		return board
	}
}
#endif
