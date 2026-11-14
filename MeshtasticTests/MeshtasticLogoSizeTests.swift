// MeshtasticLogoSizeTests.swift
// MeshtasticTests

import Testing
import SwiftUI
import UIKit
@testable import Meshtastic

/// The nav logo must keep one size whatever slot the bar offers it. On the open iPhone Duo
/// the bar offers a different slot after a rotation or a tab switch, and a logo that followed
/// the offer drew beside its glass (#2978).
@MainActor
@Suite("MeshtasticLogo size")
struct MeshtasticLogoSizeTests {

	/// Slots like the ones the bar hands out: a narrow circle, a regular bar item, a wide
	/// leading area and a short landscape bar.
	static let offeredSizes: [CGSize] = [
		CGSize(width: 20, height: 20),
		CGSize(width: 44, height: 44),
		CGSize(width: 200, height: 44),
		CGSize(width: 80, height: 32)
	]

	@Test("Keeps a fixed 28 pt size whatever slot it is offered", arguments: offeredSizes)
	func fixedSize(offered: CGSize) {
		guard #available(iOS 26.0, *) else { return }
		let host = UIHostingController(rootView: MeshtasticLogo())
		let measured = host.sizeThatFits(in: offered)
		#expect(measured.width == 28)
		#expect(measured.height == 28)
	}
}
