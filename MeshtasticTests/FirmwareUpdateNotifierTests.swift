import Foundation
import Testing

@testable import Meshtastic

@Suite("Firmware update notifier")
struct FirmwareUpdateNotifierTests {

	@Test func notificationPayloadRoutesToFirmwareUpdates() {
		let notification = FirmwareUpdateNotifier.notification(for: FirmwareUpdateNotificationCandidate(
			nodeNum: 0x1234,
			deviceName: "Meshtastic c058",
			platformioTarget: "tbeam-s3-core",
			installMethod: .appOTA,
			currentVersion: "2.7.26.54e0d8d",
			latestStableVersion: "v2.8.0"
		),
			alreadyNotified: []
		)

		#expect(notification?.id == "firmware-update-notified:4660:tbeam-s3-core:2.8.0")
		#expect(notification?.title == "Firmware update available")
		#expect(notification?.subtitle == "Meshtastic c058")
		#expect(notification?.content.contains("2.7.26") == true)
		#expect(notification?.content.contains("2.8.0") == true)
		#expect(notification?.content.contains("Firmware Updates") == true)
		#expect(notification?.target == "firmwareUpdates")
		#expect(notification?.path == "meshtastic:///settings/firmwareUpdates")
	}

	@Test func notificationPayloadUsesFlasherCopyForHardwareWithoutAppOTA() {
		let notification = FirmwareUpdateNotifier.notification(for: FirmwareUpdateNotificationCandidate(
			nodeNum: 0x1234,
			deviceName: "RP2040 node",
			platformioTarget: "rak11310",
			installMethod: .flasher,
			currentVersion: "2.7.26",
			latestStableVersion: "v2.8.0"
		),
			alreadyNotified: []
		)

		#expect(notification?.id == "firmware-update-notified:4660:rak11310:2.8.0")
		#expect(notification?.content.contains("Meshtastic Flasher") == true)
		#expect(notification?.content.contains("Firmware Updates") == false)
		#expect(notification?.target == "flasher")
		#expect(notification?.path == "https://flasher.meshtastic.org")
	}

	@Test func notificationReturnsNilWhenMetadataIsMissing() {
		#expect(FirmwareUpdateNotifier.notification(for: FirmwareUpdateNotificationCandidate(
			nodeNum: 0x1234,
			deviceName: "Meshtastic c058",
			platformioTarget: nil,
			installMethod: .appOTA,
			currentVersion: "2.7.26",
			latestStableVersion: "v2.8.0"
		),
			alreadyNotified: []
		) == nil)
		#expect(FirmwareUpdateNotifier.notification(for: FirmwareUpdateNotificationCandidate(
			nodeNum: 0x1234,
			deviceName: "Meshtastic c058",
			platformioTarget: "tbeam-s3-core",
			installMethod: .appOTA,
			currentVersion: nil,
			latestStableVersion: "v2.8.0"
		),
			alreadyNotified: []
		) == nil)
		#expect(FirmwareUpdateNotifier.notification(for: FirmwareUpdateNotificationCandidate(
			nodeNum: 0x1234,
			deviceName: "Meshtastic c058",
			platformioTarget: "tbeam-s3-core",
			installMethod: .appOTA,
			currentVersion: "2.7.26",
			latestStableVersion: nil
		),
			alreadyNotified: []
		) == nil)
	}

	@Test func notificationReturnsNilWhenAlreadyNotified() {
		let key = FirmwareUpdateNotificationPolicy.notificationKey(
			nodeNum: 0x1234,
			platformioTarget: "tbeam-s3-core",
			latestStableVersion: "v2.8.0"
		)

		let notification = FirmwareUpdateNotifier.notification(for: FirmwareUpdateNotificationCandidate(
			nodeNum: 0x1234,
			deviceName: "Meshtastic c058",
			platformioTarget: "tbeam-s3-core",
			installMethod: .appOTA,
			currentVersion: "2.7.26",
			latestStableVersion: "v2.8.0"
		),
			alreadyNotified: [key]
		)

		#expect(notification == nil)
	}

	@Test func candidateUsesMetadataVersionBeforeConnectedFallback() {
		let metadataCandidate = FirmwareUpdateNotifier.candidate(from: FirmwareUpdateNotificationSource(
			nodeNum: 0x1234,
			deviceName: "Meshtastic c058",
			platformioTarget: "tbeam-s3-core",
			architecture: "esp32-s3",
			metadataVersion: "2.7.25",
			connectedVersion: "2.7.26.54e0d8d",
			latestStableVersion: "v2.8.0"
		))
		let fallbackCandidate = FirmwareUpdateNotifier.candidate(from: FirmwareUpdateNotificationSource(
			nodeNum: 0x1234,
			deviceName: "Meshtastic c058",
			platformioTarget: "tbeam-s3-core",
			architecture: "esp32-s3",
			metadataVersion: nil,
			connectedVersion: "2.7.26.54e0d8d",
			latestStableVersion: "v2.8.0"
		))

		#expect(metadataCandidate.currentVersion == "2.7.25")
		#expect(metadataCandidate.installMethod == .appOTA)
		#expect(fallbackCandidate.currentVersion == "2.7.26.54e0d8d")
	}

	@Test func noticeContentMatchesInstallMethod() {
		let appOTANotice = FirmwareUpdateNotifier.notice(for: FirmwareUpdateNotificationCandidate(
			nodeNum: 0x1234,
			deviceName: "Meshtastic c058",
			platformioTarget: "tbeam-s3-core",
			installMethod: .appOTA,
			currentVersion: "2.7.26.54e0d8d",
			latestStableVersion: "v2.8.0"
		))
		let flasherNotice = FirmwareUpdateNotifier.notice(for: FirmwareUpdateNotificationCandidate(
			nodeNum: 0x1234,
			deviceName: "RP2040 node",
			platformioTarget: "rak11310",
			installMethod: .flasher,
			currentVersion: "2.7.26.54e0d8d",
			latestStableVersion: "v2.8.0"
		))

		#expect(appOTANotice?.connectMessage.contains("Open Firmware Updates") == true)
		#expect(flasherNotice?.connectMessage.contains("Meshtastic Flasher") == true)
		#expect(appOTANotice?.actionPath == "meshtastic:///settings/firmwareUpdates")
		#expect(flasherNotice?.actionPath == "https://flasher.meshtastic.org")
		#expect(appOTANotice?.accessibilityHint == "Opens Firmware Updates")
		#expect(flasherNotice?.accessibilityHint == "Opens Meshtastic Flasher")
	}

	@Test func updateNudgeUsesAnUpdateAffordance() {
		#expect(FirmwareUpdateNotice.symbolName == "arrow.triangle.2.circlepath")
	}
}
