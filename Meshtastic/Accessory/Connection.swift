//
//  Connection.swift
//  Meshtastic
//
//  Created by Jake Bordens on 7/10/25.
//

import Foundation
import MeshtasticProtobufs

protocol RSSIDelegate: AnyObject {
	func didUpdateRSSI(_ rssi: Int, for deviceId: UUID)
}

protocol PacketDelegate: AnyObject {
	func didReceive(result: Result<FromRadio, Error>)
	func didReceiveLog(message: String)
}

protocol Connection {
	var isConnected: Bool { get }
	func send(_ data: ToRadio) async throws
	var packetDelegate: PacketDelegate? { get set }
	func disconnect() async throws
	func drainPendingPackets() async throws
	func startDrainPendingPackets() throws
}

protocol WirelessConnection: Connection {
	var rssiDelegate: RSSIDelegate? { get set }
}

enum ConnectionState: Equatable {
	case disconnected
	case connecting
	case connected
}

enum ConnectionError: Error {
	case ioError(String)
}
