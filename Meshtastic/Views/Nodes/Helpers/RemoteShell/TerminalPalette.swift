//
//  TerminalPalette.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/8/26.
//

import UIKit

/// Maps terminal colors to colors that read on the current theme. The 16 standard colors have
/// a darker set for light backgrounds; any color, including 256 and truecolor ones, is pulled
/// toward the text color until it meets 4.5:1 contrast with what is behind it.
enum TerminalPalette {

	static let minimumContrast: CGFloat = 4.5

	private static let dark: [UInt32] = [
		0x2E3436, 0xEF2929, 0x8AE234, 0xFCE94F, 0x729FCF, 0xAD7FA8, 0x34E2E2, 0xD3D7CF,
		0x555753, 0xFF6B6B, 0xB5F57A, 0xFFF38A, 0x9EC3EF, 0xD6A8D1, 0x7CF4F4, 0xEEEEEC
	]

	private static let light: [UInt32] = [
		0x2E3436, 0xA40000, 0x2E6B05, 0x7A5C00, 0x204A87, 0x5C3566, 0x05676B, 0x6B6E68,
		0x555753, 0xCC0000, 0x3D7A0A, 0x8F6B00, 0x2A5DA8, 0x75507B, 0x07797E, 0x2E3436
	]

	static func color(_ color: TerminalColor, dark isDark: Bool) -> UIColor {
		switch color {
		case let .ansi(index):
			let table = isDark ? dark : light
			return UIColor(rgb: table[Int(index) % 16])
		case let .indexed(index):
			return indexedColor(index)
		case let .rgb(red, green, blue):
			return UIColor(red: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
		}
	}

	/// The xterm 256 color cube and gray ramp.
	private static func indexedColor(_ index: UInt8) -> UIColor {
		if index >= 232 {
			let level = CGFloat(8 + 10 * Int(index - 232)) / 255
			return UIColor(white: level, alpha: 1)
		}
		let cube = Int(index) - 16
		let steps = [0, 95, 135, 175, 215, 255].map { CGFloat($0) / 255 }
		return UIColor(red: steps[cube / 36], green: steps[(cube / 6) % 6], blue: steps[cube % 6], alpha: 1)
	}

	/// `foreground`, blended toward `text` until it reads on `background`. On a mid-gray
	/// background that `text` itself doesn't read on, it blends toward black or white instead,
	/// whichever reads better.
	static func legible(_ foreground: UIColor, on background: UIColor, text: UIColor) -> UIColor {
		var target = text
		if contrast(text, background) < minimumContrast {
			target = contrast(.black, background) >= contrast(.white, background) ? .black : .white
		}
		var color = foreground
		var step: CGFloat = 0
		while contrast(color, background) < minimumContrast, step < 1 {
			step += 0.1
			color = blend(foreground, target, step)
		}
		return color
	}

	/// Dim text: `foreground` faded toward `background` as far as it can go, up to 40%, while it
	/// still meets 4.5:1. Text already at the limit stays as it is (design#163 requirement 6).
	static func dimmed(_ foreground: UIColor, on background: UIColor) -> UIColor {
		for amount in stride(from: CGFloat(0.4), to: 0, by: -0.05) {
			let faded = blend(foreground, background, amount)
			if contrast(faded, background) >= minimumContrast {
				return faded
			}
		}
		return foreground
	}

	static func contrast(_ first: UIColor, _ second: UIColor) -> CGFloat {
		let lighter = max(luminance(first), luminance(second))
		let darker = min(luminance(first), luminance(second))
		return (lighter + 0.05) / (darker + 0.05)
	}

	static func luminance(_ color: UIColor) -> CGFloat {
		var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
		color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
		func linear(_ value: CGFloat) -> CGFloat {
			value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
		}
		return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
	}

	private static func blend(_ from: UIColor, _ to: UIColor, _ amount: CGFloat) -> UIColor {
		var fromRed: CGFloat = 0, fromGreen: CGFloat = 0, fromBlue: CGFloat = 0, fromAlpha: CGFloat = 0
		var toRed: CGFloat = 0, toGreen: CGFloat = 0, toBlue: CGFloat = 0, toAlpha: CGFloat = 0
		from.getRed(&fromRed, green: &fromGreen, blue: &fromBlue, alpha: &fromAlpha)
		to.getRed(&toRed, green: &toGreen, blue: &toBlue, alpha: &toAlpha)
		let amount = min(max(amount, 0), 1)
		return UIColor(
			red: fromRed + (toRed - fromRed) * amount,
			green: fromGreen + (toGreen - fromGreen) * amount,
			blue: fromBlue + (toBlue - fromBlue) * amount,
			alpha: 1
		)
	}
}

private extension UIColor {
	convenience init(rgb: UInt32) {
		self.init(
			red: CGFloat((rgb >> 16) & 0xFF) / 255,
			green: CGFloat((rgb >> 8) & 0xFF) / 255,
			blue: CGFloat(rgb & 0xFF) / 255,
			alpha: 1
		)
	}
}
