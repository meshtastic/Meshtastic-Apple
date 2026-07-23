//
//  Color.swift
//  Meshtastic
//
//  Copyright Garth Vander Houwen 4/25/23.
//

import Foundation
import SwiftUI
import UIKit

extension Color {

	/// Initialize a Color from a hex string (e.g., "#FF0000" or "FF0000")
	init(hex: String) {
		let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
		var int: UInt64 = 0
		Scanner(string: hex).scanHexInt64(&int)

		let a, r, g, b: UInt64
		switch hex.count {
		case 3: // RGB (12-bit)
			(a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
		case 6: // RGB (24-bit)
			(a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
		case 8: // ARGB (32-bit)
			(a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
		default:
			(a, r, g, b) = (255, 0, 0, 0)
		}

		self.init(
			.sRGB,
			red: Double(r) / 255,
			green: Double(g) / 255,
			blue: Double(b) / 255,
			opacity: Double(a) / 255
		)
	}

	/// Initialize a Color from a CSS-style color string: `rgb(r,g,b)` / `rgba(r,g,b,a)` or a hex
	/// string. Some GeoJSON producers (e.g. the Meshtastic Site Planner's coverage export) put an
	/// `rgb(...)` value in the `color` property; `init(hex:)` alone can't parse those.
	init(css: String) {
		let value = css.trimmingCharacters(in: .whitespaces)
		if value.lowercased().hasPrefix("rgb") {
			let components = value
				.drop { $0 != "(" }.dropFirst()
				.prefix { $0 != ")" }
				.split(separator: ",")
				.map { $0.trimmingCharacters(in: .whitespaces) }
			if components.count >= 3,
			   let r = Double(components[0]), let g = Double(components[1]), let b = Double(components[2]) {
				let a = components.count >= 4 ? (Double(components[3]) ?? 1) : 1
				self.init(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a)
				return
			}
		}
		self.init(hex: value)
	}
	///  Returns the WCAG relative luminance of a SwiftUI Color (0 = black, 1 = white).
	/// - Returns: relative luminance per the WCAG 2.x formula
	func relativeLuminance() -> Double {
		guard let components = cgColor?.components, components.count > 2 else {return 0}
		return wcagRelativeLuminance(red: components[0], green: components[1], blue: components[2])
	}
	///  Returns a boolean for a SwiftUI Color to determine what color of text to use
	/// - Returns: true if the color is light enough that black text gives at least ~4.5:1 contrast
	func isLight() -> Bool {
		return relativeLuminance() > 0.179
	}
	public static let magenta = Color(red: 0.50, green: 0.00, blue: 0.00)
}

/// WCAG 2.x relative luminance: linearize each sRGB channel (gamma-correct), then weight by
/// 0.2126/0.7152/0.0722. A 0.179 luminance cutoff corresponds to ~4.5:1 contrast against white,
/// which is what actually predicts legibility, unlike a flat BT.601 luma threshold.
private func wcagRelativeLuminance(red: Double, green: Double, blue: Double) -> Double {
	func linearize(_ channel: Double) -> Double {
		channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
	}
	return 0.2126 * linearize(red) + 0.7152 * linearize(green) + 0.0722 * linearize(blue)
}

extension UIColor {
	///  Returns the WCAG relative luminance of a UIColor (0 = black, 1 = white).
	/// - Returns: relative luminance per the WCAG 2.x formula
	func relativeLuminance() -> Double {
		guard let components = cgColor.components, components.count > 2 else {return 0}
		return wcagRelativeLuminance(red: components[0], green: components[1], blue: components[2])
	}
	///  Returns a boolean indicating if a color is light
	/// - Returns: true if the color is light enough that black text gives at least ~4.5:1 contrast
	func isLight() -> Bool {
		return relativeLuminance() > 0.179
	}
	///  Returns a UInt32 from a UIColor
	/// - Returns: UInt32
	var hex: UInt32 {
		   var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
		   getRed(&red, green: &green, blue: &blue, alpha: &alpha)
		   var value: UInt32 = 0
		   value += UInt32(1.0 * 255) << 24
		   value += UInt32(red   * 255) << 16
		   value += UInt32(green * 255) << 8
		   value += UInt32(blue  * 255)
		   return value
	}
	///  Returns a UIColor from a UInt32 value
	/// - Parameter hex: UInt32 value  to convert to a color
	/// - Returns: UIColor
	convenience init(hex: UInt32) {
		let red = CGFloat((hex & 0xFF0000) >> 16)
		let green = CGFloat((hex & 0x00FF00) >> 8)
		let blue = CGFloat((hex & 0x0000FF))
		self.init(red: red/255.0, green: green/255.0, blue: blue/255.0, alpha: 1.0)
	}
}
