//
//  NRFDFUSheet.swift
//  Meshtastic
//
//  Created by Jake Bordens on 12/11/25.
//

import SwiftUI
import OSLog

struct NRFDFUSheet: View {
	@Environment(\.dismiss) var dismiss
	@EnvironmentObject var accessoryManager: AccessoryManager
	@StateObject private var dfuViewModel = DFUViewModel()
	/// Held so closing the sheet while it's still reaching the radio cancels the start.
	@State private var startTask: Task<Void, Never>?

	let firmwareToFlash: URL
	/// Set when the radio's bootloader may not take a Bluetooth update.
	var bootloaderAdvice: BootloaderAdvice?
	/// The board's PlatformIO target, for opening the bootloader upgrade.
	var platformioTarget: String?

	@State private var showBootloaderUpgrade = false

	var body: some View {
		FirmwareUpdateView(
			stage: stage,
			progress: dfuViewModel.progress,
			detail: dfuViewModel.statusMessage,
			isStartDisabled: !(accessoryManager.activeConnection?.connection is BLEConnection),
			onStart: { startTask = Task { await startUpdate() } },
			onRetry: {
				if dfuViewModel.canRetry {
					accessoryManager.otaInProgress = true
					accessoryManager.shouldAutomaticallyConnectToPreferredPeripheralAfterError = false
					accessoryManager.stopDiscovery()
					dfuViewModel.retry()
				} else {
					startTask = Task { await startUpdate() }
				}
			},
			onDismiss: {
				if stage.isUnderWay {
					Task { await stopUpdate() }
				} else {
					dismiss()
				}
			},
			readyNotice: bootloaderAdvice.map(FirmwareUpdateCallout.before),
			// Only blame the bootloader when it isn't known to be current.
			failureNotice: dfuViewModel.failedBeforeTransfer && bootloaderAdvice != nil ? .didNotEnterUpdateMode : nil,
			onUpgradeBootloader: bootloaderAdvice != nil && platformioTarget != nil ? { showBootloaderUpgrade = true } : nil
		)
		.hostedSheet(isPresented: $showBootloaderUpgrade) {
			if let platformioTarget {
				BootloaderUpgradeView(platformioTarget: platformioTarget)
			}
		}
		.onDisappear {
			startTask?.cancel()
			startTask = nil
			if accessoryManager.otaInProgress {
				restoreDiscovery()
			}
		}
	}

	private var stage: FirmwareUpdateStage {
		switch dfuViewModel.state {
		case .idle:
			return .ready
		case .starting:
			return .preparing
		case .uploading:
			if dfuViewModel.isRestarting { return .restarting }
			// The library reports uploading from the moment it starts, before the radio has
			// restarted into its bootloader; nothing has gone across until progress moves.
			return dfuViewModel.progress > 0 ? .sending : .preparing
		case .success:
			return .done
		case .error:
			return .failed
		}
	}

	private func startUpdate() async {
		guard let connection = accessoryManager.activeConnection?.connection as? BLEConnection else {
			Logger.services.error("NRF DFU: no active BLE connection, cannot start")
			return
		}
		let peripheral = await connection.peripheral
		// Closed while reaching the radio: don't claim it or start an update nobody can see.
		guard !Task.isCancelled else {
			Logger.services.info("NRF DFU: start cancelled, the sheet was closed")
			return
		}
		// The DFU library reboots the radio into the bootloader and reconnects to it on its
		// own. Stop scanning and auto-connect first or the app grabs the device out from under it.
		accessoryManager.otaInProgress = true
		accessoryManager.shouldAutomaticallyConnectToPreferredPeripheralAfterError = false
		accessoryManager.stopDiscovery()
		Logger.services.info("NRF DFU: handing the radio to the DFU library")
		dfuViewModel.startDFU(peripheral: peripheral, zipFileUrl: firmwareToFlash)
	}

	/// Abort, then wait for the library to confirm before handing the radio back: restarting
	/// discovery while NordicDFU still owns the peripheral lets auto-connect grab it out from
	/// under the abort. Bounded, because an abort that never confirms must not leave the app
	/// unable to find the radio again.
	private func stopUpdate() async {
		dfuViewModel.abort()
		let deadline = Date().addingTimeInterval(3)
		while !dfuViewModel.didAbort && Date() < deadline {
			try? await Task.sleep(for: .milliseconds(100))
		}
		if !dfuViewModel.didAbort {
			Logger.services.error("NRF DFU: abort was not confirmed, handing the radio back anyway")
		}
		if accessoryManager.otaInProgress {
			restoreDiscovery()
		}
		dismiss()
	}

	/// Give the radio back to the app once DFU is finished: restart discovery and
	/// let auto-connect pick the device up when it reboots into the new firmware.
	private func restoreDiscovery() {
		Logger.services.info("NRF DFU: restoring discovery")
		accessoryManager.otaInProgress = false
		accessoryManager.userRequestedConnectionCancellation = false
		accessoryManager.shouldAutomaticallyConnectToPreferredPeripheralAfterError = true
		accessoryManager.startDiscovery()
	}
}

#Preview {
	NRFDFUSheet(firmwareToFlash: URL(fileURLWithPath: "/tmp/firmware-nrf52840.zip"))
		.environmentObject(AccessoryManager.shared)
}
