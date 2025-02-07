//
//  CLLocationCoordinate2D.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 4/25/23.
//

import Foundation
import MapKit

extension CLLocationCoordinate2D {
	/// Returns distance from coordianate in meters.
	/// - Parameter from: coordinate which will be used as end point.
	/// - Returns: distance in meters.
	func distance(from: CLLocationCoordinate2D) -> CLLocationDistance {
		let from = CLLocation(latitude: from.latitude, longitude: from.longitude)
		let to = CLLocation(latitude: self.latitude, longitude: self.longitude)
		return from.distance(from: to)
	}
}

extension [CLLocationCoordinate2D] {
	/// Get Convex Hull For an array of CLLocationCoordinate2D positions
	/// - Returns: A smaller CLLocationCoordinate2D array containing only the points necessary to create a convex hull polygon
	func getConvexHull() -> [CLLocationCoordinate2D] {
		/// X = longitude
		/// Y = latitude
		/// 2D cross product of OA and OB vectors, i.e. z-component of their 3D cross product.
		/// Returns a positive value, if OAB makes a counter-clockwise turn,
		/// negative for clockwise turn, and zero if the points are collinear.
		func cross(point: CLLocationCoordinate2D, vectorA: CLLocationCoordinate2D, vectorB: CLLocationCoordinate2D) -> Double {
			let part1 = (vectorA.longitude - point.longitude) * (vectorB.latitude - point.latitude)
			let part2 = (vectorA.latitude - point.latitude) * (vectorB.longitude - point.longitude)
			return part1 - part2
		}
		// Sort points lexicographically
		let points = self.sorted {
			$0.longitude == $1.longitude ? $0.latitude < $1.latitude : $0.longitude < $1.longitude
		}
		// Build the lower hull
		var lower: [CLLocationCoordinate2D] = []
		for point in points {
			while lower.count >= 2 && cross(point: lower[lower.count - 2], vectorA: lower[lower.count - 1], vectorB: point) <= 0 {
				lower.removeLast()
			}
			lower.append(point)
		}
		// Build upper hull
		var upper: [CLLocationCoordinate2D] = []
		for point in points.reversed() {
			while upper.count >= 2 && cross(point: upper[upper.count-2], vectorA: upper[upper.count-1], vectorB: point) <= 0 {
				upper.removeLast()
			}
			upper.append(point)
		}
		// Last point of upper list is omitted because it is repeated at the
		// beginning of the lower list.
		upper.removeLast()
		// Concatenation of the lower and upper hulls gives the convex hull.
		return (upper + lower)
	}
}
