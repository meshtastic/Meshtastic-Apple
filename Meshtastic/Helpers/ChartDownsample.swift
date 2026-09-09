//
//  ChartDownsample.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/30/26.
//

import Foundation

/// Bounds the number of points fed to a Swift Charts plot. Charts lays out every
/// mark individually, and past roughly a thousand marks the layout pass stalls the
/// main thread long enough to register as an app hang — the metrics log screens
/// were the app's top hang source once hang tracking shipped. Decimation keeps a
/// uniform stride through the series plus the exact first and last points; tables
/// and CSV exports keep the full data.
func downsampledForChart<T>(_ points: [T], budget: Int = 600) -> [T] {
	guard budget > 2, points.count > budget else { return points }
	let stride = Double(points.count - 1) / Double(budget - 1)
	var result: [T] = []
	result.reserveCapacity(budget)
	for index in 0..<budget {
		result.append(points[Int((Double(index) * stride).rounded())])
	}
	return result
}
