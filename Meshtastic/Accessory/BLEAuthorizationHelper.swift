//
//  BluetoothAuthorizationHelper.swift
//  Meshtastic
//
//  Created by Jake Bordens on 7/31/25.
//

import Foundation
import CoreBluetooth

/// A helper class to manage the CoreBluetooth delegate callbacks.
/// This is necessary because CBCentralManagerDelegate requires an NSObject.
class BluetoothAuthorizationHelper: NSObject, CBCentralManagerDelegate {
	
	/// The continuation to resume when the authorization status is determined.
	private var continuation: CheckedContinuation<Bool, Never>?
	
	/// The CoreBluetooth central manager.
	private var centralManager: CBCentralManager?

	/// Requests Bluetooth authorization and awaits the user's response.
	func requestAuthorization() async -> Bool {
		await withCheckedContinuation { continuation in
			self.continuation = continuation
			
			// Initializing the CBCentralManager triggers the permission prompt if needed.
			// The delegate method will be called with the result.
			// The manager must be retained for the delegate callbacks to occur.
			self.centralManager = CBCentralManager(delegate: self, queue: nil)
		}
	}

	/// The delegate method that receives state updates from the CBCentralManager.
	func centralManagerDidUpdateState(_ central: CBCentralManager) {
		switch central.state {
		case .poweredOn:
			// Success: User has granted permission and Bluetooth is on.
			continuation?.resume(returning: true)
		
		case .unauthorized:
			// Failure: User has explicitly denied permission.
			continuation?.resume(returning: false)
			
		case .poweredOff:
			// Failure: User needs to turn on Bluetooth in Settings.
			// For the purpose of this function, the app cannot use BLE.
			continuation?.resume(returning: false)
			
		case .unsupported:
			// Failure: This device does not support Bluetooth Low Energy.
			continuation?.resume(returning: false)

		case .resetting, .unknown:
			// The state is temporary or unknown. We wait for the next state update.
			// Do nothing and let the continuation live.
			break

		@unknown default:
			// Handle any future cases gracefully.
			continuation?.resume(returning: false)
		}
		
		// Clean up to prevent resuming more than once.
		self.continuation = nil
	}
	
	/// A static function to provide a clean call site.
	static func requestBluetoothAuthorization() async -> Bool {
		// Create an instance of the helper class.
		// The instance will be retained until the async operation completes.
		let authorizer = BluetoothAuthorizationHelper()
		return await authorizer.requestAuthorization()
	}

}
