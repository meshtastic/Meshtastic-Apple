//
//  ESP32OTAIntroSheet.swift
//  Meshtastic
//
//  Created by Jake Bordens on 12/12/25.
//

import SwiftUI
import OSLog

/// Entry point for updating an ESP32 radio from the phone. Goes straight to the shared update
/// screen for whichever way the radio is connected, or explains why the phone can't do it.
struct ESP32OTAIntroSheet: View {
	/// ESP32 OTA (BLE/WiFi) requires AdminMessage.OTAEvent with otaHash for authentication,
	/// added to Meshtastic firmware in 2.7.18.
	private let minimumOTAVersion = "2.7.18"

	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) var dismiss

	let binFileURL: URL

	/// The updater, once there is one. Both ESP32 updaters disconnect the app from the radio
	/// before the transfer, which would otherwise flip the live route to "unavailable" and tear
	/// the updater down mid-update, leaving the radio waiting in update mode.
	@State private var chosenRoute: Route?

	var body: some View {
		Group {
			content(for: chosenRoute ?? route)
		}
		.onAppear { lockInUpdater() }
		.onChange(of: route) { _, _ in lockInUpdater() }
	}

	@ViewBuilder
	private func content(for route: Route) -> some View {
		switch route {
		case .wifi:
			ESP32WifiOTASheet(binFileURL: binFileURL, host: debugHost, onUpdateComplete: { dismiss() })
				.trackScreen(.esp32WiFiUpdate)
				.onAppear { Logger.services.info("📡 [ESP32 OTA] Wi-Fi path") }
		case .ble:
			ESP32BLEOTASheet(binFileURL: binFileURL, onUpdateComplete: { dismiss() })
				.trackScreen(.esp32BLEUpdate)
				.onAppear { Logger.services.info("📡 [ESP32 OTA] BLE path") }
		case .unavailable(let reason):
			FirmwareUpdateView(
				stage: .unavailable(reason: reason),
				progress: 0,
				onStart: {},
				onRetry: {},
				onDismiss: { dismiss() }
			)
		}
	}

	private enum Route: Equatable {
		case wifi
		case ble
		case unavailable(String)
	}

	/// Keeps the route live until an updater is chosen, then holds it for the rest of the session.
	private func lockInUpdater() {
		guard chosenRoute == nil else { return }
		switch route {
		case .wifi, .ble: chosenRoute = route
		case .unavailable: break
		}
	}

	private var route: Route {
		guard accessoryManager.checkIsVersionSupported(forVersion: minimumOTAVersion) else {
			return .unavailable(String(localized: "This radio's firmware is too old to update from your phone. Update it once from a computer with the Web Flasher, and later updates can come from here.", comment: "Shown when an ESP32 radio's firmware predates phone updates"))
		}
		switch accessoryManager.activeConnection?.connection {
		case is TCPConnection:
			return .wifi
		case is BLEConnection:
			return .ble
		#if targetEnvironment(macCatalyst)
		// A Wi-Fi update needs the radio's IP address, which a serial connection doesn't give.
		// Only a DEBUG build with the IP override set can use one.
		case is SerialConnection where debugHost != nil:
			return .wifi
		#endif
		default:
			Logger.services.info("📡 [ESP32 OTA] No active connection — no OTA path available")
			return .unavailable(String(localized: "Connect to your radio over Bluetooth or Wi-Fi to update it from your phone, or update it from a computer with the Web Flasher.", comment: "Shown when the phone has no Bluetooth or Wi-Fi connection to an ESP32 radio it could update"))
		}
	}

	/// DEBUG only: launch with `-esp32OTADebugHost <ip>` to send a Wi-Fi update to that address.
	private var debugHost: String? {
		#if DEBUG
		if let host = UserDefaults.standard.string(forKey: "esp32OTADebugHost"), !host.isEmpty {
			return host
		}
		#endif
		return nil
	}
}

#Preview {
	ESP32OTAIntroSheet(binFileURL: URL(fileURLWithPath: "/tmp/firmware-esp32-s3-2.5.18.bin"))
		.environmentObject(AccessoryManager.shared)
}
