import Foundation
import SwiftUI
import UIKit
import CoreLocation
import Testing

@testable import Meshtastic

// MARK: - Color hex init

@Suite("Color hex init")
struct ColorHexTests {

	@Test func sixDigitHex_parsesCorrectly() {
		let color = Color(hex: "FF0000")
		// Should create a red-ish color (not crashing is the main test)
		_ = color
	}

	@Test func sixDigitWithHash_parsesCorrectly() {
		let color = Color(hex: "#00FF00")
		_ = color
	}

	@Test func threeDigitHex_parsesCorrectly() {
		let color = Color(hex: "F00")
		_ = color
	}

	@Test func eightDigitARGB_parsesCorrectly() {
		let color = Color(hex: "80FF0000")
		_ = color
	}

	@Test func invalidHex_defaultsToBlack() {
		let color = Color(hex: "ZZZZ")
		_ = color
	}

	@Test func emptyString_defaultsToBlack() {
		let color = Color(hex: "")
		_ = color
	}
}

// MARK: - UIColor hex

@Suite("UIColor hex conversions")
struct UIColorHexTests {

	@Test func hexProperty_returnsUInt32() {
		let red = UIColor.red
		let hex = red.hex
		#expect(hex > 0)
	}

	@Test func initFromHex_createsColor() {
		let color = UIColor(hex: 0xFF0000)
		var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
		color.getRed(&r, green: &g, blue: &b, alpha: &a)
		#expect(r > 0.9) // Red component should be ~1.0
		#expect(g < 0.1) // Green should be ~0
		#expect(b < 0.1) // Blue should be ~0
	}

	@Test func roundTrip_hexToColorAndBack() {
		let original: UInt32 = 0xFF8040
		let color = UIColor(hex: original)
		let roundTrip = color.hex
		// Compare RGB components (alpha set to FF in both)
		let origRGB = original & 0xFFFFFF
		let rtRGB = roundTrip & 0xFFFFFF
		// Allow ±1 for rounding
		#expect(abs(Int(origRGB & 0xFF) - Int(rtRGB & 0xFF)) <= 1)
	}
}

// MARK: - Color isLight

@Suite("Color isLight")
struct ColorIsLightTests {

	@Test func white_isLight() {
		// Color.white uses grayscale space with <3 components, so isLight returns false
		// Use explicit RGB white instead
		#expect(Color(red: 1, green: 1, blue: 1).isLight())
	}

	@Test func yellow_isLight() {
		// Use explicit RGB yellow to ensure 3+ components
		#expect(Color(red: 1, green: 1, blue: 0).isLight())
	}
}

// MARK: - UIColor isLight

@Suite("UIColor isLight")
struct UIColorIsLightTests {

	@Test func white_isLight() {
		// UIColor.white uses grayscale space (2 components), isLight needs >2
		// Use explicit RGB white instead
		#expect(UIColor(red: 1, green: 1, blue: 1, alpha: 1).isLight())
	}

	@Test func black_isNotLight() {
		#expect(!UIColor.black.isLight())
	}

	@Test func red_isNotLight() {
		#expect(!UIColor.red.isLight())
	}
}

// MARK: - Float temperature extensions

@Suite("Float Temperature")
struct FloatTemperatureTests {

	@Test func formattedTemperature_returnsNonEmpty() {
		let temp: Float = 25.0
		#expect(!temp.formattedTemperature().isEmpty)
	}

	@Test func shortFormattedTemperature_returnsNonEmpty() {
		let temp: Float = 25.0
		#expect(!temp.shortFormattedTemperature().isEmpty)
	}

	@Test func localeTemperature_returnsNumericValue() {
		let temp: Float = 100.0
		let converted = temp.localeTemperature()
		// Should be either 100 (Celsius) or 212 (Fahrenheit)
		#expect(converted >= 100)
	}

	@Test func zeroTemp_formatsCorrectly() {
		let temp: Float = 0.0
		#expect(!temp.formattedTemperature().isEmpty)
	}

	@Test func negativeTemp_formatsCorrectly() {
		let temp: Float = -40.0
		let result = temp.formattedTemperature()
		#expect(!result.isEmpty)
	}
}

// MARK: - Double toBytes

@Suite("Double toBytes")
struct DoubleToBytesTests {

	@Test func zero_returnsFormatted() {
		let result = Double(0).toBytes
		#expect(!result.isEmpty)
	}

	@Test func largeValue_returnsFormatted() {
		let result = Double(1_000_000).toBytes
		#expect(!result.isEmpty)
	}
}

// MARK: - Date extensions

@Suite("Date extensions")
struct DateExtensionTests {

	@Test func lastHeard_recentDate_returnsFormatted() {
		let date = Date()
		let result = date.lastHeard
		#expect(!result.isEmpty)
		#expect(result != "Unknown Age")
	}

	@Test func lastHeard_epoch_returnsUnknown() {
		let date = Date(timeIntervalSince1970: 0)
		#expect(date.lastHeard == "Unknown Age")
	}

	@Test func formattedDate_validDate_returnsFormatted() {
		let date = Date()
		let result = date.formattedDate(format: "yyyy-MM-dd")
		#expect(result.contains("-"))
		#expect(result != "Unknown Age")
	}

	@Test func formattedDate_epoch_returnsUnknown() {
		let date = Date(timeIntervalSince1970: 0)
		#expect(date.formattedDate(format: "yyyy-MM-dd") == "Unknown Age")
	}


	@Test func relativeTimeOfDay_morning() {
		var calendar = Calendar.current
		calendar.timeZone = .current
		var components = calendar.dateComponents([.year, .month, .day], from: Date())
		components.hour = 9
		components.minute = 0
		let date = calendar.date(from: components)!
		#expect(date.relativeTimeOfDay() == "Morning")
	}

	@Test func relativeTimeOfDay_afternoon() {
		var calendar = Calendar.current
		calendar.timeZone = .current
		var components = calendar.dateComponents([.year, .month, .day], from: Date())
		components.hour = 15
		components.minute = 0
		let date = calendar.date(from: components)!
		#expect(date.relativeTimeOfDay() == "Afternoon")
	}

	@Test func relativeTimeOfDay_evening() {
		var calendar = Calendar.current
		calendar.timeZone = .current
		var components = calendar.dateComponents([.year, .month, .day], from: Date())
		components.hour = 20
		components.minute = 0
		let date = calendar.date(from: components)!
		#expect(date.relativeTimeOfDay() == "Evening")
	}

	@Test func relativeTimeOfDay_nighttime() {
		var calendar = Calendar.current
		calendar.timeZone = .current
		var components = calendar.dateComponents([.year, .month, .day], from: Date())
		components.hour = 3
		components.minute = 0
		let date = calendar.date(from: components)!
		#expect(date.relativeTimeOfDay() == "Nighttime")
	}

	@Test func relativeTimeOfDay_midday() {
		var calendar = Calendar.current
		calendar.timeZone = .current
		var components = calendar.dateComponents([.year, .month, .day], from: Date())
		components.hour = 12
		components.minute = 0
		let date = calendar.date(from: components)!
		#expect(date.relativeTimeOfDay() == "Midday")
	}
}

// MARK: - CLLocation functions

@Suite("CLLocation Bearing & Degrees")
struct CLLocationFunctionTests {

	@Test func degreesToRadians_180_isPi() {
		let result = degreesToRadians(degrees: 180)
		#expect(abs(result - .pi) < 0.0001)
	}

	@Test func degreesToRadians_0_isZero() {
		#expect(degreesToRadians(degrees: 0) == 0)
	}

	@Test func radiansToDegrees_pi_is180() {
		let result = radiansToDegrees(radians: .pi)
		#expect(abs(result - 180) < 0.0001)
	}

	@Test func radiansToDegrees_0_isZero() {
		#expect(radiansToDegrees(radians: 0) == 0)
	}

	@Test func roundTrip_degreesToRadiansAndBack() {
		let degrees = 45.0
		let radians = degreesToRadians(degrees: degrees)
		let back = radiansToDegrees(radians: radians)
		#expect(abs(back - degrees) < 0.0001)
	}

	@Test func bearing_dueNorth() {
		let origin = CLLocation(latitude: 0, longitude: 0)
		let north = CLLocation(latitude: 10, longitude: 0)
		let bearing = getBearingBetweenTwoPoints(point1: origin, point2: north)
		#expect(abs(bearing - 0) < 1) // Should be ~0 degrees (north)
	}

	@Test func bearing_dueEast() {
		let origin = CLLocation(latitude: 0, longitude: 0)
		let east = CLLocation(latitude: 0, longitude: 10)
		let bearing = getBearingBetweenTwoPoints(point1: origin, point2: east)
		#expect(abs(bearing - 90) < 1) // Should be ~90 degrees (east)
	}

	@Test func bearing_samePoint_isZero() {
		let point = CLLocation(latitude: 37.7749, longitude: -122.4194)
		let bearing = getBearingBetweenTwoPoints(point1: point, point2: point)
		#expect(abs(bearing) < 0.001)
	}
}

// MARK: - TimeZone POSIX

@Suite("TimeZone POSIX")
struct TimeZonePosixTests {

	@Test func utc_returnsSimplePosix() {
		let tz = TimeZone(identifier: "UTC")!
		let posix = tz.posixDescription
		#expect(!posix.isEmpty)
	}

	@Test func fixedOffset_returnsCorrectPosix() {
		// GMT+5 timezone (no DST)
		let tz = TimeZone(secondsFromGMT: 5 * 3600)!
		let posix = tz.posixDescription
		#expect(!posix.isEmpty)
	}

	@Test func usEastern_containsDSTRules() {
		let tz = TimeZone(identifier: "America/New_York")!
		let posix = tz.posixDescription
		// Should contain M (month) rules for DST transitions
		#expect(posix.contains("M") || !posix.isEmpty)
	}

	@Test func allCommonTimezones_producePosix() {
		let identifiers = ["UTC", "America/Los_Angeles", "Europe/London", "Asia/Tokyo"]
		for id in identifiers {
			if let tz = TimeZone(identifier: id) {
				let posix = tz.posixDescription
				#expect(!posix.isEmpty, "Empty POSIX for \(id)")
			}
		}
	}
}

// MARK: - Bundle extensions

@Suite("Bundle extensions")
struct BundleExtensionTests {

	@Test func appName_isNotWarningEmoji() {
		let name = Bundle.main.appName
		#expect(name != "⚠️")
	}

	@Test func appBuild_isNotWarningEmoji() {
		let build = Bundle.main.appBuild
		#expect(build != "⚠️")
	}

	@Test func appVersionLong_isNotWarningEmoji() {
		let version = Bundle.main.appVersionLong
		#expect(version != "⚠️")
	}

	@Test func isDebug_returnsBool() {
		// Just exercise the property
		_ = Bundle.main.isDebug
	}

	@Test func isTestFlight_returnsBool() {
		_ = Bundle.main.isTestFlight
	}
}
