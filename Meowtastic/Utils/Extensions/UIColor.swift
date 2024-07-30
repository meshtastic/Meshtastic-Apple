import Foundation
import Swift
import UIKit

extension UIColor {
	static var random: UIColor {
		UIColor(
			red: .random(in: 0...1),
			green: .random(in: 0...1),
			blue: .random(in: 0...1),
			alpha: 1.0
		)
	}

	func lighter(componentDelta: CGFloat = 0.1) -> UIColor {
		makeColor(componentDelta: componentDelta)
	}

	func darker(componentDelta: CGFloat = 0.1) -> UIColor {
		makeColor(componentDelta: -1 * componentDelta)
	}

	private func add(_ value: CGFloat, toComponent: CGFloat) -> CGFloat {
		max(0, min(1, toComponent + value))
	}

	private func makeColor(componentDelta: CGFloat) -> UIColor {
		var red: CGFloat = 0
		var blue: CGFloat = 0
		var green: CGFloat = 0
		var alpha: CGFloat = 0

		getRed(&red, green: &green, blue: &blue, alpha: &alpha)

		return UIColor(
			red: add(componentDelta, toComponent: red),
			green: add(componentDelta, toComponent: green),
			blue: add(componentDelta, toComponent: blue),
			alpha: alpha
		)
	}
}
