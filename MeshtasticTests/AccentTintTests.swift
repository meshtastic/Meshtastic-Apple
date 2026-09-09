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
	/// The fill accent by asset name rather than through `Color.accentColor`. The brand extension
	/// shadows SwiftUI's `accentColor`, which resolves inside the app but is ambiguous from here,
	/// where both declarations are visible. `accentTint` has no such clash and is read directly.
	private static let fillAccentAsset = "Colors/MeshtasticAccent"

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
		// Message bubbles and prominent buttons paint white text on this, so it has to stay dark in
		// dark mode. Lightening it is the tempting one-line fix that breaks them.
		guard let light = resolved(asset: Self.fillAccentAsset, dark: false),
			  let dark = resolved(asset: Self.fillAccentAsset, dark: true) else {
			Issue.record("\(Self.fillAccentAsset) missing"); return
		}
		#expect(abs(luminance(light) - luminance(dark)) < 0.01)
		#expect(luminance(dark) < 0.2)
	}

	@Test("the on-surface accent lightens in dark so tinted labels stay readable")
	func tintAccentLightensInDark() {
		// Reads Color.accentTint itself, so repointing it at another asset fails here. Cobalt on a
		// dark sheet measures about 1.7:1, which is why the save confirmation was unreadable.
		let light = luminance(resolved(.accentTint, dark: false))
		let dark = luminance(resolved(.accentTint, dark: true))
		#expect(dark > light)
		#expect(dark > 0.4)
	}

	@Test("the tint token agrees with the fill accent in light and diverges in dark")
	func accentsSplitOnlyInDark() {
		// The whole point of the split, and the assertion that catches `accentTint` being pointed
		// back at the fill accent: the dark values would collapse together.
		guard let fillLight = resolved(asset: Self.fillAccentAsset, dark: false),
			  let fillDark = resolved(asset: Self.fillAccentAsset, dark: true) else {
			Issue.record("\(Self.fillAccentAsset) missing"); return
		}
		#expect(abs(luminance(resolved(.accentTint, dark: false)) - luminance(fillLight)) < 0.01)
		#expect(luminance(resolved(.accentTint, dark: true)) > luminance(fillDark) + 0.2)
	}
	#endif
}
