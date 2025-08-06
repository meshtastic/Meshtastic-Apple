//
//  Connection.swift
//  Meshtastic
//
//  Created by Jake Bordens on 7/10/25.
//

import Foundation
import MeshtasticProtobufs

protocol Connection: Actor {
	var isConnected: Bool { get }
	func send(_ data: ToRadio) async throws
	func connect() async throws -> AsyncStream<ConnectionEvent>
	func disconnect(userInitiated: Bool) async throws  // If error is not provided, assume user-initiated disconnect
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
	case userDisconnected
}

enum ConnectionState: Equatable {
	case disconnected
	case connecting
	case connected
}

enum ConnectionError: Error, LocalizedError {
	case ioError(String)
}
