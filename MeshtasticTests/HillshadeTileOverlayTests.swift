//
//  HillshadeTileOverlayTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/31/26.
//
import Foundation
import Testing
@testable import Meshtastic

@Suite("Hillshade")
struct HillshadeTileOverlayTests {

	@Test("the median network agrees with sorting")
	func median() {
		var generator = SystemRandomNumberGenerator()
		for _ in 0..<5_000 {
			// Few distinct values, so ties are common.
			let values = (0..<9).map { _ in Float(Int.random(in: 0...6, using: &generator)) }
			let expected = values.sorted()[4]
			var window = values
			let actual = window.withUnsafeMutableBufferPointer { HillshadeTileOverlay.median9($0) }
			#expect(actual == expected, "\(values)")
		}
		for permutation in [[1, 2, 3, 4, 5, 6, 7, 8, 9], [9, 8, 7, 6, 5, 4, 3, 2, 1], [5, 1, 9, 2, 8, 3, 7, 4, 6]] {
			var window = permutation.map(Float.init)
			#expect(window.withUnsafeMutableBufferPointer { HillshadeTileOverlay.median9($0) } == 5)
		}
	}
}
