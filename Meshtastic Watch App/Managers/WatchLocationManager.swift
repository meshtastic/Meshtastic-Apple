//
//  WatchLocationManager.swift
//  Meshtastic Watch App
//
//  Copyright(c) Meshtastic 2025.
//

import Foundation
import CoreLocation
import os

/// Manages location and heading updates for the watchOS foxhunt compass.
///
/// On Apple Watch models with a magnetometer (Series 5+) the compass heading
/// is used. On older models the GPS course (direction of travel) is used as a
/// fallback – this only works while the user is moving.
@MainActor
final class WatchLocationManager: NSObject, ObservableObject {

	private let manager = CLLocationManager()
	private let logger = Logger(subsystem: "gvh.MeshtasticClient.watchkitapp", category: "📍 Location")

	/// Current heading in degrees (0‑360). Updated from the magnetometer when
	/// available, otherwise falls back to GPS course.
	@Published var heading: Double = 0

	/// Most recent location of the watch.
	@Published var currentLocation: CLLocation?

	/// `true` once the manager is actively delivering updates.
	@Published var isUpdating = false

	/// Authorisation status surfaced to the UI so it can prompt if needed.
	@Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

	/// Whether the device has a compass (magnetometer).
	var hasCompass: Bool { CLLocationManager.headingAvailable() }

	// MARK: - Lifecycle

	override init() {
		super.init()
		manager.delegate = self
		manager.desiredAccuracy = kCLLocationAccuracyBest
		manager.distanceFilter = 2 // metres
		authorizationStatus = manager.authorizationStatus
	}

	func requestAuthorization() {
		logger.info("Requesting location authorisation")
		manager.requestWhenInUseAuthorization()
	}

	func startUpdates() {
		guard authorizationStatus == .authorizedAlways ||
			  authorizationStatus == .authorizedWhenInUse else {
			logger.warning("Cannot start updates – insufficient authorisation (\(self.authorizationStatus.rawValue))")
			return
		}
		logger.info("Starting location updates")
		manager.startUpdatingLocation()
		if CLLocationManager.headingAvailable() {
			manager.headingFilter = 1
			manager.startUpdatingHeading()
		}
		isUpdating = true
	}

	func stopUpdates() {
		logger.info("Stopping location updates")
		manager.stopUpdatingLocation()
		if CLLocationManager.headingAvailable() {
			manager.stopUpdatingHeading()
		}
		isUpdating = false
	}
}

// MARK: - CLLocationManagerDelegate
extension WatchLocationManager: @preconcurrency CLLocationManagerDelegate {

	nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
		Task { @MainActor in
			guard let latest = locations.last else { return }
			self.currentLocation = latest

			// Fallback heading from GPS course when no magnetometer.
			if !CLLocationManager.headingAvailable(), latest.course >= 0 {
				self.heading = latest.course
			}
		}
	}

	nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
		Task { @MainActor in
			self.heading = newHeading.trueHeading >= 0
				? newHeading.trueHeading
				: newHeading.magneticHeading
		}
	}

	nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
		Task { @MainActor in
			self.authorizationStatus = manager.authorizationStatus
			if self.authorizationStatus == .authorizedAlways ||
			   self.authorizationStatus == .authorizedWhenInUse {
				self.startUpdates()
			}
		}
	}

	nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
		Task { @MainActor in
			logger.error("Location error: \(error.localizedDescription, privacy: .public)")
		}
	}
}
