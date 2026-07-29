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
		UserDefaults.nodeNotificationsUserOverrideForEvent = false
	}

	@Test func eventFirmwareDisablesNewNodeNotifications() {
		let result = EventFirmwareNotificationPolicy.updatedSettings(
			for: .defcon,
			current: .init(
				newNodeNotifications: true,
				autoDisabledForEvent: false,
				userOverrideForEvent: false
			)
		)

		#expect(result.newNodeNotifications == false)
		#expect(result.autoDisabledForEvent == true)
	}

	@Test func eventFirmwareDoesNotReDisableIfAlreadyAutoDisabled() {
		let result = EventFirmwareNotificationPolicy.updatedSettings(
			for: .burningMan,
			current: .init(
				newNodeNotifications: true,
				autoDisabledForEvent: true,
				userOverrideForEvent: false
			)
		)

		#expect(result.newNodeNotifications == true)
		#expect(result.autoDisabledForEvent == true)
	}

	@Test func eventFirmwarePreservesNotificationsTheUserAlreadyDisabled() {
		let result = EventFirmwareNotificationPolicy.updatedSettings(
			for: .defcon,
			current: .init(
				newNodeNotifications: false,
				autoDisabledForEvent: false,
				userOverrideForEvent: false
			)
		)

		#expect(result.newNodeNotifications == false)
		#expect(result.autoDisabledForEvent == false)
	}

	@Test func vanillaFirmwareReEnablesNotificationsAfterEventAutoDisable() {
		let result = EventFirmwareNotificationPolicy.updatedSettings(
			for: .vanilla,
			current: .init(
				newNodeNotifications: false,
				autoDisabledForEvent: true,
				userOverrideForEvent: false
			)
		)

		#expect(result.newNodeNotifications == true)
		#expect(result.autoDisabledForEvent == false)
	}

	@Test func vanillaFirmwareDoesNotTouchPrefsWhenNotPreviouslyAutoDisabled() {
		let result = EventFirmwareNotificationPolicy.updatedSettings(
			for: .vanilla,
			current: .init(
				newNodeNotifications: false,
				autoDisabledForEvent: false,
				userOverrideForEvent: false
			)
		)

		#expect(result.newNodeNotifications == false)
		#expect(result.autoDisabledForEvent == false)
	}

	@Test func explicitUserChoiceSupersedesAutomaticEventPreference() {
		let automatic = EventFirmwareNotificationPolicy.updatedSettings(
			for: .defcon,
			current: .init(
				newNodeNotifications: true,
				autoDisabledForEvent: false,
				userOverrideForEvent: false
			)
		)
		let userChoice = EventFirmwareNotificationPolicy.userUpdatedSettings(
			newNodeNotifications: false,
			isEventFirmware: true
		)
		let afterVanilla = EventFirmwareNotificationPolicy.updatedSettings(
			for: .vanilla,
			current: userChoice
		)

		#expect(automatic == .init(
			newNodeNotifications: false,
			autoDisabledForEvent: true,
			userOverrideForEvent: false
		))
		#expect(userChoice == .init(
			newNodeNotifications: false,
			autoDisabledForEvent: false,
			userOverrideForEvent: true
		))
		#expect(afterVanilla == .init(
			newNodeNotifications: false,
			autoDisabledForEvent: false,
			userOverrideForEvent: false
		))
	}

	@Test func explicitUserReEnableIsPreservedAcrossEventMetadataUpdates() {
		let automatic = EventFirmwareNotificationPolicy.updatedSettings(
			for: .defcon,
			current: .init(
				newNodeNotifications: true,
				autoDisabledForEvent: false,
				userOverrideForEvent: false
			)
		)
		let userChoice = EventFirmwareNotificationPolicy.userUpdatedSettings(
			newNodeNotifications: true,
			isEventFirmware: true
		)
		let repeatedEventUpdate = EventFirmwareNotificationPolicy.updatedSettings(
			for: .defcon,
			current: userChoice
		)
		let afterVanilla = EventFirmwareNotificationPolicy.updatedSettings(
			for: .vanilla,
			current: repeatedEventUpdate
		)

		#expect(automatic.newNodeNotifications == false)
		#expect(repeatedEventUpdate == userChoice)
		#expect(afterVanilla == .init(
			newNodeNotifications: true,
			autoDisabledForEvent: false,
			userOverrideForEvent: false
		))
	}

	@Test func unknownNonVanillaEditionDisablesNotifications() {
		let result = EventFirmwareNotificationPolicy.updatedSettings(
			for: .UNRECOGNIZED(126),
			current: .init(
				newNodeNotifications: true,
				autoDisabledForEvent: false,
				userOverrideForEvent: false
			)
		)

		#expect(result.newNodeNotifications == false)
		#expect(result.autoDisabledForEvent == true)
	}

	@Test func allEventEditionsAreDetected() {
		let eventEditions: [FirmwareEdition] = [
			.defcon,
			.burningMan,
			.openSauce,
			.hamvention,
			.UNRECOGNIZED(20),
			.diyEdition,
			.smartCitizen
		]
		for edition in eventEditions {
			#expect(edition != .vanilla, "Expected \(edition) to not be vanilla")
		}
	}
}
