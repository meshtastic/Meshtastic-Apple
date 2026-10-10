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

extension GeoBounds {
	/// A box around the given coordinates, padded by a fraction of its size on every side and never
	/// smaller than `minimumSpanMeters` across. Nil when there are no coordinates.
	static func around(_ coordinates: [CLLocationCoordinate2D], padding: Double = 0.15, minimumSpanMeters: Double = 2_000) -> GeoBounds? {
		guard let first = coordinates.first else { return nil }
		var minLat = first.latitude, maxLat = first.latitude
		var minLon = first.longitude, maxLon = first.longitude
		for c in coordinates.dropFirst() {
			minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
			minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
		}
		let centerLat = (minLat + maxLat) / 2
		let metersPerDegreeLon = SpatialFrame.metersPerDegreeLatitude * cos(centerLat * .pi / 180)
		var latSpan = max((maxLat - minLat) * (1 + 2 * padding), minimumSpanMeters / SpatialFrame.metersPerDegreeLatitude)
		var lonSpan = max((maxLon - minLon) * (1 + 2 * padding), minimumSpanMeters / metersPerDegreeLon)
		// Keep the box roughly square in meters so the model isn't a sliver.
		let latMeters = latSpan * SpatialFrame.metersPerDegreeLatitude
		let lonMeters = lonSpan * metersPerDegreeLon
		if latMeters < lonMeters * 0.5 { latSpan = lonMeters * 0.5 / SpatialFrame.metersPerDegreeLatitude }
		if lonMeters < latMeters * 0.5 { lonSpan = latMeters * 0.5 / metersPerDegreeLon }
		let centerLon = (minLon + maxLon) / 2
		return GeoBounds(
			minLon: centerLon - lonSpan / 2, minLat: max(centerLat - latSpan / 2, -85),
			maxLon: centerLon + lonSpan / 2, maxLat: min(centerLat + latSpan / 2, 85)
		)
	}

	func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
		coordinate.latitude >= minLat && coordinate.latitude <= maxLat
			&& coordinate.longitude >= minLon && coordinate.longitude <= maxLon
	}
}
