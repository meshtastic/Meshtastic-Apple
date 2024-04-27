//
//  Color.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 4/25/23.
//

import Foundation
import SwiftUI
import UIKit

extension Color {
	///  Returns a boolean for a SwiftUI Color to determine what color of text to use
	/// - Returns: true if the color is light
	func isLight() -> Bool {
		guard let components = cgColor?.components, components.count > 2 else {return false}
		let brightness = ((components[0] * 299) + (components[1] * 587) + (components[2] * 114)) / 1000
		return (brightness > 0.5)
	}
	public static let magenta = Color(red: 0.50, green: 0.00, blue: 0.00)
//	public static var magenta: Color {
//		return Color(red: 0.50, green: 0.00, blue: 0.00)
//		//return Color(UIColor(red: 0.50, green: 0.00, blue: 0.00, alpha: 1.00))	//return Color(UIColor.magenta)
//	}
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
		/// print("\(red) - \(green) - \(blue)")
		self.init(red: red/255.0, green: green/255.0, blue: blue/255.0, alpha: 1.0)
	}
}
