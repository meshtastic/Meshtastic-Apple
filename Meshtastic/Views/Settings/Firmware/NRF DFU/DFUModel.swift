//
//  to.swift
//  Meshtastic
//
//  Created by jake on 12/2/25.
//

import Foundation
import NordicDFU
import CoreBluetooth
import OSLog
import UIKit

// A simple enum to track the UI state
enum DFUUpdateState: Equatable {
    case idle
	case starting
    case uploading
    case success
    case error(String)

	var isError: Bool {
		if case .error = self { return true }
		return false
	}
}

/// Whether a dropped BLE DFU starts over. From Meshtastic nRF52 Bootloader 2.6.0 the bootloader
/// drops an unfinished transfer on disconnect and accepts a fresh START on the next connection.
/// An older one keeps the stale session and answers START with invalid state, which NordicDFU
/// reports as `.remoteLegacyDFUInvalidState`, not a lost link, so it ends the attempts.
enum DFURestartPolicy {
	static let maxRestarts = 3
	static let delay: Duration = .seconds(2)

	static func shouldRestart(linkLost: Bool, bootloaderTargetKnown: Bool, restartsSoFar: Int) -> Bool {
		linkLost && bootloaderTargetKnown && restartsSoFar < maxRestarts
	}
}

/// The default selector, remembering which peripheral it picked so a restart can go straight
/// back to the bootloader, which may advertise at a different address from the application.
private final class BootloaderPeripheralSelector: DFUPeripheralSelector {
	private(set) var selectedIdentifier: UUID?

	override func select(_ peripheral: CBPeripheral, advertisementData: [String: AnyObject], RSSI: NSNumber, hint name: String? = nil) -> Bool {
		let selected = super.select(peripheral, advertisementData: advertisementData, RSSI: RSSI, hint: name)
		if selected {
			selectedIdentifier = peripheral.identifier
		}
		return selected
	}
}

class DFUViewModel: NSObject, ObservableObject {
    // MARK: - Published Properties (UI Binding)
    @Published var progress: Double = 0.0
    @Published var state: DFUUpdateState = .idle
    @Published var statusMessage: String = "Ready"
	/// Set when the library confirms an abort. Handing the radio back to the app before
	/// this lands restarts discovery while NordicDFU still owns the peripheral.
	@Published private(set) var didAbort = false
	@Published var rotatingMessage: String = ""
	
	var lastRotatingMessageUpdate = Date.distantPast
	var rotatingMessageIndex = -1
	var rotatingMessages: [String] {
		FirmwareUpdateTips.messages
	}
	
    // MARK: - DFU Controller
    private var dfuController: DFUServiceController?
	private var selector = BootloaderPeripheralSelector()
	private var zipFileUrl: URL?
	private var targetIdentifier: UUID?
	/// Set once START has been accepted. The bootloader has erased the application by then,
	/// so the peripheral last connected to is the bootloader.
	private var transferStarted = false
	private var restarts = 0
	private var restartTask: Task<Void, Never>?

    // MARK: - Start DFU
    /// Call this function from your SwiftUI View
    /// - Parameters:
    ///   - peripheral: The CoreBluetooth device you are connected to
    ///   - zipFileUrl: The local URL of the Firmware Zip file
    func startDFU(peripheral: CBPeripheral, zipFileUrl: URL) {
		self.zipFileUrl = zipFileUrl
		self.targetIdentifier = peripheral.identifier
		self.selector = BootloaderPeripheralSelector()
		self.transferStarted = false
		self.restarts = 0
        self.didAbort = false
        self.state = .uploading
		Logger.services.info("NRF DFU: starting on \(peripheral.identifier.uuidString, privacy: .public)")
		run(targetIdentifier: peripheral.identifier)
    }

	private func run(targetIdentifier: UUID) {
		guard let zipFileUrl, let firmware = try? DFUFirmware(urlToZipFile: zipFileUrl) else {
			Logger.services.error("NRF DFU: could not read the firmware zip")
			self.state = .error("Invalid Zip File")
			return
		}

		let initiator = DFUServiceInitiator(queue: .main, delegateQueue: .main)
		initiator.forceScanningForNewAddressInLegacyDfu = true
		initiator.dataObjectPreparationDelay = 0.4
		initiator.enableUnsafeExperimentalButtonlessServiceInSecureDfu = true
		initiator.forceDfu = false
		initiator.disableResume = true
		initiator.packetReceiptNotificationParameter = 8
		initiator.peripheralSelector = selector
		initiator.delegate = self
		initiator.progressDelegate = self
		initiator.logger = self

		self.dfuController = initiator.with(firmware: firmware)
			.start(targetWithIdentifier: targetIdentifier)
	}

	/// The peripheral to start over against: the bootloader the library scanned for after the
	/// buttonless jump, or the original target when the bootloader kept its address.
	private var bootloaderIdentifier: UUID? {
		selector.selectedIdentifier ?? (transferStarted ? targetIdentifier : nil)
	}

	/// Starts the update over from START after the link dropped. Runs at once rather than
	/// waiting on the user, since a board that still has a valid application leaves DFU after
	/// 6 minutes without activity.
	private func restart(after error: DFUError, message: String) -> Bool {
		let linkLost = error == .deviceDisconnected || error == .failedToConnect
		let bootloaderIdentifier = self.bootloaderIdentifier
		guard DFURestartPolicy.shouldRestart(linkLost: linkLost, bootloaderTargetKnown: bootloaderIdentifier != nil, restartsSoFar: restarts),
			  let bootloaderIdentifier else {
			return false
		}
		restarts += 1
		Logger.services.warning("NRF DFU: link lost (\(message, privacy: .public)), starting over, attempt \(self.restarts) of \(DFURestartPolicy.maxRestarts)")
		targetIdentifier = bootloaderIdentifier
		transferStarted = false
		progress = 0
		state = .starting
		statusMessage = "Reconnecting..."
		restartTask = Task { @MainActor [weak self] in
			try? await Task.sleep(for: DFURestartPolicy.delay)
			guard let self, !Task.isCancelled else { return }
			self.restartTask = nil
			self.run(targetIdentifier: bootloaderIdentifier)
		}
		return true
	}

    // Abort function
    func abort() {
		if let restartTask {
			// Between attempts there is no library session to abort.
			restartTask.cancel()
			self.restartTask = nil
			dfuStateDidChange(to: .aborted)
			return
		}
        _ = dfuController?.abort()
    }
}

// MARK: - DFU Service Delegate (State Changes)
extension DFUViewModel: DFUServiceDelegate {
	
    func dfuStateDidChange(to state: DFUState) {
		// delegateQueue is .main, so we're already on the main thread
		switch state {
		case .starting:
			UIApplication.shared.isIdleTimerDisabled = true
			self.rotatingMessage = "This can take a while. Please be patient."
			self.state = .starting
		case .completed:
			UIApplication.shared.isIdleTimerDisabled = false
			self.state = .success
			self.statusMessage = "Update Complete"
			self.rotatingMessage = "Firmware Update Successful!"
			self.progress = 1.0
		case .disconnecting:
			UIApplication.shared.isIdleTimerDisabled = false
			self.statusMessage = "Disconnecting..."
		case .aborted:
			UIApplication.shared.isIdleTimerDisabled = false
			self.state = .error("Aborted")
			self.statusMessage = "Update Aborted"
			self.didAbort = true
		case .uploading:
			self.transferStarted = true
			self.state = .uploading
			self.statusMessage = "Uploading..."
		default:
			self.statusMessage = state.description
		}
		Logger.services.info("NRF DFU State changed: \(state.description)")
    }
    
    func dfuError(_ error: DFUError, didOccurWithMessage message: String) {
		if restart(after: error, message: message) {
			return
		}
		self.state = .error(message)
		self.statusMessage = "Error: \(message)"
    }
}

// MARK: - DFU Progress Delegate (Progress Bar)
extension DFUViewModel: DFUProgressDelegate {
    func dfuProgressDidChange(for part: Int, outOf totalParts: Int, to progress: Int, currentSpeedBytesPerSecond: Double, avgSpeedBytesPerSecond: Double) {
		// Convert 0-100 Int to 0.0-1.0 Double for SwiftUI ProgressView
		self.progress = Double(progress) / 100.0
		
		if self.lastRotatingMessageUpdate.timeIntervalSinceNow < -10 {
			// Last message was 10 seconds ago. This ensures messages don't rotate too fast
			self.lastRotatingMessageUpdate = Date()
			self.rotatingMessageIndex = (self.rotatingMessageIndex + 1) % self.rotatingMessages.count
			self.rotatingMessage = self.rotatingMessages[self.rotatingMessageIndex]
		}
		Logger.services.info("NRF DFU Progress: \(progress)%")
	}
}

// MARK: - Logger Delegate (Optional)
extension DFUViewModel: LoggerDelegate {
    func logWith(_ level: LogLevel, message: String) {
		Logger.services.info("NRF DFU Log: \(message)")
    }
}
