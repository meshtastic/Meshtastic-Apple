// MARK: EventFirmwareNotificationPolicy.swift

import MeshtasticProtobufs

struct EventFirmwareNotificationSettings: Equatable {
	let newNodeNotifications: Bool
	let autoDisabledForEvent: Bool
	let userOverrideForEvent: Bool
}

enum EventFirmwareNotificationPolicy {

	static func userUpdatedSettings(
		newNodeNotifications: Bool,
		isEventFirmware: Bool
	) -> EventFirmwareNotificationSettings {
		EventFirmwareNotificationSettings(
			newNodeNotifications: newNodeNotifications,
			autoDisabledForEvent: false,
			userOverrideForEvent: isEventFirmware
		)
	}

	static func updatedSettings(
		for edition: FirmwareEdition,
		current: EventFirmwareNotificationSettings
	) -> EventFirmwareNotificationSettings {
		if edition == .vanilla {
			return EventFirmwareNotificationSettings(
				newNodeNotifications: current.autoDisabledForEvent ? true : current.newNodeNotifications,
				autoDisabledForEvent: false,
				userOverrideForEvent: false
			)
		}

		guard !current.userOverrideForEvent,
			  current.newNodeNotifications,
			  !current.autoDisabledForEvent else {
			return current
		}
		return EventFirmwareNotificationSettings(
			newNodeNotifications: false,
			autoDisabledForEvent: true,
			userOverrideForEvent: false
		)
	}
}
