//
//  CinemaModelStandLayoutTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/1/26.
//
import Testing
@testable import Meshtastic

@Suite("Cinema model stand layout")
struct CinemaModelStandLayoutTests {
	/// A handheld radio: 10 cm tall, 6 cm wide on its stand.
	private let handheld = CinemaModelStandLayout.Size(height: 0.1, halfWidth: 0.03)
	/// A 300 pt card, about 22 cm wide.
	private let cardWidth: Float = 0.22

	@Test("At real size the card hangs a hand's width out, its bottom at half the model's height")
	func realSize() {
		let offset = CinemaModelStandLayout.cardOffset(stand: handheld, zoom: 1, cardWidth: cardWidth, cardHeight: 0.2)
		#expect(abs(offset.x - 0.2) < 1e-6)
		#expect(abs(offset.y - (0.05 + 0.1)) < 1e-6)
		#expect(offset.z == 0)
	}

	@Test("A flat tracker gets the same room beside it as a small radio")
	func flatModel() {
		let tracker = CinemaModelStandLayout.Size(height: 0.012, halfWidth: 0.025)
		let offset = CinemaModelStandLayout.cardOffset(stand: tracker, zoom: 1, cardWidth: cardWidth, cardHeight: 0.2)
		#expect(abs(offset.y - (0.04 + 0.1)) < 1e-6)
	}

	@Test("Made larger, the model never runs into the card, and the card's bottom stays within reach")
	func zoomedModelClearsCard() {
		for zoom: Float in [1, 2, 3, 4, 5] {
			let offset = CinemaModelStandLayout.cardOffset(stand: handheld, zoom: zoom, cardWidth: cardWidth, cardHeight: 0.45)
			let cardLeftEdge = offset.x - cardWidth / 2
			#expect(cardLeftEdge >= handheld.halfWidth * zoom + 0.04 - 1e-6)
			let bottom = offset.y - 0.45 / 2
			#expect(bottom <= 0.1 + 1e-6)
			#expect(bottom >= 0.05 - 1e-6)
		}
	}

	@Test("The zoom is held between real size and five times it")
	func zoomClamp() {
		#expect(CinemaModelStandLayout.clampZoom(0.2) == 1)
		#expect(CinemaModelStandLayout.clampZoom(3) == 3)
		#expect(CinemaModelStandLayout.clampZoom(12) == 5)
		#expect(CinemaModelStandLayout.clampZoom(.nan) == 1)
	}
}
