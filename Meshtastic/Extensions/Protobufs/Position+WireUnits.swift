//
//  Position+WireUnits.swift
//  Meshtastic
//

import CoreLocation
import MeshtasticProtobufs

/// On the wire `ground_speed` is km/h and `ground_track` is 1e-5 degrees, the units firmware GPS uses.
/// Speed, track and HAE altitude are optional fields: unset means no reading, and 0 is a reading.
extension Position {
	static let groundTrackUnitsPerDegree: Double = 100_000
	static let groundTrackFullCircle: UInt32 = 36_000_000

	/// km/h from a CoreLocation speed in m/s, or nil when CoreLocation marks the speed invalid.
	static func groundSpeedKmh(metersPerSecond speed: CLLocationSpeed, accuracy: CLLocationSpeedAccuracy) -> UInt32? {
		guard speed.isFinite, speed >= 0, accuracy >= 0 else { return nil }
		return UInt32(exactly: (speed * 3.6).rounded())
	}

	/// 1e-5 degrees in 0..<36,000,000 from a CoreLocation course, or nil when CoreLocation marks the course invalid.
	static func groundTrack(courseDegrees course: CLLocationDirection, accuracy: CLLocationDirectionAccuracy) -> UInt32? {
		guard course.isFinite, course >= 0, accuracy >= 0 else { return nil }
		guard let scaled = UInt32(exactly: (course * groundTrackUnitsPerDegree).rounded()) else { return nil }
		return scaled % groundTrackFullCircle
	}

	/// Whole meters above the WGS84 ellipsoid, or nil when CoreLocation marks the altitude invalid.
	static func altitudeHae(ellipsoidalAltitude: CLLocationDistance, verticalAccuracy: CLLocationAccuracy) -> Int32? {
		guard ellipsoidalAltitude.isFinite, verticalAccuracy > 0 else { return nil }
		return Int32(exactly: ellipsoidalAltitude.rounded())
	}

	/// Sets speed, track and HAE altitude from a phone fix, leaving each one unset when the fix has no valid reading.
	mutating func setSpeedTrackAndHae(from location: CLLocation) {
		if let speed = Self.groundSpeedKmh(metersPerSecond: location.speed, accuracy: location.speedAccuracy) {
			groundSpeed = speed
		}
		if let track = Self.groundTrack(courseDegrees: location.course, accuracy: location.courseAccuracy) {
			groundTrack = track
		}
		if let hae = Self.altitudeHae(ellipsoidalAltitude: location.ellipsoidalAltitude, verticalAccuracy: location.verticalAccuracy) {
			altitudeHae = hae
		}
	}

	/// `groundTrack` in whole degrees (0..<360), or nil when it is unset or out of range.
	var groundTrackDegrees: Int32? {
		guard hasGroundTrack, groundTrack < Self.groundTrackFullCircle else { return nil }
		return Int32((Double(groundTrack) / Self.groundTrackUnitsPerDegree).rounded()) % 360
	}
}
