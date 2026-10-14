//
//  SpatialFrame.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/10/26.
//
import CoreLocation
import Foundation
import simd

/// The local frame a spatial map is built in: meters from the center of a geographic box, with
/// x east, y up and z south (north is away from a viewer standing south of the model). The box
/// is small enough that a flat-earth conversion around its center is accurate to well under a
/// meter, which is finer than any mesh position.
struct SpatialFrame: Equatable, Sendable {
	let bounds: GeoBounds
	let centerLatitude: Double
	let centerLongitude: Double
	/// Meters per degree of longitude at the center latitude.
	let metersPerDegreeLongitude: Double
	static let metersPerDegreeLatitude = 111_320.0

	init(bounds: GeoBounds) {
		self.bounds = bounds
		centerLatitude = (bounds.minLat + bounds.maxLat) / 2
		centerLongitude = (bounds.minLon + bounds.maxLon) / 2
		metersPerDegreeLongitude = Self.metersPerDegreeLatitude * cos(centerLatitude * .pi / 180)
	}

	/// Width (east-west) and depth (north-south) of the box in meters.
	var widthMeters: Double { (bounds.maxLon - bounds.minLon) * metersPerDegreeLongitude }
	var depthMeters: Double { (bounds.maxLat - bounds.minLat) * Self.metersPerDegreeLatitude }

	/// Local position of a coordinate at a height in meters above sea level.
	func localPosition(latitude: Double, longitude: Double, altitude: Double) -> SIMD3<Float> {
		SIMD3(
			Float((longitude - centerLongitude) * metersPerDegreeLongitude),
			Float(altitude),
			Float(-(latitude - centerLatitude) * Self.metersPerDegreeLatitude)
		)
	}

	func localPosition(_ coordinate: CLLocationCoordinate2D, altitude: Double) -> SIMD3<Float> {
		localPosition(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: altitude)
	}

	/// The coordinate at a local x/z position.
	func coordinate(x: Float, z: Float) -> CLLocationCoordinate2D {
		CLLocationCoordinate2D(
			latitude: centerLatitude - Double(z) / Self.metersPerDegreeLatitude,
			longitude: centerLongitude + Double(x) / metersPerDegreeLongitude
		)
	}

	/// Fraction (0...1) across the box, west to east and north to south, in Web Mercator. Used
	/// to line vertices up with a Mercator map image of the same box.
	func mercatorFraction(latitude: Double, longitude: Double) -> SIMD2<Double> {
		let u = (longitude - bounds.minLon) / (bounds.maxLon - bounds.minLon)
		let top = Self.mercatorY(bounds.maxLat)
		let bottom = Self.mercatorY(bounds.minLat)
		let v = (Self.mercatorY(latitude) - top) / (bottom - top)
		return SIMD2(u, v)
	}

	/// Latitude at a Mercator fraction (0 = north edge, 1 = south edge) of the box.
	func latitude(atMercatorFraction v: Double) -> Double {
		let top = Self.mercatorY(bounds.maxLat)
		let bottom = Self.mercatorY(bounds.minLat)
		return Self.latitude(mercatorY: top + v * (bottom - top))
	}

	func longitude(atFraction u: Double) -> Double {
		bounds.minLon + u * (bounds.maxLon - bounds.minLon)
	}

	/// Web Mercator y in 0...1 (0 at the north pole limit).
	static func mercatorY(_ latitude: Double) -> Double {
		let clamped = min(max(latitude, -85.05), 85.05)
		let rad = clamped * .pi / 180
		return (1 - log(tan(rad) + 1 / cos(rad)) / .pi) / 2
	}

	static func latitude(mercatorY y: Double) -> Double {
		atan(sinh(.pi * (1 - 2 * y))) * 180 / .pi
	}
}

/// The round area the spatial map shows. The terrain is a disk of this radius; the elevation
/// grid, the map image and terrain downloads cover `bounds`, the square around it.
struct SpatialCircle: Equatable, Sendable {
	let latitude: Double
	let longitude: Double
	let radiusMeters: Double

	/// A circle centered on the middle of the coordinates' extent, reaching the farthest one plus
	/// `padding` of that distance, and never smaller than `minimumRadiusMeters`. Nil when empty.
	static func around(_ coordinates: [CLLocationCoordinate2D], padding: Double = 0.15, minimumRadiusMeters: Double = 1_000) -> SpatialCircle? {
		guard let first = coordinates.first else { return nil }
		var minLat = first.latitude, maxLat = first.latitude
		var minLon = first.longitude, maxLon = first.longitude
		for c in coordinates.dropFirst() {
			minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
			minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
		}
		let unpadded = SpatialCircle(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2, radiusMeters: 0)
		let farthest = coordinates.map { unpadded.distanceMeters(to: $0) }.max() ?? 0
		return SpatialCircle(latitude: unpadded.latitude, longitude: unpadded.longitude, radiusMeters: max(farthest * (1 + padding), minimumRadiusMeters))
	}

	var metersPerDegreeLongitude: Double { SpatialFrame.metersPerDegreeLatitude * cos(latitude * .pi / 180) }

	/// Ground distance from the center, flat-earth in the same frame the model is built in.
	func distanceMeters(to coordinate: CLLocationCoordinate2D) -> Double {
		let x = (coordinate.longitude - longitude) * metersPerDegreeLongitude
		let z = (coordinate.latitude - latitude) * SpatialFrame.metersPerDegreeLatitude
		return (x * x + z * z).squareRoot()
	}

	func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
		distanceMeters(to: coordinate) <= radiusMeters
	}

	/// The square around the circle.
	var bounds: GeoBounds {
		let latSpan = radiusMeters / SpatialFrame.metersPerDegreeLatitude
		let lonSpan = radiusMeters / metersPerDegreeLongitude
		return GeoBounds(
			minLon: longitude - lonSpan, minLat: max(latitude - latSpan, -85),
			maxLon: longitude + lonSpan, maxLat: min(latitude + latSpan, 85)
		)
	}
}

extension GeoBounds {
	func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
		coordinate.latitude >= minLat && coordinate.latitude <= maxLat
			&& coordinate.longitude >= minLon && coordinate.longitude <= maxLon
	}

	func intersects(_ other: GeoBounds) -> Bool {
		maxLon > other.minLon && minLon < other.maxLon && maxLat > other.minLat && minLat < other.maxLat
	}
}
