//
//  SpatialZoom.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/12/26.
//
import CoreLocation
import Foundation
import simd

/// Zooming the spatial map into the geography. The table keeps its size; the circle it shows gets
/// smaller around a center, and the terrain is rebuilt for it. Zoom 1 is the whole mesh.
enum SpatialZoom {
	/// The zoomed circle never gets smaller than this radius in meters.
	static let minimumRadiusMeters = 1_000.0
	/// How far Center on the card and Show in 3D zoom in on a node.
	static let focusZoom = 4.0

	/// The most the map can zoom in on a full circle: down to a 1 km radius, and never below 1.
	static func maximumZoom(fullRadiusMeters: Double) -> Double {
		guard fullRadiusMeters.isFinite, fullRadiusMeters > minimumRadiusMeters else { return 1 }
		return fullRadiusMeters / minimumRadiusMeters
	}

	static func clamp(_ zoom: Double, fullRadiusMeters: Double) -> Double {
		guard zoom.isFinite else { return 1 }
		return min(max(zoom, 1), maximumZoom(fullRadiusMeters: fullRadiusMeters))
	}

	/// The circle shown at a zoom around a center (the full circle's center when nil). The center
	/// is pulled in so the zoomed circle stays inside the full one, so zooming out ends on the
	/// whole mesh and the map never shows ground beyond it.
	static func circle(full: SpatialCircle, zoom: Double, center: CLLocationCoordinate2D?) -> SpatialCircle {
		let zoom = clamp(zoom, fullRadiusMeters: full.radiusMeters)
		let radius = full.radiusMeters / zoom
		guard let center, zoom > 1 else {
			return SpatialCircle(latitude: full.latitude, longitude: full.longitude, radiusMeters: radius)
		}
		// Offset of the center from the full circle's center in meters east and north.
		let east = (center.longitude - full.longitude) * full.metersPerDegreeLongitude
		let north = (center.latitude - full.latitude) * SpatialFrame.metersPerDegreeLatitude
		let distance = (east * east + north * north).squareRoot()
		let room = full.radiusMeters - radius
		let factor = distance > room && distance > 0 ? room / distance : 1
		return SpatialCircle(
			latitude: full.latitude + north * factor / SpatialFrame.metersPerDegreeLatitude,
			longitude: full.longitude + east * factor / full.metersPerDegreeLongitude,
			radiusMeters: radius
		)
	}

	/// Whether a node is drawn: only inside the circle shown, so nothing stands past the rim.
	static func isShown(_ coordinate: CLLocationCoordinate2D, in circle: SpatialCircle) -> Bool {
		circle.contains(coordinate)
	}

	/// Whether a point in model units lies on the disk, measured flat from its middle.
	static func isOnDisk(x: Float, z: Float, diskRadius: Float) -> Bool {
		x * x + z * z <= diskRadius * diskRadius * 1.0001
	}

	/// A point pulled in flat to the disk's rim when it lies past it, keeping its height. Used for
	/// flyover paths through nodes outside the zoomed circle, so they end at the rim.
	static func clampToDisk(_ point: SIMD3<Float>, diskRadius: Float) -> SIMD3<Float> {
		let distance = (point.x * point.x + point.z * point.z).squareRoot()
		guard distance > diskRadius, distance > 0 else { return point }
		let factor = diskRadius / distance
		return SIMD3(point.x * factor, point.y, point.z * factor)
	}

	/// While a zoom is waiting for its terrain, the built terrain is shown scaled and shifted
	/// toward what the new circle will show. `offset` is the new center's position on the current
	/// disk and `scale` how much bigger the new circle draws the ground, both in model units.
	/// The scale is held between 0.2 and the size where the terrain's edge reaches `maxRadius`,
	/// and the shift is cut so no part of the terrain goes past `maxRadius` (under the bezel).
	struct Preview: Equatable {
		let scale: Float
		let translation: SIMD2<Float>

		static let identity = Preview(scale: 1, translation: .zero)

		init(scale: Float, translation: SIMD2<Float>) {
			self.scale = scale
			self.translation = translation
		}

		init(offset: SIMD2<Float>, scale: Float, diskRadius: Float, maxRadius: Float) {
			guard diskRadius > 0, scale.isFinite, scale > 0 else {
				self = .identity
				return
			}
			let largest = max(maxRadius / diskRadius, 1)
			let s = min(max(scale, 0.2), largest)
			var t = -offset * s
			let room = max(maxRadius - s * diskRadius, 0)
			let length = simd_length(t)
			if length > room { t = length > 0 ? t * (room / length) : .zero }
			self.scale = s
			self.translation = t
		}

		/// Where a point on the built terrain shows during the preview.
		func apply(x: Float, z: Float) -> SIMD2<Float> {
			SIMD2(x, z) * scale + translation
		}
	}
}
