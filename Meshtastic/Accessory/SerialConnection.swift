//
//  SerialConnection.swift
//  Meshtastic
//
//  Created by Jake Bordens on 7/22/25.
//

import Foundation
import OSLog
import MeshtasticProtobufs
import Darwin.POSIX.termios
import Dispatch

actor SerialConnection: Connection {
	func drainPendingPackets() async throws {
		//
	}

	func startDrainPendingPackets() throws {
		//
	}

	private let path: String
	private var fd: Int32 = -1
	private var isOpen: Bool = false
	private var dispatchIO: DispatchIO?
	private var readerTask: Task<Void, Never>?

	var isConnected: Bool { isOpen }

	init(path: String) {
		self.path = path
	}

	private func startReader() {
		readerTask = Task { @MainActor in
			guard let dispatchIO = dispatchIO else { return }
			let bufferSize = 1024
			while await self.isOpen && !Task.isCancelled {
				try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
					dispatchIO.read(offset: 0, length: bufferSize, queue: .global()) { done, data, error in
						if error != 0 {
							continuation.resume(throwing: POSIXError(POSIXErrorCode(rawValue: error)!))
							return
						}

						guard let data = data, !data.isEmpty else {
							if done != 0 {
								continuation.resume()
							}
							return
						}

						var bytes = [UInt8](repeating: 0, count: data.count)
						data.copyBytes(to: &bytes, count: data.count)

						do {
							try self.processIncoming(bytes)
							continuation.resume()
						} catch {
							continuation.resume(throwing: error)
						}
					}
				}
			}
		}
	}

	private func processIncoming(_ bytes: [UInt8]) throws {
		var index = 0
		while index < bytes.count {
			// Scan for magic bytes
			if index + 1 < bytes.count && bytes[index] == 0x94 && bytes[index + 1] == 0xc3 {
				index += 2
				// Read length
				if index + 1 < bytes.count {
					let length = UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1])
					index += 2

					// Read payload
					if index + Int(length) <= bytes.count {
						let payload = Data(bytes[index ..< index + Int(length)])
						if let fromRadio = try? FromRadio(serializedBytes: payload) {
							await packetStream?.yield(fromRadio)
						} else {
							await packetStream?.finish()
						}
						index += Int(length)
					} else {
						// Not enough data, wait for more
						break
					}
				} else {
					// Not enough data, wait for more
					break
				}
			} else {
				index += 1 // Skip byte until magic found
			}
		}
	}

	func send(_ data: ToRadio) async throws {
		guard isOpen else {
			throw AccessoryError.ioFailed("Not connected")
		}
		let serialized = try data.serializedData()
		var buffer = Data([0x94, 0xc3])
		var len: UInt16 = UInt16(serialized.count).bigEndian
		buffer.append(Data(bytes: &len, count: 2))
		buffer.append(serialized)

		let written = buffer.withUnsafeBytes { ptr in
			Darwin.write(fd, ptr.baseAddress, buffer.count)
		}
		if written != buffer.count {
			throw POSIXError(POSIXErrorCode(rawValue: errno)!)
		}
	}

	func disconnect() async throws {
		if isOpen {
			readerTask?.cancel()
			dispatchIO?.close(flags: .stop)
			close(fd)
			isOpen = false
			packetStream?.finish()
			packetStream = nil
		}
	}

	private var packetStream: AsyncStream<MeshtasticProtobufs.FromRadio>.Continuation?

	private func getPacketStream() -> AsyncStream<MeshtasticProtobufs.FromRadio> {
		AsyncStream<MeshtasticProtobufs.FromRadio> { continuation in
			self.packetStream = continuation
			continuation.onTermination = { _ in
				Task { try await self.disconnect() }
			}
		}
	}

	func connect() async throws -> (AsyncStream<FromRadio>, AsyncStream<String>?) {
		fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
		if fd == -1 {
			throw POSIXError(POSIXErrorCode(rawValue: errno)!)
		}

		var term: termios = termios()
		if tcgetattr(fd, &term) == -1 {
			close(fd)
			throw POSIXError(POSIXErrorCode(rawValue: errno)!)
		}

		cfmakeraw(&term)
		term.c_cflag |= UInt((CS8 | CREAD | CLOCAL))
		if cfsetspeed(&term, 921600) == -1 {
			close(fd)
			throw POSIXError(POSIXErrorCode(rawValue: errno)!)
		}

		if tcsetattr(fd, TCSANOW, &term) == -1 {
			close(fd)
			throw POSIXError(POSIXErrorCode(rawValue: errno)!)
		}

		// Set up DispatchIO
		let io = DispatchIO(type: .stream, fileDescriptor: fd, queue: .global()) { error in
			if error != 0 {
				Logger.transport.error("[Serial] DispatchIO closed with error: \(error)")
			}
		}
		io.setLimit(highWater: 1024)
		dispatchIO = io

		isOpen = true
		startReader()

		return (getPacketStream(), nil)
	}
}
