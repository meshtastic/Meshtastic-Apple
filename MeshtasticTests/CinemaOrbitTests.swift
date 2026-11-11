//
//  CinemaOrbitTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/10/26.
//
import Foundation
import simd
import Testing
@testable import Meshtastic

@Suite("Cinema space station Earth")
struct CinemaOrbitTests {

	@Test("the speed runs from real time to ten times, and Reduce Motion holds the globe still")
	func speedAndRate() {
		#expect(CinemaOrbit.speed(0) == 1)
		#expect(CinemaOrbit.speed(4) == 4)
		#expect(CinemaOrbit.speed(40) == CinemaOrbit.maximumSpeed)
		let realTime = CinemaOrbit.radiansPerSecond(speed: 1, reduceMotion: false)
		#expect(abs(realTime * Float(CinemaOrbit.period) - 2 * .pi) < 0.0001)
		#expect(abs(CinemaOrbit.radiansPerSecond(speed: 10, reduceMotion: false) - realTime * 10) < 0.000001)
		#expect(CinemaOrbit.radiansPerSecond(speed: 10, reduceMotion: true) == 0)
	}

	@Test("the globe spans what Earth does from 420 km, and it and its air stay out past the cupola's sphere")
	func globeScale() {
		let distance = CinemaOrbit.globeDistance
		let angularRadius = asin(CinemaOrbit.globeRadius / distance) * 180 / .pi
		#expect(abs(angularRadius - Float(asin(6371.0 / 6791.0) * 180 / .pi)) < 0.01)
		for radius in [CinemaOrbit.globeRadius, CinemaOrbit.cloudRadius, CinemaOrbit.airRadius] {
			#expect(distance - radius > 50)
			// The side the seat sees is all well inside the stars' sphere.
			#expect((distance * distance - radius * radius).squareRoot() < 980)
		}
		#expect(CinemaOrbit.globeRadius < CinemaOrbit.cloudRadius && CinemaOrbit.cloudRadius < CinemaOrbit.airRadius)
	}

	@Test("Earth is up and behind the seat, and the ground under the station faces the seat with north toward the front")
	func orientation() {
		#expect(CinemaOrbit.earthDirection.y > 0.85 && CinemaOrbit.earthDirection.z > 0)
		let nadir = CinemaOrbit.orientation.act(CinemaOrbit.surfacePoint(latitude: CinemaOrbit.nadirLatitude, longitude: CinemaOrbit.nadirLongitude))
		#expect(simd_dot(nadir, -CinemaOrbit.earthDirection) > 0.9999)
		let northward = CinemaOrbit.orientation.act(CinemaOrbit.surfacePoint(latitude: CinemaOrbit.nadirLatitude + 1, longitude: CinemaOrbit.nadirLongitude)) - nadir
		#expect(simd_dot(simd_normalize(northward), CinemaOrbit.north) > 0.9)
	}

	@Test("by day the sun lights the ground under the station; by night that side is dark with a thin dawn at the edge")
	func dayAndNight() {
		let underStation = -CinemaOrbit.earthDirection
		#expect(simd_dot(underStation, CinemaOrbit.sunDirection(.day)) > 0.3)
		let night = CinemaOrbit.sunDirection(.night)
		#expect(simd_dot(underStation, night) < -0.2)
		// The normals at the disk's edge, as seen from the seat, lean this far off the middle's;
		// the one toward the sun is lit, so there is a dawn along that edge.
		let edge = acos(CinemaOrbit.globeRadius / CinemaOrbit.globeDistance)
		let across = simd_normalize(night - simd_dot(night, underStation) * underStation)
		let edgeNormal = underStation * cos(edge) + across * sin(edge)
		#expect(simd_dot(edgeNormal, night) > 0)
	}

	@Test("turning about the spin axis runs the ground under the station back along its track")
	func spinRunsGroundBack() {
		let up = -CinemaOrbit.earthDirection
		let axis = CinemaOrbit.spinAxis
		#expect(abs(simd_dot(axis, up)) < 0.0001)
		let moved = simd_quatf(angle: 0.01, axis: axis).act(up)
		let northHere = simd_normalize(CinemaOrbit.north - simd_dot(CinemaOrbit.north, up) * up)
		// The track is north-east, so the ground goes south-west: against north.
		#expect(simd_dot(moved - up, northHere) < 0)
	}

	@Test("the globe's mesh faces out and lays the texture with north at the top")
	func sphereMesh() {
		let shape = CinemaOrbit.sphere(radius: 2, segments: 24, rings: 12)
		#expect(shape.positions.count == shape.normals.count && shape.positions.count == shape.coordinates.count)
		#expect(shape.indices.allSatisfy { Int($0) < shape.positions.count })
		for t in stride(from: 0, to: shape.indices.count, by: 3) {
			let p = (0..<3).map { shape.positions[Int(shape.indices[t + $0])] }
			let face = simd_cross(p[1] - p[0], p[2] - p[0])
			#expect(simd_dot(face, p[0] + p[1] + p[2]) > 0)
		}
		// The top of the image is north, and the left edge longitude -180.
		#expect(CinemaOrbit.textureCoordinate(latitude: 90, longitude: -180) == SIMD2(0, 1))
		#expect(CinemaOrbit.textureCoordinate(latitude: -90, longitude: 180) == SIMD2(1, 0))
		#expect(CinemaOrbit.surfacePoint(latitude: 90, longitude: 0).y == 1)
	}

	@Test("the air glows at the globe's edge as seen from the seat, not over its middle, and only where it's lit")
	func airGlow() {
		let width = 256, height = 128
		for side in CinemaEarthSide.allCases {
			let pixels = CinemaOrbit.airGlow(side: side, width: width)
			#expect(pixels.count == width * height * 4)
			// The point of the shell right in front of the seat: over the middle, so no glow.
			let front = -CinemaOrbit.earthDirection
			let latitude = asin(Double(front.y)) * 180 / .pi
			let longitude = atan2(Double(-front.z), Double(front.x)) * 180 / .pi
			let x = min(Int((longitude + 180) / 360 * Double(width)), width - 1)
			let y = min(Int((90 - latitude) / 180 * Double(height)), height - 1)
			#expect(pixels[(y * width + x) * 4 + 3] < 10)
			#expect(pixels.enumerated().contains { $0.offset % 4 == 3 && $0.element > 100 })
		}
	}
}
