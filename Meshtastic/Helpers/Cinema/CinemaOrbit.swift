//
//  CinemaOrbit.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/10/26.
//
import Foundation
import simd

/// Which side of Earth is under the space station's cupola: the sunlit ground, or the dark side
/// with its city lights.
enum CinemaEarthSide: String, CaseIterable, Identifiable {
	case day
	case night

	static let key = "cinemaEarthSide"

	var id: String { rawValue }

	var title: String {
		switch self {
		case .day:
			String(localized: "Day", comment: "Cinema: the space station's view of Earth with the sunlit side under the cupola")
		case .night:
			String(localized: "Night", comment: "Cinema: the space station's view of Earth with the dark side and its city lights under the cupola")
		}
	}
}

/// A globe's mesh, as `CinemaOrbit.sphere(radius:segments:rings:)` builds it.
struct CinemaGlobeMesh {
	let positions: [SIMD3<Float>]
	let normals: [SIMD3<Float>]
	let coordinates: [SIMD2<Float>]
	let indices: [UInt32]
}

/// Where Earth and the sun are outside the space station's cupola, and how fast the ground goes by,
/// for the globe the cinema turns behind the cupola's windows. The same places as the render's
/// `scripts/cinema/orbit.py`, so the globe lines up with the painted cupola and its light, in the
/// cinema stage's axes: the image's center at -z, right +x, up +y, from the seat.
enum CinemaOrbit {
	/// The station's height and Earth's radius, in kilometers.
	static let altitude = 420.0
	static let earthRadius = 6371.0
	/// One trip round Earth, about how long the real station takes.
	static let period: TimeInterval = 92 * 60
	/// The panel's speed runs from real time to this many times faster.
	static let maximumSpeed = 10
	static let speedKey = "cinemaEarthSpeed"
	/// The clouds drift over the ground a little faster than it turns.
	static let cloudRate: Float = 1.06

	/// How far out the globe's center is drawn, in stage meters. Earth is drawn to scale for this
	/// distance, so it spans what it does from 420 km, and its nearest point and the air over it are
	/// still out past the cupola's 50 m sphere.
	static let globeDistance: Float = 1_200
	static var globeRadius: Float { globeDistance * Float(earthRadius / (earthRadius + altitude)) }
	/// The clouds and the top of the glowing air, as shells over the ground.
	static var cloudRadius: Float { globeRadius * Float((earthRadius + 8) / earthRadius) }
	static var airRadius: Float { globeRadius * Float((earthRadius + 70) / earthRadius) }

	/// The point on the ground straight under the station, and the way north runs from it as seen
	/// from the seat: the Bahamas and Florida, with north toward the front.
	static let nadirLatitude = 25.0
	static let nadirLongitude = -78.0
	static let north = simd_normalize(SIMD3<Float>(0.35, 0, -1))
	/// The way the station is flying over the ground, turned this far east of north.
	static let trackHeading: Float = 45 * .pi / 180

	/// A unit vector `azimuth` degrees clockwise from the front and `elevation` degrees up.
	static func direction(azimuth: Float, elevation: Float) -> SIMD3<Float> {
		let a = azimuth * .pi / 180, e = elevation * .pi / 180
		return SIMD3(sin(a) * cos(e), sin(e), -cos(a) * cos(e))
	}

	/// Earth's center: up and behind the seat, so its edge crosses the cupola's front windows.
	static var earthDirection: SIMD3<Float> { direction(azimuth: 180, elevation: 64) }

	/// The sun. By day, low on the left in front, so the ground under the station is lit with night
	/// coming over Earth's edge on the right, as the cupola's image is painted. By night, just past
	/// Earth's edge on the left as seen from the seat, so the side under the station is dark with
	/// only a thin dawn along that edge. (From 420 km the edge of the disk faces almost straight
	/// back at the station, so a sun hidden behind Earth would leave no dawn at all.)
	static func sunDirection(_ side: CinemaEarthSide) -> SIMD3<Float> {
		switch side {
		case .day:
			return direction(azimuth: -50, elevation: -10)
		case .night:
			let day = direction(azimuth: -50, elevation: -10)
			let across = simd_normalize(day - simd_dot(day, earthDirection) * earthDirection)
			let angle: Float = 72 * .pi / 180
			return simd_normalize(earthDirection * cos(angle) + across * sin(angle))
		}
	}

	/// The panel's speed, kept from 1 (real time) to `maximumSpeed`.
	static func speed(_ value: Int) -> Int {
		min(max(value, 1), maximumSpeed)
	}

	/// How fast the globe turns, in radians a second: once round in `period` at real time, faster
	/// with the speed, and not at all with Reduce Motion on.
	static func radiansPerSecond(speed: Int, reduceMotion: Bool) -> Float {
		guard !reduceMotion else { return 0 }
		return 2 * .pi / Float(period) * Float(self.speed(speed))
	}

	// MARK: The globe

	/// A point on the globe's surface at a latitude and longitude, in the globe's own axes: north
	/// up (+y), longitude 0 along +x, 90° east along -z.
	static func surfacePoint(latitude: Double, longitude: Double) -> SIMD3<Float> {
		let lat = latitude * .pi / 180, lon = longitude * .pi / 180
		return SIMD3(Float(cos(lat) * cos(lon)), Float(sin(lat)), Float(-cos(lat) * sin(lon)))
	}

	/// Where a latitude and longitude fall on an equirectangular texture: longitude -180 at the
	/// left edge, north at the top. RealityKit counts texture rows up from the bottom.
	static func textureCoordinate(latitude: Double, longitude: Double) -> SIMD2<Float> {
		SIMD2(Float((longitude + 180) / 360), Float((latitude + 90) / 180))
	}

	/// The turn that brings the nadir point round to face the seat, with north running the way
	/// `north` says.
	static var orientation: simd_quatf {
		let lat = nadirLatitude * .pi / 180, lon = nadirLongitude * .pi / 180
		let up0 = surfacePoint(latitude: nadirLatitude, longitude: nadirLongitude)
		let north0 = simd_normalize(SIMD3<Float>(Float(-sin(lat) * cos(lon)), Float(cos(lat)), Float(sin(lat) * sin(lon))))
		let east0 = simd_cross(north0, up0)
		let up = -earthDirection
		let northHere = simd_normalize(north - simd_dot(north, up) * up)
		let east = simd_cross(northHere, up)
		let local = simd_float3x3(columns: (east0, north0, up0))
		let world = simd_float3x3(columns: (east, northHere, up))
		return simd_quatf(world * local.transpose)
	}

	/// The axis the globe turns about, in the stage's axes, so the ground under the station runs
	/// back along the station's track as it flies.
	static var spinAxis: SIMD3<Float> {
		let up = -earthDirection
		let northHere = simd_normalize(north - simd_dot(north, up) * up)
		let east = simd_cross(northHere, up)
		let track = northHere * cos(trackHeading) + east * sin(trackHeading)
		return simd_normalize(simd_cross(track, up))
	}

	/// A globe of `radius`: positions and normals out from its center, texture coordinates that
	/// lay an equirectangular image over it, and triangles wound so their fronts face out.
	static func sphere(radius: Float, segments: Int = 160, rings: Int = 80) -> CinemaGlobeMesh {
		var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], coordinates: [SIMD2<Float>] = []
		for ring in 0...rings {
			let latitude = 90 - 180 * Double(ring) / Double(rings)
			for segment in 0...segments {
				let longitude = -180 + 360 * Double(segment) / Double(segments)
				let normal = surfacePoint(latitude: latitude, longitude: longitude)
				normals.append(normal)
				positions.append(normal * radius)
				coordinates.append(textureCoordinate(latitude: latitude, longitude: longitude))
			}
		}
		var indices: [UInt32] = []
		let row = UInt32(segments + 1)
		for ring in 0..<UInt32(rings) {
			for segment in 0..<UInt32(segments) {
				let a = ring * row + segment, b = a + row, c = b + 1, d = a + 1
				// Down a ring, then east: counterclockwise seen from outside.
				if ring > 0 { indices += [a, b, d] }
				if ring < UInt32(rings) - 1 { indices += [d, b, c] }
			}
		}
		return CinemaGlobeMesh(positions: positions, normals: normals, coordinates: coordinates, indices: indices)
	}

	/// The glow of the air seen edge on, for the shell over the ground at `airRadius`: how bright
	/// and what color at each point of that shell, by how near the edge of the globe it is as seen
	/// from the seat and how lit it is, blue by day reddening toward night. In the globe's unturned
	/// axes, which are the stage's, as RGBA with the opacity in alpha. Equirectangular like the
	/// other textures; the shell doesn't turn with the ground.
	static func airGlow(side: CinemaEarthSide, width: Int = 1024) -> [UInt8] {
		let height = width / 2
		let center = earthDirection * globeDistance
		let sun = sunDirection(side)
		var pixels = [UInt8](repeating: 0, count: width * height * 4)
		for y in 0..<height {
			let latitude = 90 - 180 * (Double(y) + 0.5) / Double(height)
			for x in 0..<width {
				let longitude = -180 + 360 * (Double(x) + 0.5) / Double(width)
				let n = surfacePoint(latitude: latitude, longitude: longitude)
				let toSeat = simd_normalize(-(center + n * airRadius))
				let facing = simd_dot(n, toSeat)
				guard facing > 0 else { continue }
				let edge = pow(1 - facing, 7)
				let lit = smoothstep(-0.25, 0.2, simd_dot(n, sun))
				let amount = min(edge * lit * 1.4, 1)
				guard amount > 0.002 else { continue }
				let blue = SIMD3<Float>(0.3, 0.55, 1.0), red = SIMD3<Float>(0.95, 0.4, 0.15)
				let color = red + (blue - red) * smoothstep(0, 0.6, lit)
				let i = (y * width + x) * 4
				pixels[i] = UInt8(color.x * 255)
				pixels[i + 1] = UInt8(color.y * 255)
				pixels[i + 2] = UInt8(color.z * 255)
				pixels[i + 3] = UInt8(amount * 255)
			}
		}
		return pixels
	}

	private static func smoothstep(_ low: Float, _ high: Float, _ value: Float) -> Float {
		let t = min(max((value - low) / (high - low), 0), 1)
		return t * t * (3 - 2 * t)
	}
}
