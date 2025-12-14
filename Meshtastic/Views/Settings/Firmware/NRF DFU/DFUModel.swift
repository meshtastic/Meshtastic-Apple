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
}

class DFUViewModel: NSObject, ObservableObject {
    // MARK: - Published Properties (UI Binding)
    @Published var progress: Double = 0.0
    @Published var state: DFUUpdateState = .idle
    @Published var statusMessage: String = "Ready"
	@Published var rotatingMessage: String = ""
	
	var lastRotatingMessageUpdate = Date.distantPast
	var rotatingMessageIndex = -1
	let rotatingMessages = ["Hang tight, Garth is working on it.", "Keep your device close to the phone or Ben will be angry.", "Dan says, \"Do not close the app!\""]
	
    // MARK: - DFU Controller
    private var dfuController: DFUServiceController?
    
    // MARK: - Start DFU
    /// Call this function from your SwiftUI View
    /// - Parameters:
    ///   - peripheral: The CoreBluetooth device you are connected to
    ///   - zipFileUrl: The local URL of the Firmware Zip file
    func startDFU(peripheral: CBPeripheral, zipFileUrl: URL) {
        
        guard let firmware = try? DFUFirmware(urlToZipFile: zipFileUrl) else {
            self.state = .error("Invalid Zip File")
            return
        }
        
        // Setup the initiator
        let initiator = DFUServiceInitiator(queue: .main, delegateQueue: .main)
	
		initiator.forceScanningForNewAddressInLegacyDfu = true
		initiator.dataObjectPreparationDelay = 0.4
		initiator.enableUnsafeExperimentalButtonlessServiceInSecureDfu = true
		initiator.forceDfu = false
		initiator.disableResume = true
		initiator.packetReceiptNotificationParameter = 8
		
		// Set self as delegate
        initiator.delegate = self
        initiator.progressDelegate = self
        initiator.logger = self // Optional: For debugging
        
        // Start the process
        self.state = .uploading
		self.dfuController = initiator.with(firmware: firmware)
			.start(target: peripheral)
    }
    
    // Abort function
    func abort() {
        _ = dfuController?.abort()
    }
}

// MARK: - DFU Service Delegate (State Changes)
extension DFUViewModel: DFUServiceDelegate {
	
    func dfuStateDidChange(to state: DFUState) {
        // Map Nordic's internal state to our UI string
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
        default:
            self.statusMessage = state.description
        }
		Logger.services.info("NRF DFU State changed: \(state.description)")
    }
    
    func dfuError(_ error: DFUError, didOccurWithMessage message: String) {
        self.state = .error(message)
        self.statusMessage = "Error: \(message)"
    }
}

// MARK: - DFU Progress Delegate (Progress Bar)
extension DFUViewModel: DFUProgressDelegate {
    func dfuProgressDidChange(for part: Int, outOf totalParts: Int, to progress: Int, currentSpeedBytesPerSecond: Double, avgSpeedBytesPerSecond: Double) {
        // Convert 0-100 Int to 0.0-1.0 Double for SwiftUI ProgressView
        self.progress = Double(progress) / 100.0
		
		if lastRotatingMessageUpdate.timeIntervalSinceNow < -10 {
			// Last message was 10 seconds ago. This insures messages don't rotate too fast
			lastRotatingMessageUpdate = Date()
			self.rotatingMessageIndex = (self.rotatingMessageIndex + 1) % self.rotatingMessages.count
			self.rotatingMessage = self.rotatingMessages[self.rotatingMessageIndex]
		}
    }
}

// MARK: - Logger Delegate (Optional)
extension DFUViewModel: LoggerDelegate {
    func logWith(_ level: LogLevel, message: String) {
		Logger.services.info("NRF DFU Log: \(message)")
    }
}
