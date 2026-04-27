// ExtensionDetailedTests.swift
// MeshtasticTests

import Testing
import Foundation
import MapKit
import SwiftUI
import UIKit
@testable import Meshtastic

// MARK: - Data Extension Tests

@Suite("Data Extensions")
struct DataExtensionTests {

	@Test func macAddressString() {
		let data = Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
		#expect(data.macAddressString == "aa:bb:cc:dd:ee:ff")
	}

	@Test func macAddressString_empty() {
		let data = Data()
		#expect(data.macAddressString == "")
	}

	@Test func hexDescription() {
		let data = Data([0x01, 0x23, 0xAB, 0xCD])
		#expect(data.hexDescription == "0123abcd")
	}

	@Test func hexDescription_empty() {
		let data = Data()
		#expect(data.hexDescription == "")
	}
}

// MARK: - Date Extension Tests

@Suite("Date Extensions Detailed")
struct DateExtensionDetailedTests {

	@Test func lastHeard_recentDate() {
		let date = Date()
		let result = date.lastHeard
		#expect(!result.isEmpty)
		#expect(result != "Unknown Age")
	}

	@Test func lastHeard_epochZero() {
		let date = Date(timeIntervalSince1970: 0)
		#expect(date.lastHeard == "Unknown Age")
	}

	@Test func lastHeard_farFuture() {
		let date = Date(timeIntervalSince1970: Date().timeIntervalSince1970 + 400 * 24 * 3600)
		#expect(date.lastHeard == "Unknown Age")
	}

	@Test func relativeTimeOfDay_morning() {
		var cal = Calendar.current
		cal.timeZone = TimeZone.current
		var comps = cal.dateComponents([.year, .month, .day], from: Date())
		comps.hour = 8
		comps.minute = 0
		let date = cal.date(from: comps)!
		#expect(date.relativeTimeOfDay() == "Morning")
	}

	@Test func relativeTimeOfDay_midday() {
		var cal = Calendar.current
		cal.timeZone = TimeZone.current
		var comps = cal.dateComponents([.year, .month, .day], from: Date())
		comps.hour = 12
		comps.minute = 0
		let date = cal.date(from: comps)!
		#expect(date.relativeTimeOfDay() == "Midday")
	}

	@Test func relativeTimeOfDay_afternoon() {
		var cal = Calendar.current
		cal.timeZone = TimeZone.current
		var comps = cal.dateComponents([.year, .month, .day], from: Date())
		comps.hour = 15
		comps.minute = 0
		let date = cal.date(from: comps)!
		#expect(date.relativeTimeOfDay() == "Afternoon")
	}

	@Test func relativeTimeOfDay_evening() {
		var cal = Calendar.current
		cal.timeZone = TimeZone.current
		var comps = cal.dateComponents([.year, .month, .day], from: Date())
		comps.hour = 19
		comps.minute = 0
		let date = cal.date(from: comps)!
		#expect(date.relativeTimeOfDay() == "Evening")
	}

	@Test func relativeTimeOfDay_nighttime() {
		var cal = Calendar.current
		cal.timeZone = TimeZone.current
		var comps = cal.dateComponents([.year, .month, .day], from: Date())
		comps.hour = 3
		comps.minute = 0
		let date = cal.date(from: comps)!
		#expect(date.relativeTimeOfDay() == "Nighttime")
	}
}

// MARK: - Float Extension Tests

@Suite("Float Extensions")
struct FloatExtensionTests {

	@Test func formattedTemperature_zero() {
		let temp = Float(0.0)
		let result = temp.formattedTemperature()
		#expect(!result.isEmpty)
	}

	@Test func formattedTemperature_positive() {
		let temp = Float(25.0)
		let result = temp.formattedTemperature()
		#expect(!result.isEmpty)
	}

	@Test func shortFormattedTemperature() {
		let temp = Float(100.0)
		let result = temp.shortFormattedTemperature()
		#expect(!result.isEmpty)
	}

	@Test func localeTemperature() {
		let temp = Float(0.0)
		let result = temp.localeTemperature()
		// At 0°C, locale temperature is either 0 (metric) or 32 (imperial)
		#expect(result == 0.0 || abs(result - 32.0) < 0.1)
	}
}

// MARK: - Double Extension Tests

@Suite("Double Extensions")
struct DoubleExtensionTests {

	@Test func toBytes_zero() {
		let result = Double(0).toBytes
		#expect(!result.isEmpty)
	}

	@Test func toBytes_large() {
		let result = Double(1_000_000).toBytes
		#expect(!result.isEmpty)
	}
}

// MARK: - CLLocation Tests

@Suite("CLLocation Functions Detailed")
struct CLLocationFunctionDetailedTests {

	@Test func degreesToRadians_zero() {
		#expect(degreesToRadians(degrees: 0) == 0)
	}

	@Test func degreesToRadians_90() {
		#expect(abs(degreesToRadians(degrees: 90) - .pi / 2) < 0.0001)
	}

	@Test func degreesToRadians_180() {
		#expect(abs(degreesToRadians(degrees: 180) - .pi) < 0.0001)
	}

	@Test func radiansToDegrees_zero() {
		#expect(radiansToDegrees(radians: 0) == 0)
	}

	@Test func radiansToDegrees_pi() {
		#expect(abs(radiansToDegrees(radians: .pi) - 180) < 0.0001)
	}

	@Test func roundTrip_degreesRadiansDegrees() {
		let original = 45.0
		let result = radiansToDegrees(radians: degreesToRadians(degrees: original))
		#expect(abs(result - original) < 0.0001)
	}

	@Test func getBearing_northToSouth() {
		let p1 = CLLocation(latitude: 0, longitude: 0)
		let p2 = CLLocation(latitude: -10, longitude: 0)
		let bearing = getBearingBetweenTwoPoints(point1: p1, point2: p2)
		#expect(abs(bearing - 180) < 1.0)
	}

	@Test func getBearing_eastward() {
		let p1 = CLLocation(latitude: 0, longitude: 0)
		let p2 = CLLocation(latitude: 0, longitude: 10)
		let bearing = getBearingBetweenTwoPoints(point1: p1, point2: p2)
		#expect(abs(bearing - 90) < 1.0)
	}

	@Test func getBearing_samePoint() {
		let p1 = CLLocation(latitude: 37.7749, longitude: -122.4194)
		let bearing = getBearingBetweenTwoPoints(point1: p1, point2: p1)
		#expect(bearing.isFinite)
	}
}

// MARK: - CLLocationCoordinate2D Tests

@Suite("CLLocationCoordinate2D Extensions")
struct CLLocationCoordinate2DExtensionTests {

	@Test func distance_samePoint() {
		let coord = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
		let dist = coord.distance(from: coord)
		#expect(dist < 1.0)
	}

	@Test func distance_knownPoints() {
		let sf = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
		let la = CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)
		let dist = la.distance(from: sf)
		// SF to LA is approximately 559 km
		#expect(dist > 500_000 && dist < 600_000)
	}

	@Test func convexHull_triangle() {
		let points = [
			CLLocationCoordinate2D(latitude: 0, longitude: 0),
			CLLocationCoordinate2D(latitude: 1, longitude: 0),
			CLLocationCoordinate2D(latitude: 0, longitude: 1)
		]
		let hull = points.getConvexHull()
		#expect(hull.count == 3)
	}

	@Test func convexHull_squareWithInterior() {
		let points = [
			CLLocationCoordinate2D(latitude: 0, longitude: 0),
			CLLocationCoordinate2D(latitude: 0, longitude: 2),
			CLLocationCoordinate2D(latitude: 2, longitude: 0),
			CLLocationCoordinate2D(latitude: 2, longitude: 2),
			CLLocationCoordinate2D(latitude: 1, longitude: 1) // interior point
		]
		let hull = points.getConvexHull()
		#expect(hull.count == 4)
	}

	@Test func convexHull_emptyArray() {
		let points: [CLLocationCoordinate2D] = []
		let hull = points.getConvexHull()
		#expect(hull.isEmpty)
	}

	@Test func convexHull_singlePoint() {
		let points = [CLLocationCoordinate2D(latitude: 1, longitude: 1)]
		let hull = points.getConvexHull()
		#expect(hull.count >= 1)
	}
}

// MARK: - Color Extension Tests

@Suite("Color Extensions")
struct ColorExtensionTests {

	@Test func initFromHex6() {
		let color = Color(hex: "#FF0000")
		// Should create a non-crashing Color
		_ = color
	}

	@Test func initFromHex3() {
		let color = Color(hex: "F00")
		_ = color
	}

	@Test func initFromHex8() {
		let color = Color(hex: "80FF0000")
		_ = color
	}

	@Test func initFromHex_invalid() {
		let color = Color(hex: "xyz")
		_ = color
	}
}

// MARK: - UIColor Extension Tests

@Suite("UIColor Extensions")
struct UIColorExtensionTests {

	@Test func hex_red() {
		let color = UIColor(red: 1.0, green: 0, blue: 0, alpha: 1.0)
		let hex = color.hex
		// Red should have high bits in the red channel
		#expect((hex & 0xFF0000) >> 16 == 255)
		#expect((hex & 0x00FF00) >> 8 == 0)
		#expect(hex & 0x0000FF == 0)
	}

	@Test func hex_green() {
		let color = UIColor(red: 0, green: 1.0, blue: 0, alpha: 1.0)
		let hex = color.hex
		#expect((hex & 0x00FF00) >> 8 == 255)
	}

	@Test func initFromHex_roundTrip() {
		let original: UInt32 = 0xFF8040
		let color = UIColor(hex: original)
		// Verify it created a valid color
		var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
		color.getRed(&r, green: &g, blue: &b, alpha: &a)
		#expect(abs(r - 1.0) < 0.01)
		#expect(abs(g - 0.502) < 0.01)
		#expect(abs(b - 0.251) < 0.01)
	}
}

// MARK: - TimeZone Extension Tests

@Suite("TimeZone Extensions")
struct TimeZoneExtensionTests {

	@Test func posixDescription_utc() {
		let tz = TimeZone(identifier: "UTC")!
		let posix = tz.posixDescription
		#expect(!posix.isEmpty)
		#expect(posix.contains("GMT") || posix.contains("UTC"))
	}

	@Test func posixDescription_noDST() {
		// Arizona doesn't observe DST
		let tz = TimeZone(identifier: "America/Phoenix")!
		let posix = tz.posixDescription
		#expect(!posix.isEmpty)
	}

	@Test func posixDescription_withDST() {
		let tz = TimeZone(identifier: "America/New_York")!
		let posix = tz.posixDescription
		#expect(!posix.isEmpty)
		// Should contain DST transition info with "M" for month
		#expect(posix.contains(",M") || !tz.isDaylightSavingTime())
	}
}
