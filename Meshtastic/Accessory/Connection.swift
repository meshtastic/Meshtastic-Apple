//
//  Connection.swift
//  Meshtastic
//
//  Created by Jake Bordens on 7/10/25.
//

import Foundation
import MeshtasticProtobufs

protocol Connection: Actor {
	var type: TransportType { get }
	
	var isConnected: Bool { get }
	func send(_ data: ToRadio) async throws
	func connect() async throws -> AsyncStream<ConnectionEvent>
	func disconnect(withError: Error?, shouldReconnect: Bool) async throws
	func drainPendingPackets() async throws
	func startDrainPendingPackets() throws
	
	func appDidEnterBackground()
	func appDidBecomeActive()
}

enum ConnectionEvent {
	case data(FromRadio)
	case logMessage(String)
	case rssiUpdate(Int)
	case error(Error)
	case errorWithoutReconnect(Error)
	case disconnected(shouldReconnect: Bool)
}

enum ConnectionState: Equatable {
	case disconnected
	case connecting
	case connected
}

enum ConnectionError: Error, LocalizedError {
	case ioError(String)
}
