//
//  AccentTintTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 9/8/26.
//

import Testing
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
@testable import Meshtastic

/// The app carries two accents on purpose: one to fill a shape under white text, one to draw text
/// on a surface. They agree in light mode and must not in dark.
@Suite("Accent tint")
struct AccentTintTests {

	#if canImport(UIKit)
	private func resolved(_ name: String, dark: Bool) -> UIColor? {
		guard let color = UIColor(named: name) else { return nil }
		return color.resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
	}

	private func luminance(_ color: UIColor) -> CGFloat {
		var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
		color.getRed(&r, green: &g, blue: &b, alpha: &a)
		func lin(_ c: CGFloat) -> CGFloat { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
		return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
	}

	@Test("both accent assets resolve")
	func assetsExist() {
		#expect(UIColor(named: "AccentColor") != nil)
		#expect(UIColor(named: "Colors/MeshtasticAccent") != nil)
	}

	@Test("the fill accent stays dark in both appearances")
	func fillAccentDoesNotLighten() {
		// Message bubbles and prominent buttons paint white text on this, so it has to stay dark
		// in dark mode. Lightening it is the tempting one-line fix that breaks them.
		guard let light = resolved("Colors/MeshtasticAccent", dark: false),
			  let dark = resolved("Colors/MeshtasticAccent", dark: true) else {
			Issue.record("Colors/MeshtasticAccent missing"); return
		}
		#expect(abs(luminance(light) - luminance(dark)) < 0.01)
		#expect(luminance(dark) < 0.2)
	}

	@Test("the on-surface accent lightens in dark so tinted labels stay readable")
	func tintAccentLightensInDark() {
		// What `Color.accentTint` reads. Cobalt on a dark sheet measures about 1.7:1, which is why
		// the save confirmation action was unreadable; the palette's Blue 300 is the fix.
		guard let light = resolved("AccentColor", dark: false),
			  let dark = resolved("AccentColor", dark: true) else {
			Issue.record("AccentColor missing"); return
		}
		#expect(luminance(dark) > luminance(light))
		#expect(luminance(dark) > 0.4)
	}
	#endif
}
