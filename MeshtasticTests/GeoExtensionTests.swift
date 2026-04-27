import CoreLocation
import Testing

@testable import Meshtastic

// MARK: - CLLocationCoordinate2D Distance

@Suite("CLLocationCoordinate2D Distance")
struct CoordinateDistanceTests {

	@Test func samePoint_distanceIsZero() {
		let coord = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
		let distance = coord.distance(from: coord)
		#expect(distance < 0.01)
	}

	@Test func knownDistance_isApproximatelyCorrect() {
		// San Francisco to Los Angeles ≈ 559 km
		let sf = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
		let la = CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)
		let distance = la.distance(from: sf)
		#expect(distance > 500_000) // > 500 km
		#expect(distance < 620_000) // < 620 km
	}

	@Test func distanceIsAlwaysPositive() {
		let a = CLLocationCoordinate2D(latitude: 0, longitude: 0)
		let b = CLLocationCoordinate2D(latitude: 1, longitude: 1)
		#expect(a.distance(from: b) > 0)
	}

	@Test func distanceIsSymmetric() {
		let a = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
		let b = CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)
		let ab = a.distance(from: b)
		let ba = b.distance(from: a)
		#expect(abs(ab - ba) < 0.01)
	}
}

// MARK: - Convex Hull

@Suite("Convex Hull")
struct ConvexHullTests {

	@Test func emptyArray_returnsEmpty() {
		let points: [CLLocationCoordinate2D] = []
		let hull = points.getConvexHull()
		#expect(hull.isEmpty)
	}

	@Test func singlePoint_returnsSinglePoint() {
		let points = [CLLocationCoordinate2D(latitude: 1, longitude: 1)]
		let hull = points.getConvexHull()
		#expect(hull.count == 1)
	}

	@Test func twoPoints_returnsBothPointsPlusClosing() {
		let points = [
			CLLocationCoordinate2D(latitude: 0, longitude: 0),
			CLLocationCoordinate2D(latitude: 1, longitude: 1)
		]
		let hull = points.getConvexHull()
		// Algorithm returns lower + upper hull concatenated (includes closing point)
		#expect(hull.count >= 2)
	}

	@Test func squarePoints_returnsAllFourCorners() {
		let points = [
			CLLocationCoordinate2D(latitude: 0, longitude: 0),
			CLLocationCoordinate2D(latitude: 0, longitude: 1),
			CLLocationCoordinate2D(latitude: 1, longitude: 0),
			CLLocationCoordinate2D(latitude: 1, longitude: 1)
		]
		let hull = points.getConvexHull()
		// A square has 4 corners, hull should include all + closing point
		#expect(hull.count >= 4)
	}

	@Test func interiorPointExcluded_hullIsSmaller() {
		// Triangle with an interior point
		let points = [
			CLLocationCoordinate2D(latitude: 0, longitude: 0),
			CLLocationCoordinate2D(latitude: 0, longitude: 4),
			CLLocationCoordinate2D(latitude: 4, longitude: 0),
			CLLocationCoordinate2D(latitude: 1, longitude: 1) // interior
		]
		let hull = points.getConvexHull()
		// Hull should have 3 points (triangle) + closing = 4, not include interior
		#expect(hull.count <= 4)
	}

	@Test func collinearPoints_returnsEndpointsOrClosing() {
		let points = [
			CLLocationCoordinate2D(latitude: 0, longitude: 0),
			CLLocationCoordinate2D(latitude: 0, longitude: 1),
			CLLocationCoordinate2D(latitude: 0, longitude: 2)
		]
		let hull = points.getConvexHull()
		// Collinear points: hull has endpoints plus closing point from algorithm
		#expect(hull.count <= 4)
		#expect(hull.count >= 2)
	}

	@Test func largePointSet_hullIsSmallerOrEqual() {
		// Generate points in a circle with some interior points
		var points: [CLLocationCoordinate2D] = []
		for i in 0..<20 {
			let angle = Double(i) * (2 * .pi / 20)
			points.append(CLLocationCoordinate2D(
				latitude: cos(angle) * 10,
				longitude: sin(angle) * 10
			))
		}
		// Add interior points
		points.append(CLLocationCoordinate2D(latitude: 0, longitude: 0))
		points.append(CLLocationCoordinate2D(latitude: 1, longitude: 1))

		let hull = points.getConvexHull()
		#expect(hull.count <= points.count)
		#expect(hull.count > 2)
	}
}
