//
//  CinemaEnvironmentTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/9/26.
//
#if os(visionOS)
import CinemaContent
import Foundation
import Testing

@testable import Meshtastic

@Suite("Cinema environments")
struct CinemaEnvironmentTests {

	@Test("every environment ships its image and anchors, with a screen")
	func everyEnvironmentShips() {
		for environment in CinemaEnvironment.allCases {
			let stones = environment.hasStone ? CastleStone.allCases : [.gray]
			for stone in stones {
				#expect(cinemaEnvironmentImageURL(named: environment.imageName(stone: stone)) != nil, "\(environment) has no image in \(stone)")
			}
			#expect(CinemaAnchors.load(for: environment)?.board(.screen) != nil, "\(environment) has no screen")
		}
	}

	@Test("every cutout ships the sky painted behind it, and only one standing on a summit or rooftop has a clear one")
	func cutoutsHaveSkies() {
		for environment in CinemaEnvironment.allCases {
			if environment.isCutout {
				let sky = environment.skyImageName
				#expect(sky.flatMap(cinemaEnvironmentImageURL(named:)) != nil, "\(environment) has no sky")
			} else {
				#expect(environment.skyImageName == nil)
			}
			if environment.siteKind != nil {
				#expect(environment.clearSkyImageName.flatMap(cinemaEnvironmentImageURL(named:)) != nil, "\(environment) has no clear sky")
			} else {
				#expect(environment.clearSkyImageName == nil)
			}
		}
	}

	@Test("the space station is a cutout with Earth behind it, on no summit or rooftop")
	func spaceStation() {
		let station = CinemaEnvironment.spaceStation
		#expect(station.isCutout)
		#expect(station.siteKind == nil)
		#expect(station.skyImageName == "space_earth")
		#expect(!station.hasStone)
		#expect(!station.hasScrolls)
		let anchors = CinemaAnchors.load(for: station)
		for board in CinemaBoard.allCases {
			#expect(anchors?.board(board) != nil, "the space station has no \(board) board")
		}
	}
}
#endif
