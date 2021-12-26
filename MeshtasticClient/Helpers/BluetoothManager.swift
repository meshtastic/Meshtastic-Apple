//
//  BluetoothManager.swift
//  MeshtasticClient
//
//  Created by Garth Vander Houwen on 12/1/21.
//

import Combine
import CoreBluetooth

final class BluetoothManager: NSObject {

	private var centralManager: CBCentralManager!

	var stateSubject: PassthroughSubject<CBManagerState, Never> = .init()
	var peripheralSubject: PassthroughSubject<CBPeripheral, Never> = .init()

	func start() {
		centralManager = .init(delegate: self, queue: .main)
	}

	func connect(_ peripheral: CBPeripheral) {
		centralManager.stopScan()
		peripheral.delegate = self
		centralManager.connect(peripheral)
	}
}
