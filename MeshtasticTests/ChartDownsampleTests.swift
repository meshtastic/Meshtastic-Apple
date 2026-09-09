//
//  ChartDownsampleTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 8/30/26.
//

import Testing
@testable import Meshtastic

@Suite("Chart downsampling")
struct ChartDownsampleTests {

	@Test func underBudgetPassesThrough() {
		let points = Array(0..<500)
		#expect(downsampledForChart(points, budget: 600) == points)
	}

	@Test func exactBudgetPassesThrough() {
		let points = Array(0..<600)
		#expect(downsampledForChart(points, budget: 600) == points)
	}

	@Test func overBudgetIsBounded() {
		let points = Array(0..<5_000)
		let result = downsampledForChart(points, budget: 600)
		#expect(result.count == 600)
	}

	@Test func endpointsSurvive() {
		let points = Array(0..<4_321)
		let result = downsampledForChart(points, budget: 600)
		#expect(result.first == 0)
		#expect(result.last == 4_320)
	}

	@Test func orderAndDistinctnessPreserved() {
		let points = Array(0..<10_000)
		let result = downsampledForChart(points, budget: 600)
		#expect(result == result.sorted())
		#expect(Set(result).count == result.count)
	}

	@Test func degenerateBudgetPassesThrough() {
		let points = Array(0..<100)
		#expect(downsampledForChart(points, budget: 2) == points)
	}
}
