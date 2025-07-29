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
	///  Returns a boolean for a SwiftUI Color to determine what color of text to use
	/// - Returns: true if the color is light
	func isLight() -> Bool {
		guard let components = cgColor?.components, components.count > 2 else {return false}
		let brightness = ((components[0] * 299) + (components[1] * 587) + (components[2] * 114)) / 1000
		return (brightness > 0.5)
	}
	public static let magenta = Color(red: 0.50, green: 0.00, blue: 0.00)
}

extension UIColor {
	///  Returns a boolean indicating if a color is light
	/// - Returns: true if the color is light
	func isLight() -> Bool {
		guard let components = cgColor.components, components.count > 2 else {return false}
		let brightness = ((components[0] * 299) + (components[1] * 587) + (components[2] * 114)) / 1000
		return (brightness > 0.5)
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
