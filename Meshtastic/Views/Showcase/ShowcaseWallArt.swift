//
//  ShowcaseWallArt.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
#if os(visionOS)
import RealityKit
import UIKit

/// What hangs on the right wall: a poster of Chirpy, facing the Meshtastic mark on the left
/// wall, and nearer the seat a small plaque for Meshtastic Solutions.
extension ShowcaseRoom {
	/// The poster's and plaque's centers on the right wall, and their sizes in meters.
	static let posterCenter = SIMD3<Float>(ShowcaseRoomGeometry.width / 2, 1.55, -1.5)
	static let posterSize = SIMD2<Float>(1.0, 1.4)
	static let plaqueCenter = SIMD3<Float>(ShowcaseRoomGeometry.width / 2, 1.3, -0.55)
	static let plaqueSize = SIMD2<Float>(0.36, 0.2)

	func addWallArt() async {
		// Turns a board's face, +Z, to -X: out of the right wall into the room.
		let facingIn = simd_quatf(angle: -.pi / 2, axis: [0, 1, 0])
		if let image = Self.chirpyPoster(), let poster = await Self.board(image, size: Self.posterSize, depth: 0.02, edge: .white) {
			poster.name = "ChirpyPoster"
			poster.position = Self.posterCenter - [0.01, 0, 0]
			poster.orientation = facingIn
			root.addChild(poster)
		}
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

	/// Chirpy on white, so the green body doesn't vanish into the green wall.
	private static func chirpyPoster() -> CGImage? {
		guard let chirpy = UIImage(named: "Chirpy") else { return nil }
		let size = CGSize(width: CGFloat(posterSize.x) * pixelsPerMeter, height: CGFloat(posterSize.y) * pixelsPerMeter)
		return render(size) { bounds in
			UIColor.white.setFill()
			UIRectFill(bounds)
			let area = bounds.insetBy(dx: 90, dy: 90)
			let scale = min(area.width / chirpy.size.width, area.height / chirpy.size.height)
			let drawn = CGSize(width: chirpy.size.width * scale, height: chirpy.size.height * scale)
			chirpy.draw(in: CGRect(x: area.midX - drawn.width / 2, y: area.midY - drawn.height / 2, width: drawn.width, height: drawn.height))
		}
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
