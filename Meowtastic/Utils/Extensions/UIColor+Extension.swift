import Foundation
import SwiftUI
import UIKit

extension UIColor {
	///  Returns a UInt32 from a UIColor
	/// - Returns: UInt32
	var hex: UInt32 {
		var red: CGFloat = 0
		var green: CGFloat = 0
		var blue: CGFloat = 0
		var alpha: CGFloat = 0

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

		self.init(
			red: red/255.0,
			green: green/255.0,
			blue: blue/255.0,
			alpha: 1.0
		)
	}

	///  Returns a boolean indicating if a color is light
	/// - Returns: true if the color is light
	func isLight() -> Bool {
		guard let components = cgColor.components, components.count > 2 else {
			return false
		}

		let brightness = ((components[0] * 299) + (components[1] * 587) + (components[2] * 114)) / 1000

		return brightness > 0.5
	}
}
