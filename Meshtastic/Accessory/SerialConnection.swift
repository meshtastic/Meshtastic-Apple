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

/// Custom error type for serial connection handling.
private enum SerialError: Error, LocalizedError {
	case eof
	case ioFailed(String)
	case notConnected
	case invalidPacketLength(UInt16)

	var errorDescription: String? {
		switch self {
		case .eof:
			return "End of file reached."
		case .ioFailed(let reason):
			return "I/O Error: \(reason)"
		case .notConnected:
			return "Serial port not connected."
		case .invalidPacketLength(let length):
			return "Invalid packet length received: \(length)."
		}
	}
}

actor SerialConnection: Connection {
	private let path: String
	private var fd: Int32 = -1
	private var fileHandle: FileHandle?
	private var isOpen: Bool = false

	// For DispatchSourceRead implementation
	private var readSource: DispatchSourceRead?
	private let readQueue = DispatchQueue(label: "com.meshtastic.serial.read")
	private var readBuffer = Data()

	var isConnected: Bool { isOpen }

	init(path: String) {
		self.path = path
	}

	// MARK: - Reading Logic (DispatchSourceRead Implementation)

	/// Processes the internal buffer to find and yield complete packets.
	/// This method is always called on the actor's context.
	private func processBuffer() {
		let startOfFrame: [UInt8] = [0x94, 0xc3]

		while !readBuffer.isEmpty {
			guard let startIndex = readBuffer.firstRange(of: startOfFrame)?.lowerBound else {
				readBuffer.removeAll()
				return
			}

			if startIndex > readBuffer.startIndex {
				readBuffer.removeSubrange(readBuffer.startIndex..<startIndex)
			}

			guard readBuffer.count >= 4 else { return }

			let lengthBytes = readBuffer.subdata(in: 2..<4)
			let length = lengthBytes.withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }

			let totalPacketLength = 4 + Int(length)

			guard readBuffer.count >= totalPacketLength else { return }

			let payload = readBuffer.subdata(in: 4..<totalPacketLength)

			if let fromRadio = try? FromRadio(serializedBytes: payload) {
				packetStream?.yield(fromRadio)
			} else {
				Logger.transport.error("[Serial] Failed to deserialize payload. Skipping packet.")
			}

			readBuffer.removeSubrange(0..<totalPacketLength)
		}
	}

	/// The main reader setup, using a DispatchSourceRead for non-blocking I/O.
	private func startReader() {
		guard let fileHandle = self.fileHandle else { return }

		let source = DispatchSource.makeReadSource(fileDescriptor: fileHandle.fileDescriptor, queue: readQueue)
		self.readSource = source

		// The event handler is non-isolated. It must hop back to the actor to access state.
		source.setEventHandler { [weak self] in
			let bytesAvailable = source.data
			guard bytesAvailable > 0 else { return }

			// Schedule a task to run on the actor to handle the available data.
			Task {
				await self?.handleDataAvailable(bytesAvailable: Int(bytesAvailable))
			}
		}

		// The cancellation handler also hops back to the actor to clean up.
		source.setCancelHandler { [weak self] in
			Task {
				await self?.cleanUpConnection()
			}
		}

		source.resume()
	}

	/// Reads available data from the file handle and processes it.
	/// This method is always called on the actor's context via a Task.
	private func handleDataAvailable(bytesAvailable: Int) {
		guard isOpen, let fileHandle = self.fileHandle else {
			readSource?.cancel()
			return
		}

		do {
			if let data = try fileHandle.read(upToCount: bytesAvailable), !data.isEmpty {
				appendAndProcess(data: data)
			} else {
				// read(upToCount:) returns nil or empty data on EOF
				// handleReaderEOF()
			}
		} catch {
			Logger.transport.error("[Serial] Read error: \(error)")
			handleReaderEOF()
		}
	}

	// Actor-isolated methods to be called from other actor-isolated methods.
	private func appendAndProcess(data: Data) {
		readBuffer.append(data)
		processBuffer()
	}

	private func handleReaderEOF() {
		Logger.transport.info("[Serial] Reached end of file. Closing connection.")
		readSource?.cancel()
	}

	// MARK: - Connection Lifecycle

	func connect() async throws -> (AsyncStream<FromRadio>, AsyncStream<String>?) {
		fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
		if fd == -1 {
			throw POSIXError(POSIXErrorCode(rawValue: errno)!)
		}

		var term = termios()
		if tcgetattr(fd, &term) == -1 {
			close(fd)
			throw POSIXError(POSIXErrorCode(rawValue: errno)!)
		}

		cfmakeraw(&term)
		term.c_cflag |= UInt((CS8 | CREAD | CLOCAL))
		term.c_cc.16 = 0 // VMIN
		term.c_cc.17 = 1 // VTIME (1 decisecond = 100ms)

		if cfsetspeed(&term, 921600) == -1 {
			close(fd)
			throw POSIXError(POSIXErrorCode(rawValue: errno)!)
		}

		if tcsetattr(fd, TCSANOW, &term) == -1 {
			close(fd)
			throw POSIXError(POSIXErrorCode(rawValue: errno)!)
		}

		self.fileHandle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
		self.isOpen = true

		startReader()
		return (getPacketStream(), nil)
	}

	/// This is the primary cleanup function, called when the read source is cancelled.
	private func cleanUpConnection() {
		guard isOpen else { return }
		isOpen = false

		try? fileHandle?.close()
		fileHandle = nil
		fd = -1
		readSource = nil

		packetStream?.finish()
		packetStream = nil
		Logger.transport.debug("[Serial] Connection cleaned up.")
	}

	func disconnect() async throws {
		// To disconnect, we just cancel the read source.
		// The cancellation handler will perform the actual cleanup.
		readSource?.cancel()
	}

	// MARK: - Sending Data

	func send(_ data: ToRadio) async throws {
		guard isOpen, let fileHandle = self.fileHandle else {
			throw SerialError.notConnected
		}
		let serialized = try data.serializedData()
		var buffer = Data([0x94, 0xc3])
		var len: UInt16 = UInt16(serialized.count).bigEndian
		buffer.append(Data(bytes: &len, count: 2))
		buffer.append(serialized)

		do {
			try fileHandle.write(contentsOf: buffer)
		} catch {
			throw SerialError.ioFailed(error.localizedDescription)
		}
	}

	// MARK: - Stream Management

	private var packetStream: AsyncStream<MeshtasticProtobufs.FromRadio>.Continuation?

	private func getPacketStream() -> AsyncStream<MeshtasticProtobufs.FromRadio> {
		AsyncStream<MeshtasticProtobufs.FromRadio> { continuation in
			self.packetStream = continuation
			continuation.onTermination = { _ in
				Task {
					await self.readSource?.cancel()
				}
			}
		}
	}

	// These methods are part of the Connection protocol but are not needed
	// for a continuously-reading serial connection.
	func drainPendingPackets() async throws {}
	func startDrainPendingPackets() throws {}
}

////
////  SerialConnection.swift
////  Meshtastic
////
////  Created by Jake Bordens on 7/22/25.
////
//
// import Foundation
// import OSLog
// import MeshtasticProtobufs
// import Darwin.POSIX.termios
//
//
// actor SerialConnection: Connection {
//
//
//
//
//
//
//
//
//	private let path: String
//	private var fd: Int32 = -1
//	private var isOpen: Bool = false
//
//	private var readerTask: Task<Void, Never>?
//
//	var isConnected: Bool { isOpen }
//
//	init(path: String) {
//		self.path = path
//	}
//
//	private func waitForMagicBytes() throws -> Bool {
//		let startOfFrame: [UInt8] = [0x94, 0xc3]
//		var waitingOnByte = 0
//		while isOpen {
//			var byte: UInt8 = 0
//			let bytesRead = read(fd, &byte, 1)
//			if bytesRead <= 0 {
//				continue
//			}
//			if byte == startOfFrame[waitingOnByte] {
//				waitingOnByte += 1
//			} else {
//				waitingOnByte = 0
//
//
//
//
//
//
//
//
//
//
//
//
//
//
//
//
//
//			}
//			if waitingOnByte > 1 {
//				return true
//			}
//		}
//		return false
//	}
//
//	private func readInteger() throws -> UInt16? {
//		var buffer = [UInt8](repeating: 0, count: 2)
//		let bytesRead = read(fd, &buffer, 2)
//		if bytesRead == 2 {
//			return buffer.withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
//		}
//		return nil
//	}
//
//	private func startReader() {
//		readerTask = Task { @MainActor in
//			while await self.isOpen {
//				do {
//					if try await self.waitForMagicBytes() == false {
//						Logger.transport.debug("[Serial] startReader: EOF while waiting for magic bytes")
//						continue
//					}
//					if let length = try await self.readInteger() {
//						let payload = try await self.receiveData(exact: Int(length))
//
//
//
//
//						if let fromRadio = try? FromRadio(serializedBytes: payload) {
//							await self.packetStream?.yield(fromRadio)
//						} else {
//							await self.packetStream?.finish()
//						}
//
//					} else {
//						Logger.transport.debug("[Serial] startReader: EOF while waiting for length")
//
//					}
//				} catch {
//					Logger.transport.error("[Serial] startReader: Error reading from Serial: \(error)")
//					await self.packetStream?.finish()
//					break
//				}
//
//
//			}
//		}
//	}
//
//	private func receiveData(exact: Int) throws -> Data {
//		var data = Data(capacity: exact)
//		var remaining = exact
//		while remaining > 0 {
//			var buffer = [UInt8](repeating: 0, count: remaining)
//			let bytesRead = read(fd, &buffer, remaining)
//			if bytesRead <= 0 {
//				throw POSIXError(POSIXErrorCode(rawValue: errno)!)
//			}
//			data.append(contentsOf: buffer[0..<bytesRead])
//			remaining -= bytesRead
//		}
//		return data
//	}
//
//	func send(_ data: ToRadio) async throws {
//		guard isOpen else {
//			throw AccessoryError.ioFailed("Not connected")
//		}
//		let serialized = try data.serializedData()
//		var buffer = Data([0x94, 0xc3])
//		var len: UInt16 = UInt16(serialized.count).bigEndian
//		buffer.append(Data(bytes: &len, count: 2))
//		buffer.append(serialized)
//
//		let written = buffer.withUnsafeBytes { ptr in
//			Darwin.write(fd, ptr.baseAddress, buffer.count)
//		}
//		if written != buffer.count {
//			throw POSIXError(POSIXErrorCode(rawValue: errno)!)
//		}
//	}
//
//	func disconnect() async throws {
//		if isOpen {
//			readerTask?.cancel()
//
//			close(fd)
//			isOpen = false
//			packetStream?.finish()
//			packetStream = nil
//		}
//	}
//
//	func drainPendingPackets() async throws {
//		// For Serial, since reader is always running, no need to drain separately
//	}
//
//	func startDrainPendingPackets() throws {
//		// For Serial, reader is already started
//	}
//
//	private var packetStream: AsyncStream<MeshtasticProtobufs.FromRadio>.Continuation?
//
//	private func getPacketStream() -> AsyncStream<MeshtasticProtobufs.FromRadio> {
//		AsyncStream<MeshtasticProtobufs.FromRadio> { continuation in
//			self.packetStream = continuation
//			continuation.onTermination = { _ in
//				Task { try await self.disconnect() }
//			}
//		}
//	}
//
//	func connect() async throws -> (AsyncStream<FromRadio>, AsyncStream<String>?) {
//		fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
//		if fd == -1 {
//			throw POSIXError(POSIXErrorCode(rawValue: errno)!)
//		}
//
//		var term: termios = termios()
//		if tcgetattr(fd, &term) == -1 {
//			close(fd)
//			throw POSIXError(POSIXErrorCode(rawValue: errno)!)
//		}
//
//		cfmakeraw(&term)
//		term.c_cflag |= UInt((CS8 | CREAD | CLOCAL))
//		if cfsetspeed(&term, 921600) == -1 {
//			close(fd)
//			throw POSIXError(POSIXErrorCode(rawValue: errno)!)
//		}
//
//		if tcsetattr(fd, TCSANOW, &term) == -1 {
//			close(fd)
//			throw POSIXError(POSIXErrorCode(rawValue: errno)!)
//		}
//
//		//		// Clear non-blocking for reads
//		//		let flags = fcntl(fd, F_GETFL)
//		//		if flags == -1 || fcntl(fd, F_SETFL, flags & ~O_NONBLOCK) == -1 {
//		//			close(fd)
//		//			throw POSIXError(POSIXErrorCode(rawValue: errno)!)
//		//		}
//
//
//
//		isOpen = true
//
//
//		startReader()
//		return (getPacketStream(), nil)
//	}
// }
