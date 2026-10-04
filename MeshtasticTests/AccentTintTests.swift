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

/// The app carries two accents on purpose: `accentColor` to draw text and glyphs on a surface, and
/// `accentFill` to fill a shape under white text. They agree in light mode and must not in dark.
@Suite("Accent tint")
struct AccentTintTests {

	#if canImport(UIKit)
	/// The text accent by asset name rather than through `Color.accentColor`. The brand extension
	/// shadows SwiftUI's `accentColor`, which resolves inside the app but is ambiguous from here,
	/// where both declarations are visible. `accentFill` has no such clash and is read directly.
	private static let textAccentAsset = "AccentColor"

	private func resolved(_ color: Color, dark: Bool) -> UIColor {
		UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
	}

	private func resolved(asset: String, dark: Bool) -> UIColor? {
		UIColor(named: asset)?.resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
	}

	private func luminance(_ color: UIColor) -> CGFloat {
		var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
		color.getRed(&r, green: &g, blue: &b, alpha: &a)
		func lin(_ c: CGFloat) -> CGFloat { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
		return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
	}

	@Test("the fill accent stays dark in both appearances")
	func fillAccentDoesNotLighten() {
		// Reads Color.accentFill itself. Message bubbles and prominent buttons paint white text on
		// it, so it has to stay dark in dark mode; white on the light blue is about 1.8:1.
		let light = luminance(resolved(.accentFill, dark: false))
		let dark = luminance(resolved(.accentFill, dark: true))
		#expect(abs(light - dark) < 0.01)
		#expect(dark < 0.2)
	}

	@Test("the text accent lightens in dark so tinted labels stay readable")
	func textAccentLightensInDark() {
		// The app-wide tint. Cobalt on a dark sheet measures about 1.8:1, which made every plain
		// button, menu row and map control hard to read in dark mode.
		guard let light = resolved(asset: Self.textAccentAsset, dark: false),
			  let dark = resolved(asset: Self.textAccentAsset, dark: true) else {
			Issue.record("\(Self.textAccentAsset) missing"); return
		}
		#expect(luminance(dark) > luminance(light))
		#expect(luminance(dark) > 0.4)
	}

	@Test("the two accents agree in light and diverge in dark")
	func accentsSplitOnlyInDark() {
		// Catches either token being pointed at the other: the dark values would collapse together.
		guard let textLight = resolved(asset: Self.textAccentAsset, dark: false),
			  let textDark = resolved(asset: Self.textAccentAsset, dark: true) else {
			Issue.record("\(Self.textAccentAsset) missing"); return
		}
		#expect(abs(luminance(textLight) - luminance(resolved(.accentFill, dark: false))) < 0.01)
		#expect(luminance(textDark) > luminance(resolved(.accentFill, dark: true)) + 0.2)
	}
	#endif
}
