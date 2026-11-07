//
//  LookoutSummitBarTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/7/26.
//
import Testing
@testable import Meshtastic

@Suite("Fire lookout summit bar")
struct LookoutSummitBarTests {

	@Test("mountain country keeps the 300 m bar")
	func mountains() {
		#expect(LookoutSummitBar.bar(for: Array(repeating: 600, count: 12)) == 300)
	}

	@Test("with only a few real mountains, hills join them")
	func fewMountains() {
		let prominences: [Float] = [900, 700, 400] + Array(repeating: 200, count: 9) + Array(repeating: 60, count: 20)
		#expect(LookoutSummitBar.bar(for: prominences) == 150)
	}

	@Test("a lowland mesh goes down to small hills, then to any summit")
	func lowland() {
		#expect(LookoutSummitBar.bar(for: Array(repeating: 80, count: 15)) == 50)
		#expect(LookoutSummitBar.bar(for: [20, 10]) == 0)
	}
}
