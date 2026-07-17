//
//  GeofenceTests.swift
//  MeshtasticTests
//
//  Tests for the waypoint-geofence alert engine (MeshPackets+Geofence):
//  the crossing-state store (baseline / transition / geometry-key rotation /
//  thread-safety), the WaypointEntity.contains(location:) geometry, and
//  applyGeofence(from:) proto→entity mapping.
//

import Testing
import Foundation
import CoreLocation
import MeshtasticProtobufs
@testable import Meshtastic

// MARK: - GeofenceCrossingStore

@Suite("Geofence crossing store")
struct GeofenceCrossingStoreTests {

	@Test("First observation of a pair establishes a baseline (returns nil, never notifies)")
	func firstObservationIsBaseline() {
		let store = GeofenceCrossingStore()
		#expect(store.update(key: "wp-1", isInside: true) == nil)
		#expect(store.update(key: "wp-2", isInside: false) == nil)
	}

	@Test("Second observation returns the previous state")
	func secondObservationReturnsPrevious() {
		let store = GeofenceCrossingStore()
		_ = store.update(key: "k", isInside: false)
		#expect(store.update(key: "k", isInside: true) == false)
	}

	@Test("Repeated same state returns that state — the engine treats it as no transition")
	func repeatedStateIsNoTransition() {
		let store = GeofenceCrossingStore()
		_ = store.update(key: "k", isInside: true)
		// previous == current -> evaluateGeofences skips (no enter/exit alert).
		#expect(store.update(key: "k", isInside: true) == true)
	}

	@Test("Different keys track independent state")
	func keysAreIndependent() {
		let store = GeofenceCrossingStore()
		_ = store.update(key: "a", isInside: true)
		#expect(store.update(key: "b", isInside: false) == nil)   // "b" never seen -> baseline
		#expect(store.update(key: "a", isInside: false) == true)  // "a" transitions inside->outside
	}

	@Test("Enter / exit / enter sequence reports the correct transitions")
	func enterExitEnterSequence() {
		let store = GeofenceCrossingStore()
		#expect(store.update(key: "k", isInside: true) == nil)    // baseline (no alert)
		#expect(store.update(key: "k", isInside: false) == true)  // was inside -> exit
		#expect(store.update(key: "k", isInside: true) == false)  // was outside -> enter
		#expect(store.update(key: "k", isInside: true) == true)   // unchanged -> no alert
	}

	/// Mirrors the production key format from `evaluateGeofences`: the geofence geometry
	/// (radius + bounding box corners) is part of the key, so changing it re-establishes a
	/// baseline instead of firing a spurious enter/exit from stale inside/outside state.
	private func geometryKey(
		waypointId: Int64, nodeNum: Int64, radius: Int,
		north: Int32 = 0, south: Int32 = 0, east: Int32 = 0, west: Int32 = 0
	) -> String {
		"\(waypointId)-\(nodeNum)-\(radius)-\(north)-\(south)-\(east)-\(west)"
	}

	@Test("Changing the geofence radius resets the baseline (no spurious alert)")
	func radiusChangeResetsBaseline() {
		let store = GeofenceCrossingStore()
		let inside100 = geometryKey(waypointId: 1, nodeNum: 42, radius: 100)
		#expect(store.update(key: inside100, isInside: true) == nil)  // baseline inside @100m

		// Radius enlarged to 200m -> different key -> brand-new baseline even though the node's
		// inside/outside may differ under the new geometry. Must NOT be reported as a transition.
		let outside200 = geometryKey(waypointId: 1, nodeNum: 42, radius: 200)
		#expect(store.update(key: outside200, isInside: false) == nil)
	}

	@Test("Changing the bounding box resets the baseline (no spurious alert)")
	func boundingBoxChangeResetsBaseline() {
		let store = GeofenceCrossingStore()
		let box1 = geometryKey(waypointId: 7, nodeNum: 9, radius: 0, north: 100, south: -100, east: 100, west: -100)
		#expect(store.update(key: box1, isInside: true) == nil)

		let box2 = geometryKey(waypointId: 7, nodeNum: 9, radius: 0, north: 200, south: -200, east: 200, west: -200)
		#expect(store.update(key: box2, isInside: false) == nil)   // new box -> fresh baseline
	}

	@Test("Concurrent updates are serialized without crashing or losing state")
	func concurrentUpdatesAreThreadSafe() {
		let store = GeofenceCrossingStore()
		// Hammer the store from many threads at once; the internal serial queue must keep this
		// crash-free and leave every touched key with a recorded state.
		DispatchQueue.concurrentPerform(iterations: 1_000) { i in
			_ = store.update(key: "shared", isInside: i % 2 == 0)
			_ = store.update(key: "k-\(i)", isInside: true)
		}
		// A previously-seen key now has a baseline, so a follow-up returns non-nil.
		#expect(store.update(key: "shared", isInside: true) != nil)
		#expect(store.update(key: "k-0", isInside: true) != nil)
		#expect(store.update(key: "k-999", isInside: true) != nil)
	}
}

// MARK: - WaypointEntity.contains(location:) geometry

@Suite("Waypoint geofence geometry")
struct WaypointGeofenceGeometryTests {

	/// Center used by the circular-geofence cases: 37.0, -122.0.
	private static let centerLatI: Int32 = 370000000
	private static let centerLonI: Int32 = -1220000000

	private func waypointWithCircle(radius: Int) -> WaypointEntity {
		let wp = WaypointEntity()
		wp.latitudeI = Self.centerLatI
		wp.longitudeI = Self.centerLonI
		wp.geofenceRadius = radius
		return wp
	}

	private func waypointWithBox() -> WaypointEntity {
		let wp = WaypointEntity()
		wp.hasBoundingBox = true
		wp.boundingBoxLatitudeNorthI = 370010000   // 37.001
		wp.boundingBoxLatitudeSouthI = 369990000   // 36.999
		wp.boundingBoxLongitudeEastI = -1219990000  // -121.999
		wp.boundingBoxLongitudeWestI = -1220010000  // -122.001
		return wp
	}

	@Test("No geofence -> contains returns nil")
	func noGeofenceReturnsNil() {
		let wp = WaypointEntity()
		wp.latitudeI = Self.centerLatI
		wp.longitudeI = Self.centerLonI
		#expect(wp.hasGeofence == false)
		#expect(wp.contains(location: CLLocation(latitude: 37.0, longitude: -122.0)) == nil)
	}

	@Test("Circle contains a point inside the radius")
	func circleContainsInsidePoint() {
		let wp = waypointWithCircle(radius: 100)
		// ~50 m north of center (0.000449° ≈ 50 m)
		let point = CLLocation(latitude: 37.000449, longitude: -122.0)
		#expect(wp.contains(location: point) == true)
	}

	@Test("Circle excludes a point beyond the radius")
	func circleExcludesOutsidePoint() {
		let wp = waypointWithCircle(radius: 100)
		// ~200 m north of center — well outside the 100 m radius
		let point = CLLocation(latitude: 37.0018, longitude: -122.0)
		#expect(wp.contains(location: point) == false)
	}

	@Test("Bounding box includes interior points and excludes exterior ones")
	func boundingBoxContainment() {
		let wp = waypointWithBox()
		#expect(wp.contains(location: CLLocation(latitude: 37.0, longitude: -122.0)) == true)      // center
		#expect(wp.contains(location: CLLocation(latitude: 37.0009, longitude: -122.0)) == true)   // just inside north
		#expect(wp.contains(location: CLLocation(latitude: 37.0011, longitude: -122.0)) == false)  // just north of box
		#expect(wp.contains(location: CLLocation(latitude: 37.0, longitude: -121.9989)) == false)  // just east of box
	}

	@Test("Circle and box combine as a union — inside either counts")
	func circleAndBoxAreUnion() {
		let wp = waypointWithBox()
		wp.latitudeI = Self.centerLatI
		wp.longitudeI = Self.centerLonI
		wp.geofenceRadius = 10   // tiny circle; the box is the larger region
		// ~90 m north: outside the 10 m circle but inside the box -> union == inside
		let point = CLLocation(latitude: 37.0008, longitude: -122.0)
		#expect(wp.contains(location: point) == true)
	}

	@Test("Point outside both the circle and the box -> false")
	func outsideBothReturnsFalse() {
		let wp = waypointWithBox()
		wp.latitudeI = Self.centerLatI
		wp.longitudeI = Self.centerLonI
		wp.geofenceRadius = 50
		let point = CLLocation(latitude: 37.5, longitude: -122.0)   // far away
		#expect(wp.contains(location: point) == false)
	}

	@Test("boundingBoxCoordinates: nil without a box, four corners with one")
	func boundingBoxCoordinates() {
		let plain = WaypointEntity()
		#expect(plain.boundingBoxCoordinates == nil)

		let wp = waypointWithBox()
		let corners = wp.boundingBoxCoordinates
		#expect(corners?.count == 4)
	}
}

// MARK: - WaypointEntity.applyGeofence(from:)

@Suite("Waypoint applyGeofence(from:)")
struct WaypointApplyGeofenceTests {

	@Test("Copies circular geofence + notification flags from the proto")
	func copiesCircleAndFlags() {
		let wp = WaypointEntity()
		var proto = Waypoint()
		proto.geofenceRadius = 250
		proto.notifyOnEnter = true
		proto.notifyOnExit = false
		proto.notifyFavoritesOnly = true

		wp.applyGeofence(from: proto)

		#expect(wp.geofenceRadius == 250)
		#expect(wp.notifyOnEnter == true)
		#expect(wp.notifyOnExit == false)
		#expect(wp.notifyFavoritesOnly == true)
		#expect(wp.hasBoundingBox == false)
	}

	@Test("Copies the bounding box when the proto has one")
	func copiesBoundingBox() {
		let wp = WaypointEntity()
		var proto = Waypoint()
		// Setting a field on the computed `boundingBox` materializes it (hasBoundingBox == true).
		proto.boundingBox.latitudeNorthI = 370010000
		proto.boundingBox.latitudeSouthI = 369990000
		proto.boundingBox.longitudeEastI = -1219990000
		proto.boundingBox.longitudeWestI = -1220010000
		#expect(proto.hasBoundingBox == true)

		wp.applyGeofence(from: proto)

		#expect(wp.hasBoundingBox == true)
		#expect(wp.boundingBoxLatitudeNorthI == 370010000)
		#expect(wp.boundingBoxLatitudeSouthI == 369990000)
		#expect(wp.boundingBoxLongitudeEastI == -1219990000)
		#expect(wp.boundingBoxLongitudeWestI == -1220010000)
	}

	@Test("Clears a stale bounding box when the proto has none")
	func clearsStaleBoundingBox() {
		let wp = WaypointEntity()
		// Pre-existing stale bounding box on the entity.
		wp.hasBoundingBox = true
		wp.boundingBoxLatitudeNorthI = 12345
		wp.boundingBoxLatitudeSouthI = 6789
		wp.boundingBoxLongitudeEastI = 111
		wp.boundingBoxLongitudeWestI = 222

		var proto = Waypoint()
		proto.geofenceRadius = 100   // circle only, no bounding box
		wp.applyGeofence(from: proto)

		#expect(wp.hasBoundingBox == false)
		#expect(wp.boundingBoxLatitudeNorthI == 0)
		#expect(wp.boundingBoxLatitudeSouthI == 0)
		#expect(wp.boundingBoxLongitudeEastI == 0)
		#expect(wp.boundingBoxLongitudeWestI == 0)
	}
}
