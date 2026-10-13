//
//  SpatialVolumeFitTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/12/26.
//
import Foundation
import Testing
@testable import Meshtastic

@Suite("Spatial map volume fit")
struct SpatialVolumeFitTests {
	@Test func theDiskFillsTheDefaultVolumeLessTheRim() {
		let size = SpatialVolumeFit.defaultSize
		let fit = SpatialVolumeFit(volumeWidth: Float(size.x), volumeDepth: Float(size.z), modelDiskRadius: 0.5)
		#expect(abs(fit.diskRadius - (0.55 - SpatialVolumeFit.rimMargin)) < 1e-5)
		#expect(abs(fit.scale * 0.5 - fit.diskRadius) < 1e-5)
	}

	@Test func theDiskFollowsAResize() {
		let small = SpatialVolumeFit(volumeWidth: 0.6, volumeDepth: 0.6, modelDiskRadius: 0.5)
		let large = SpatialVolumeFit(volumeWidth: 2.0, volumeDepth: 2.0, modelDiskRadius: 0.5)
		#expect(abs(small.diskRadius - (0.3 - SpatialVolumeFit.rimMargin)) < 1e-5)
		#expect(abs(large.diskRadius - (1.0 - SpatialVolumeFit.rimMargin)) < 1e-5)
		#expect(large.scale > small.scale)
	}

	@Test func theDiskAndRimStayOnTheBaseplateAtEveryAllowedSize() {
		let low = SpatialVolumeFit.minimumSize, high = SpatialVolumeFit.maximumSize
		for step in 0...20 {
			let t = Double(step) / 20
			let width = Float(low.x + (high.x - low.x) * t)
			let depth = Float(low.z + (high.z - low.z) * (1 - t))
			let fit = SpatialVolumeFit(volumeWidth: width, volumeDepth: depth, modelDiskRadius: 0.48)
			#expect(fit.diskRadius + SpatialVolumeFit.rimMargin <= min(width, depth) / 2 + 1e-5)
		}
	}

	@Test func aNarrowVolumeFitsItsShorterSide() {
		let fit = SpatialVolumeFit(volumeWidth: 1.6, volumeDepth: 0.8, modelDiskRadius: 0.5)
		#expect(abs(fit.diskRadius - (0.4 - SpatialVolumeFit.rimMargin)) < 1e-5)
	}

	@Test func badSizesKeepASmallDisk() {
		#expect(SpatialVolumeFit(volumeWidth: 0, volumeDepth: 0, modelDiskRadius: 0.5).diskRadius == SpatialVolumeFit.minimumDiskRadius)
		#expect(SpatialVolumeFit(volumeWidth: .nan, volumeDepth: 1, modelDiskRadius: 0.5).diskRadius == SpatialVolumeFit.minimumDiskRadius)
		#expect(SpatialVolumeFit(volumeWidth: 1, volumeDepth: 1, modelDiskRadius: 0).scale == 1)
	}

	@Test func theDefaultSizeIsWithinTheLimits() {
		let size = SpatialVolumeFit.defaultSize
		for axis in 0..<3 {
			#expect(size[axis] >= SpatialVolumeFit.minimumSize[axis] && size[axis] <= SpatialVolumeFit.maximumSize[axis])
		}
	}
}
