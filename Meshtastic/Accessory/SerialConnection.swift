//
//  SerialConnection.swift
//  Meshtastic
//
//  Created by Jake Bordens on 7/22/25.
//
#if targetEnvironment(macCatalyst)
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
	let type = TransportType.serial
	private let path: String
	private var fd: Int32 = -1
	private var fileHandle: FileHandle?
	private var isOpen: Bool = false

	// For DispatchSourceRead implementation
	private var readSource: DispatchSourceRead?
	private let readQueue = DispatchQueue(label: "com.meshtastic.serial.read")
	private var readBuffer = Data()

	private var eventStreamContinuation: AsyncStream<ConnectionEvent>.Continuation?
	
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
				eventStreamContinuation?.yield(.data(fromRadio))
			} else {
				Logger.transport.error("🔱 [Serial] Failed to deserialize payload. Skipping packet.")
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
			Task {
				if bytesAvailable > 0 {
					await self?.handleDataAvailable(bytesAvailable: Int(bytesAvailable))
				} else {
					await self?.handleReaderEOF()
				}
			}
		}

		// The cancellation handler also hops back to the actor to clean up.
		source.setCancelHandler { [weak self] in
			Task {
				try? await self?.disconnect(withError: AccessoryError.disconnected("Serial connection lost"))
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
			if let data = try fileHandle.read(upToCount: bytesAvailable) {
				if !data.isEmpty {
					appendAndProcess(data: data)
				} else {
					handleReaderEOF()
				}
			}
		} catch {
			Logger.transport.error("🔱 [Serial] Read error: \(error, privacy: .public)")
			handleReaderEOF()
		}
	}

	// Actor-isolated methods to be called from other actor-isolated methods.
	private func appendAndProcess(data: Data) {
		readBuffer.append(data)
		processBuffer()
	}

	private func handleReaderEOF() {
		Logger.transport.info("🔱 [Serial] Reached end of file. Closing connection.")
		readSource?.cancel()
	}

	// MARK: - Connection Lifecycle

	func connect() async throws -> AsyncStream<ConnectionEvent> {
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

		if cfsetspeed(&term, 115200) == -1 {
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
		return getPacketStream()
	}

	func disconnect(userInitiated: Bool) async throws {
		try await self.disconnect(withError: userInitiated ? nil : AccessoryError.disconnected("Unknown error"))
	}
	
	func disconnect(withError error: Error? = nil) async throws {
		if let error {
			eventStreamContinuation?.yield(.error(error))
		} else {
			eventStreamContinuation?.yield(.userDisconnected)
		}
		eventStreamContinuation?.finish()
		eventStreamContinuation = nil
		
		if isOpen {
			isOpen = false
			try? fileHandle?.close()
			fileHandle = nil
			fd = -1
			readSource?.cancel()
			readSource = nil
		}		
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
	private func getPacketStream() -> AsyncStream<ConnectionEvent> {
		AsyncStream<ConnectionEvent> { continuation in
			self.eventStreamContinuation = continuation
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
	
	func appDidEnterBackground() {
		
	}
	
	func appDidBecomeActive() {
		
	}
}
#endif
