//
//  UIColor.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/31/23.
//
import Foundation
import Swift
import UIKit

extension UIColor {

	private func makeColor(componentDelta: CGFloat) -> UIColor {
		var red: CGFloat = 0
		var blue: CGFloat = 0
		var green: CGFloat = 0
		var alpha: CGFloat = 0

		getRed(&red, green: &green,	blue: &blue, alpha: &alpha)

		return UIColor(
			red: add(componentDelta, toComponent: red),
			green: add(componentDelta, toComponent: green),
			blue: add(componentDelta, toComponent: blue),
			alpha: alpha
		)
	}

	func lighter(componentDelta: CGFloat = 0.1) -> UIColor {
		return makeColor(componentDelta: componentDelta)
	}

	func darker(componentDelta: CGFloat = 0.1) -> UIColor {
		return makeColor(componentDelta: -1*componentDelta)
	}

	private func add(_ value: CGFloat, toComponent: CGFloat) -> CGFloat {
		return max(0, min(1, toComponent + value))
	}

}
