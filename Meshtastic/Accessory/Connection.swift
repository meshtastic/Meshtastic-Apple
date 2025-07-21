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
	func connect() async -> (AsyncStream<FromRadio>, AsyncStream<String>?)
	func disconnect() async throws
	func drainPendingPackets() async throws
	func startDrainPendingPackets() throws
}

protocol WirelessConnection: Connection {
	func getRSSIStream() async -> AsyncStream<Int>
}

enum ConnectionState: Equatable {
	case disconnected
	case connecting
	case connected
}

enum ConnectionError: Error {
	case ioError(String)
}
