//
//  Connection.swift
//  Meshtastic
//
//  Created by Jake Bordens on 7/10/25.
//

import Foundation
import MeshtasticProtobufs
import SwiftProtobuf

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

// MARK: - Shared FromRadio decode + encoding validation

/// Outcome of decoding one top-level `FromRadio` frame from raw transport bytes.
///
/// SwiftProtobuf validates UTF-8 while decoding and throws `BinaryDecodingError.invalidUTF8`
/// when a string field (e.g. a node's `long_name`) carries an invalid byte sequence. That
/// is a per-field content problem, not a transport problem, so it is surfaced separately
/// from genuine framing failures — see `FromRadioDecoder`.
enum FromRadioDecodeOutcome {
	/// Frame decoded cleanly; yield `.data(_)` to the `AccessoryManager`.
	case decoded(FromRadio)
	/// A string field failed UTF-8 validation. Skip this frame and keep reading; the
	/// error is carried for logging only.
	case skipInvalidUTF8(Error)
	/// Any other decode failure (truncation, malformed wire format, …): a genuine
	/// framing/stream problem, which transports may recover from by reconnecting.
	case failed(Error)
}

/// The single decode + encoding-validation path shared by every transport, so BLE, TCP,
/// and Serial handle a malformed string field identically instead of each rolling its own.
enum FromRadioDecoder {
	/// Decodes and validates one `FromRadio` frame. Pure — no actor state and no I/O — so
	/// it is safe to call synchronously from any transport actor and is directly unit-testable.
	static func classify(_ data: Data) -> FromRadioDecodeOutcome {
		do {
			return .decoded(try FromRadio(serializedBytes: data))
		} catch {
			return isInvalidUTF8(error) ? .skipInvalidUTF8(error) : .failed(error)
		}
	}

	/// True iff `error` is SwiftProtobuf's `.invalidUTF8` binary-decoding error.
	/// `BinaryDecodingError` has no associated values, so it is implicitly `Equatable`
	/// and `== .invalidUTF8` compiles via `Optional`'s conditional conformance.
	private static func isInvalidUTF8(_ error: Error) -> Bool {
		(error as? BinaryDecodingError) == .invalidUTF8
	}
}

enum ConnectionState: Equatable, Codable {
	case disconnected
	case connecting
	case connected
}

enum ConnectionError: Error, LocalizedError {
	case ioError(String)
}
