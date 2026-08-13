import Foundation
import Testing

@testable import Meshtastic

@Suite("Firmware update notification policy")
struct FirmwareUpdateNotificationPolicyTests {

	@Test func installMethodUsesAppOTAOnlyForArchitecturesHandledByTheApp() {
		#expect(FirmwareUpdateNotificationPolicy.installMethod(architecture: "esp32") == .appOTA)
		#expect(FirmwareUpdateNotificationPolicy.installMethod(architecture: "esp32-s3") == .appOTA)
		#expect(FirmwareUpdateNotificationPolicy.installMethod(architecture: "nrf52840") == .appOTA)
		#expect(FirmwareUpdateNotificationPolicy.installMethod(architecture: "rp2040") == .flasher)
		#expect(FirmwareUpdateNotificationPolicy.installMethod(architecture: nil) == .flasher)
		#expect(FirmwareUpdateNotificationPolicy.installMethod(architecture: "unknown") == .flasher)
	}

	@Test func normalizedVersionDropsLeadingVAndBuildHash() {
		#expect(FirmwareUpdateNotificationPolicy.normalizedVersion("v2.8.0.ad132e9") == "2.8.0")
		#expect(FirmwareUpdateNotificationPolicy.normalizedVersion("2.7.26.54e0d8d") == "2.7.26")
		#expect(FirmwareUpdateNotificationPolicy.normalizedVersion("2.8.0") == "2.8.0")
		#expect(FirmwareUpdateNotificationPolicy.normalizedVersion("  v2.8.0\n") == "2.8.0")
	}

	@Test func updateAvailableWhenCurrentVersionIsOlderThanLatestStable() {
		#expect(FirmwareUpdateNotificationPolicy.isUpdateAvailable(current: "2.7.26.54e0d8d", latestStable: "v2.8.0"))
		#expect(FirmwareUpdateNotificationPolicy.isUpdateAvailable(current: "2.8.0", latestStable: "v2.8.0") == false)
		#expect(FirmwareUpdateNotificationPolicy.isUpdateAvailable(current: "2.9.0", latestStable: "v2.8.0") == false)
	}

	@Test func notificationKeyIncludesNodeTargetAndStableVersion() {
		let key = FirmwareUpdateNotificationPolicy.notificationKey(
			nodeNum: 0x1234,
			platformioTarget: "tbeam-s3-core",
			latestStableVersion: "v2.8.0"
		)

		#expect(key == "firmware-update-notified:4660:tbeam-s3-core:2.8.0")
	}

	@Test func shouldNotifyOnlyWhenBehindAndNotAlreadyNotified() {
		let key = FirmwareUpdateNotificationPolicy.notificationKey(
			nodeNum: 0x1234,
			platformioTarget: "tbeam-s3-core",
			latestStableVersion: "v2.8.0"
		)

		#expect(FirmwareUpdateNotificationPolicy.shouldNotify(
			nodeNum: 0x1234,
			platformioTarget: "tbeam-s3-core",
			currentVersion: "2.7.26.54e0d8d",
			latestStableVersion: "v2.8.0",
			alreadyNotified: []
		))
		#expect(FirmwareUpdateNotificationPolicy.shouldNotify(
			nodeNum: 0x1234,
			platformioTarget: "tbeam-s3-core",
			currentVersion: "2.7.26.54e0d8d",
			latestStableVersion: "v2.8.0",
			alreadyNotified: [key]
		) == false)
		#expect(FirmwareUpdateNotificationPolicy.shouldNotify(
			nodeNum: 0x1234,
			platformioTarget: "tbeam-s3-core",
			currentVersion: "2.8.0",
			latestStableVersion: "v2.8.0",
			alreadyNotified: []
		) == false)
	}

	@Test func userDefaultsStorageSuppressesRepeatButAllowsNewStableVersion() {
		UserDefaults.firmwareUpdateNotificationKeys = []
		defer { UserDefaults.firmwareUpdateNotificationKeys = [] }

		let firstKey = FirmwareUpdateNotificationPolicy.notificationKey(
			nodeNum: 0x1234,
			platformioTarget: "tbeam-s3-core",
			latestStableVersion: "v2.8.0"
		)
		UserDefaults.recordFirmwareUpdateNotificationKey(firstKey)

		#expect(FirmwareUpdateNotificationPolicy.shouldNotify(
			nodeNum: 0x1234,
			platformioTarget: "tbeam-s3-core",
			currentVersion: "2.7.26",
			latestStableVersion: "v2.8.0",
			alreadyNotified: UserDefaults.firmwareUpdateNotificationKeySet
		) == false)
		#expect(FirmwareUpdateNotificationPolicy.shouldNotify(
			nodeNum: 0x1234,
			platformioTarget: "tbeam-s3-core",
			currentVersion: "2.7.26",
			latestStableVersion: "v2.8.1",
			alreadyNotified: UserDefaults.firmwareUpdateNotificationKeySet
		))
	}
}
