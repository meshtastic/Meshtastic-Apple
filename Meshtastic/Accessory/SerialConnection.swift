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

actor SerialConnection: Connection {
	private let path: String
	private var fd: Int32 = -1
	private var isOpen: Bool = false
	private var readerTask: Task<Void, Never>?

	var isConnected: Bool { isOpen }

	init(path: String) {
		self.path = path
	}

	private func waitForMagicBytes() throws -> Bool {
		let startOfFrame: [UInt8] = [0x94, 0xc3]
		var waitingOnByte = 0
		while isOpen {
			var byte: UInt8 = 0
			let bytesRead = read(fd, &byte, 1)
			if bytesRead <= 0 {
				continue
			}
			if byte == startOfFrame[waitingOnByte] {
				waitingOnByte += 1
			} else {
				waitingOnByte = 0
			}
			if waitingOnByte > 1 {
				return true
			}
		}
		return false
	}

	private func readInteger() throws -> UInt16? {
		var buffer = [UInt8](repeating: 0, count: 2)
		let bytesRead = read(fd, &buffer, 2)
		if bytesRead == 2 {
			return buffer.withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
		}
		return nil
	}

	private func startReader() {
		readerTask = Task { @MainActor in
			while await self.isOpen {
				do {
					if try await self.waitForMagicBytes() == false {
						Logger.transport.debug("[Serial] startReader: EOF while waiting for magic bytes")
						continue
					}
					if let length = try await self.readInteger() {
						let payload = try await self.receiveData(exact: Int(length))
						if let fromRadio = try? FromRadio(serializedBytes: payload) {
							await self.packetStream?.yield(fromRadio)
						} else {
							await self.packetStream?.finish()
						}
					} else {
						Logger.transport.debug("[Serial] startReader: EOF while waiting for length")
					}
				} catch {
					Logger.transport.error("[Serial] startReader: Error reading from Serial: \(error)")
					await self.packetStream?.finish()
					break
				}
			}
		}
	}

	private func receiveData(exact: Int) throws -> Data {
		var data = Data(capacity: exact)
		var remaining = exact
		while remaining > 0 {
			var buffer = [UInt8](repeating: 0, count: remaining)
			let bytesRead = read(fd, &buffer, remaining)
			if bytesRead <= 0 {
				throw POSIXError(POSIXErrorCode(rawValue: errno)!)
			}
			data.append(contentsOf: buffer[0..<bytesRead])
			remaining -= bytesRead
		}
		return data
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
			close(fd)
			isOpen = false
			packetStream?.finish()
			packetStream = nil
		}
	}

	func drainPendingPackets() async throws {
		// For Serial, since reader is always running, no need to drain separately
	}

	func startDrainPendingPackets() throws {
		// For Serial, reader is already started
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

		//		// Clear non-blocking for reads
		//		let flags = fcntl(fd, F_GETFL)
		//		if flags == -1 || fcntl(fd, F_SETFL, flags & ~O_NONBLOCK) == -1 {
		//			close(fd)
		//			throw POSIXError(POSIXErrorCode(rawValue: errno)!)
		//		}

		isOpen = true

		startReader()
		return (getPacketStream(), nil)
	}
}
