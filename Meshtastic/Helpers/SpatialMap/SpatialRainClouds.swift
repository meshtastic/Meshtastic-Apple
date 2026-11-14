//
//  SpatialRainClouds.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/13/26.
//
import CoreGraphics
import CoreImage.CIFilterBuiltins
import Foundation

/// The radar drawn as cloud: a few sheets of the same rain stacked a little apart, the upper ones
/// blurred so the edges look like vapor rather than a cut-out, and on the 3D map a soft shadow of
/// it on the ground. The radar's colors are kept, so heavy rain still reads as heavy.
enum SpatialRainClouds {
	/// One sheet: how far above the lowest it floats, in model units on the 3D map, how much of
	/// the image's longest edge it is blurred by, and how see-through it is.
	struct Layer: Equatable, Sendable {
		let rise: Float
		let blur: Double
		let opacity: Float
	}

	/// The sharp rain at the bottom and two softer sheets over it. Where the rain is solid the
	/// three come to about the 2D map's strength.
	static let layers: [Layer] = [
		Layer(rise: 0, blur: 0, opacity: 0.35),
		Layer(rise: 0.004, blur: 0.006, opacity: 0.25),
		Layer(rise: 0.008, blur: 0.014, opacity: 0.2)
	]
	/// The shadow's strength under solid rain, and its blur.
	static let shadowOpacity: Float = 0.2
	static let shadowBlur = 0.01

	/// How solid the stacked sheets are where the rain is solid.
	static var combinedOpacity: Float {
		1 - layers.reduce(1) { $0 * (1 - $1.opacity) }
	}

	/// The sheets' images, bottom first, and the shadow's.
	struct Images: @unchecked Sendable {
		let sheets: [CGImage]
		let shadow: CGImage
	}

	/// The sheets and the shadow for a radar image. Nil if Core Image can't draw them.
	static func images(for radar: CGImage) -> Images? {
		var sheets: [CGImage] = []
		for layer in layers {
			guard let sheet = layer.blur > 0 ? softened(radar, blur: layer.blur) : radar else { return nil }
			sheets.append(sheet)
		}
		guard let shadow = shadow(radar) else { return nil }
		return Images(sheets: sheets, shadow: shadow)
	}

	/// The image blurred by `blur` of its longest edge, at its own size, premultiplied RGBA.
	static func softened(_ image: CGImage, blur: Double) -> CGImage? {
		render(blurred(CIImage(cgImage: image), image: image, blur: blur), like: image)
	}

	/// The rain's shape in black, blurred: where the rain falls, darkened.
	static func shadow(_ image: CGImage) -> CGImage? {
		let black = CIFilter.colorMatrix()
		black.inputImage = CIImage(cgImage: image)
		black.rVector = CIVector(x: 0, y: 0, z: 0, w: 0)
		black.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
		black.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
		black.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
		guard let output = black.outputImage else { return nil }
		return render(blurred(output, image: image, blur: shadowBlur), like: image)
	}

	/// The image with each pixel's strength scaled by `factor` of its place, as fractions across
	/// and down the image (0, 0 at the top left). Used to fade far rain out the cinema windows.
	static func faded(_ image: CGImage, by factor: (_ u: Double, _ v: Double) -> Double) -> CGImage? {
		let width = image.width, height = image.height
		guard width > 0, height > 0,
			  let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
									  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
			  let data = context.data else { return nil }
		context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
		let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
		for row in 0..<height {
			let v = (Double(row) + 0.5) / Double(height)
			for column in 0..<width {
				let scale = min(max(factor((Double(column) + 0.5) / Double(width), v), 0), 1)
				let index = (row * width + column) * 4
				// Premultiplied, so every channel scales with the alpha.
				for channel in 0..<4 {
					pixels[index + channel] = UInt8((Double(pixels[index + channel]) * scale).rounded())
				}
			}
		}
		return context.makeImage()
	}

	private static let context = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])

	private static func blurred(_ input: CIImage, image: CGImage, blur: Double) -> CIImage {
		let filter = CIFilter.gaussianBlur()
		// Clamped first, so the box's edges don't blur in from transparent.
		filter.inputImage = input.clampedToExtent()
		filter.radius = Float(Double(max(image.width, image.height)) * blur)
		return (filter.outputImage ?? input).cropped(to: CGRect(x: 0, y: 0, width: image.width, height: image.height))
	}

	private static func render(_ output: CIImage, like image: CGImage) -> CGImage? {
		context.createCGImage(output, from: CGRect(x: 0, y: 0, width: image.width, height: image.height),
							  format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
	}
}
