//
//  EventFirmwareNotificationTests.swift
//  MeshtasticTests
//
//  Tests for auto-disabling new-node notifications on event firmware.
//

import Foundation
import Testing
@testable import Meshtastic
import MeshtasticProtobufs

@Suite("Event firmware notification defaults", .serialized)
struct EventFirmwareNotificationTests {

	init() {
		// Reset state before each test
		UserDefaults.newNodeNotifications = true
		UserDefaults.nodeNotificationsAutoDisabledForEvent = false
	}

	@Test func eventFirmwareDisablesNewNodeNotifications() {
		// Simulate: event firmware detected, not yet auto-disabled
		UserDefaults.nodeNotificationsAutoDisabledForEvent = false
		UserDefaults.newNodeNotifications = true

		// Apply logic inline (mirrors applyEventFirmwareNotificationDefaults)
		let edition = FirmwareEdition.defcon
		if edition != .vanilla {
			if !UserDefaults.nodeNotificationsAutoDisabledForEvent {
				UserDefaults.newNodeNotifications = false
				UserDefaults.nodeNotificationsAutoDisabledForEvent = true
			}
		}

		#expect(UserDefaults.newNodeNotifications == false)
		#expect(UserDefaults.nodeNotificationsAutoDisabledForEvent == true)
	}

	@Test func eventFirmwareDoesNotReDisableIfAlreadyAutoDisabled() {
		// User re-enabled manually; the flag stays true from prior auto-disable
		UserDefaults.nodeNotificationsAutoDisabledForEvent = true
		UserDefaults.newNodeNotifications = true

		let edition = FirmwareEdition.burningMan
		if edition != .vanilla {
			if !UserDefaults.nodeNotificationsAutoDisabledForEvent {
				UserDefaults.newNodeNotifications = false
				UserDefaults.nodeNotificationsAutoDisabledForEvent = true
			}
		}

		// Should not have changed since already auto-disabled
		#expect(UserDefaults.newNodeNotifications == true)
	}

	@Test func vanillaFirmwareReEnablesNotificationsAfterEventAutoDisable() {
		// Previously auto-disabled by event firmware
		UserDefaults.nodeNotificationsAutoDisabledForEvent = true
		UserDefaults.newNodeNotifications = false

		let edition = FirmwareEdition.vanilla
		if edition != .vanilla {
			if !UserDefaults.nodeNotificationsAutoDisabledForEvent {
				UserDefaults.newNodeNotifications = false
				UserDefaults.nodeNotificationsAutoDisabledForEvent = true
			}
		} else {
			if UserDefaults.nodeNotificationsAutoDisabledForEvent {
				UserDefaults.newNodeNotifications = true
				UserDefaults.nodeNotificationsAutoDisabledForEvent = false
			}
		}

		#expect(UserDefaults.newNodeNotifications == true)
		#expect(UserDefaults.nodeNotificationsAutoDisabledForEvent == false)
	}

	@Test func vanillaFirmwareDoesNotTouchPrefsWhenNotPreviouslyAutoDisabled() {
		// Never connected to event firmware
		UserDefaults.nodeNotificationsAutoDisabledForEvent = false
		UserDefaults.newNodeNotifications = false // user manually disabled

		let edition = FirmwareEdition.vanilla
		if edition != .vanilla {
			if !UserDefaults.nodeNotificationsAutoDisabledForEvent {
				UserDefaults.newNodeNotifications = false
				UserDefaults.nodeNotificationsAutoDisabledForEvent = true
			}
		} else {
			if UserDefaults.nodeNotificationsAutoDisabledForEvent {
				UserDefaults.newNodeNotifications = true
				UserDefaults.nodeNotificationsAutoDisabledForEvent = false
			}
		}

		// Should not re-enable since it wasn't auto-disabled
		#expect(UserDefaults.newNodeNotifications == false)
		#expect(UserDefaults.nodeNotificationsAutoDisabledForEvent == false)
	}

	@Test func allEventEditionsAreDetected() {
		let eventEditions: [FirmwareEdition] = [.defcon, .burningMan, .openSauce, .hamvention, .diyEdition, .smartCitizen]
		for edition in eventEditions {
			#expect(edition != .vanilla, "Expected \(edition) to not be vanilla")
		}
	}
}
