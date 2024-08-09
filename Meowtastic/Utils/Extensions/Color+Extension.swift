import Foundation
import SwiftUI
import UIKit

extension Color {
	static func listBackground(for scheme: ColorScheme) -> Color {
		if scheme == .dark {
			return Color(
				red: 28 / 256,
				green: 28 / 256,
				blue: 30 / 256
			)
		}
		else {
			return .white
		}
	}

	///  Returns a boolean for a SwiftUI Color to determine what color of text to use
	/// - Returns: true if the color is light
	func isLight() -> Bool {
		guard let components = cgColor?.components, components.count > 2 else {
			return false
		}

		let brightness = ((components[0] * 299) + (components[1] * 587) + (components[2] * 114)) / 1000

		return brightness > 0.5
	}
}
