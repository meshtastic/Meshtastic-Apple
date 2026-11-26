//
//  NiimbotPrinter.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/25/26.
//

import CoreBluetooth
import Foundation
import OSLog

/// A Niimbot label printer over Bluetooth LE. The printer takes the same packets over BLE
/// as over USB, on one characteristic that both notifies and takes writes without
/// response (how MultiMote/niimbluelib finds it). The print sequences follow labeltastic's
/// vendored niimprint, including its notes on newer firmware. Its own CBCentralManager, so
/// it never touches the radio's connection.
@MainActor
final class NiimbotPrinter: NSObject, ObservableObject {

	enum Status: Equatable {
		case idle
		case bluetoothOff
		case searching
		case connecting(String)
		case ready(String)
		case printing(String)
		case failed(String)
	}

	@Published private(set) var status: Status = .idle
	@Published private(set) var found: [CBPeripheral] = []

	/// Name prefixes of the models labeltastic and niimbluelib know. Printers advertise as
	/// e.g. "D110-H12345678".
	static let namePrefixes = ["D110", "D11", "D101", "B21", "B1", "B18", "B3S"]

	private var central: CBCentralManager?
	private var peripheral: CBPeripheral?
	private var channel: CBCharacteristic?
	private var parser = NiimbotPacketParser()
	private var received: [NiimbotPacket] = []
	private var poweredOn: CheckedContinuation<Void, Error>?
	private var ready: CheckedContinuation<Void, Error>?

	// MARK: Finding and connecting

	func search() async throws {
		try await powerOn()
		found = []
		status = .searching
		central?.scanForPeripherals(withServices: nil)
	}

	func stopSearching() {
		central?.stopScan()
		if status == .searching { status = .idle }
	}

	func connect(_ target: CBPeripheral) async throws {
		try await powerOn()
		central?.stopScan()
		status = .connecting(target.name ?? "printer")
		// Nothing from an earlier connection carries over: a half-received reply would eat the
		// start of the next one, and a stale error packet would fail the first request.
		parser = NiimbotPacketParser()
		received = []
		channel = nil
		peripheral = target
		target.delegate = self
		// CoreBluetooth never gives up on a connection; a printer that's off would hang here.
		let timeout = Task { [weak self] in
			try await Task.sleep(for: .seconds(10))
			guard let self, self.ready != nil else { return }
			self.central?.cancelPeripheralConnection(target)
			self.fail(NiimbotPrinterError.noResponse(request: NiimbotRequest.connect.rawValue))
		}
		defer { timeout.cancel() }
		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			ready = continuation
			central?.connect(target)
		}
		status = .ready(target.name ?? "printer")
	}

	/// Reconnects to a printer found before, by the identifier CoreBluetooth gave it. False
	/// when this device doesn't know it any more.
	func connect(identifier: UUID) async throws -> Bool {
		try await powerOn()
		guard let known = central?.retrievePeripherals(withIdentifiers: [identifier]).first else { return false }
		try await connect(known)
		return true
	}

	var connectedIdentifier: UUID? { channel == nil ? nil : peripheral?.identifier }

	func disconnect() {
		if let peripheral { central?.cancelPeripheralConnection(peripheral) }
		peripheral = nil
		channel = nil
		status = .idle
	}

	private func powerOn() async throws {
		if central == nil {
			try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
				poweredOn = continuation
				central = CBCentralManager(delegate: self, queue: .main)
			}
		} else if central?.state != .poweredOn {
			status = .bluetoothOff
			throw CBError(.unknown)
		}
	}

	// MARK: Printing

	/// Prints one label. `density` 1-3 on the D110. Runs the sequence the printer's
	/// protocol version calls for: v3 and later print blank on the older sequence.
	func printLabel(_ bitmap: LabelBitmap, density: UInt8 = 3) async throws {
		guard channel != nil else { throw NiimbotPrinterError.noResponse(request: NiimbotRequest.connect.rawValue) }
		let name = peripheral?.name ?? "printer"
		status = .printing(name)
		defer { if case .printing = status { status = .ready(name) } }

		_ = try? await transceive(.heartbeat, [0x01])  // wakes a dozing printer
		let version = await protocolVersion()
		Logger.services.info("🏷️ [Label] \(name, privacy: .public) protocol v\(version)")
		let quantity: UInt16 = 1
		let height = UInt16(bitmap.height), width = UInt16(bitmap.width)

		if version >= 3 {
			_ = try? await transceive(.connect, [0x01])
		}
		_ = try await transceive(.setLabelDensity, [density], replyOffset: 16)
		_ = try await transceive(.setLabelType, [1], replyOffset: 16)  // 1 = die-cut with gaps
		if version >= 4 {
			_ = try await transceive(.startPrint, quantity.bigEndianBytes + [UInt8](repeating: 0, count: 7))
			// niimbluelib's fire-and-forget status query; its late reply is ignored.
			try await send(NiimbotPacket(NiimbotRequest.getPrintStatus.rawValue, [0x01]))
			_ = try await transceive(.setDimension, height.bigEndianBytes + width.bigEndianBytes
				+ quantity.bigEndianBytes + [0, 0, 0, 0, 0, 0, 0])
		} else if version == 3 {
			_ = try await transceive(.startPrint, quantity.bigEndianBytes + [0, 0, 0, 0, 0])
			_ = try await transceive(.startPagePrint, [0x01])
			_ = try await transceive(.setDimension, height.bigEndianBytes + width.bigEndianBytes + quantity.bigEndianBytes)
		} else {
			_ = try await transceive(.startPrint, [0x01])
			_ = try await transceive(.startPagePrint, [0x01])
			_ = try await transceive(.setDimension, height.bigEndianBytes + width.bigEndianBytes)
		}
		for packet in NiimbotImageEncoder.packets(for: bitmap) {
			try await send(packet)
			try await Task.sleep(for: .milliseconds(10))  // niimbluelib's pacing
		}
		_ = try await transceive(.endPagePrint, [0x01])
		try await waitForPage(quantity)
		_ = try? await transceive(.endPrint, [0x01])
		if version >= 4 {  // some models drop the next packet; give them a spare
			try? await send(NiimbotPacket(NiimbotRequest.heartbeat.rawValue, [0x01]))
		}
	}

	/// 0 for older printers, 3, 4 or 5 for newer firmware (niimbluelib's decoding).
	private func protocolVersion() async -> Int {
		guard let reply = try? await transceive(.printerStatusData, [0x01], replyOffset: 16),
			  reply.data.count > 12 else { return 0 }
		let number = Int(reply.data[11]) * 100 + Int(reply.data[12])
		switch number {
		case 204..<300: return 3
		case 300..<302: return 4
		case 302...: return 5
		default: return 0
		}
	}

	private func waitForPage(_ quantity: UInt16) async throws {
		for _ in 0..<200 {  // about a minute
			try await Task.sleep(for: .milliseconds(300))
			let reply: NiimbotPacket
			do {
				reply = try await transceive(.getPrintStatus, [0x01], replyOffset: 16)
			} catch let error as NiimbotPrinterError {
				// A fault the printer reports (cover open, labels out) is the answer; a
				// skipped poll from a busy printer is just retried.
				if case .printer = error { throw error }
				continue
			}
			if reply.data.count >= 2, UInt16(reply.data[0]) << 8 | UInt16(reply.data[1]) >= quantity {
				return
			}
		}
		throw NiimbotPrinterError.noResponse(request: NiimbotRequest.getPrintStatus.rawValue)
	}

	// MARK: Packets

	/// Sends a request and waits for its reply, whose type is the request's plus
	/// `replyOffset`. An error packet from the printer throws.
	@discardableResult
	private func transceive(
		_ request: NiimbotRequest,
		_ data: [UInt8],
		replyOffset: UInt8 = 1,
		timeout: Duration = .seconds(2)
	) async throws -> NiimbotPacket {
		let replyType = request.rawValue &+ replyOffset
		received.removeAll { $0.type == replyType }
		try await send(NiimbotPacket(request.rawValue, data))
		let deadline = ContinuousClock.now + timeout
		while ContinuousClock.now < deadline {
			if let error = received.firstIndex(where: { $0.type == 0xDB }) {
				let code = received.remove(at: error).data.first ?? 0
				throw NiimbotPrinterError.printer(code: code)
			}
			if received.contains(where: { $0.type == 0x00 }) {
				received.removeAll { $0.type == 0x00 }
				throw NiimbotPrinterError.unsupported(request: request.rawValue)
			}
			if let index = received.firstIndex(where: { $0.type == replyType }) {
				return received.remove(at: index)
			}
			try await Task.sleep(for: .milliseconds(20))
		}
		throw NiimbotPrinterError.noResponse(request: request.rawValue)
	}

	private func send(_ packet: NiimbotPacket) async throws {
		guard let peripheral, let channel else {
			throw NiimbotPrinterError.noResponse(request: packet.type)
		}
		let bytes = packet.bytes
		let chunk = max(20, peripheral.maximumWriteValueLength(for: .withoutResponse))
		var offset = 0
		while offset < bytes.count {
			while !peripheral.canSendWriteWithoutResponse {
				try await Task.sleep(for: .milliseconds(5))
			}
			let end = min(offset + chunk, bytes.count)
			peripheral.writeValue(Data(bytes[offset..<end]), for: channel, type: .withoutResponse)
			offset = end
		}
	}
}

// MARK: - CoreBluetooth

extension NiimbotPrinter: CBCentralManagerDelegate, CBPeripheralDelegate {

	nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
		MainActor.assumeIsolated {
			guard let poweredOn else { return }
			self.poweredOn = nil
			if central.state == .poweredOn {
				poweredOn.resume()
			} else {
				status = .bluetoothOff
				poweredOn.resume(throwing: CBError(.unknown))
			}
		}
	}

	nonisolated func centralManager(
		_ central: CBCentralManager,
		didDiscover peripheral: CBPeripheral,
		advertisementData: [String: Any],
		rssi RSSI: NSNumber
	) {
		MainActor.assumeIsolated {
			guard let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String,
				  Self.namePrefixes.contains(where: { name.hasPrefix($0) }),
				  !found.contains(where: { $0.identifier == peripheral.identifier }) else { return }
			found.append(peripheral)
		}
	}

	nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
		peripheral.discoverServices(nil)
	}

	nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
		MainActor.assumeIsolated {
			guard peripheral.identifier == self.peripheral?.identifier else { return }
			fail(error ?? CBError(.peripheralDisconnected))
		}
	}

	nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
		MainActor.assumeIsolated {
			// A printer given up on (a timeout, or picking another) disconnects later; that
			// must not touch the connection that replaced it.
			guard peripheral.identifier == self.peripheral?.identifier else { return }
			channel = nil
			if ready != nil {
				fail(error ?? CBError(.peripheralDisconnected))
			} else if case .failed = status {
				// Keep the failure on screen rather than replacing it with "not connected".
			} else {
				status = .idle
			}
		}
	}

	nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
		// Skip the standard short-UUID services; the print channel is on a custom one.
		for service in peripheral.services ?? [] where service.uuid.uuidString.count > 4 {
			peripheral.discoverCharacteristics(nil, for: service)
		}
	}

	nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
		guard let match = service.characteristics?.first(where: {
			$0.properties.contains(.notify) && $0.properties.contains(.writeWithoutResponse)
		}) else { return }
		MainActor.assumeIsolated {
			guard channel == nil else { return }
			channel = match
			peripheral.setNotifyValue(true, for: match)
		}
	}

	nonisolated func peripheral(
		_ peripheral: CBPeripheral,
		didUpdateNotificationStateFor characteristic: CBCharacteristic,
		error: Error?
	) {
		MainActor.assumeIsolated {
			guard peripheral.identifier == self.peripheral?.identifier else { return }
			if let error {
				// No notifications means no replies: drop the link so the next attempt starts
				// clean instead of finding a channel and waiting out the timeout.
				channel = nil
				central?.cancelPeripheralConnection(peripheral)
				fail(error)
				return
			}
			guard let ready else { return }
			self.ready = nil
			ready.resume()
		}
	}

	nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
		guard let value = characteristic.value else { return }
		MainActor.assumeIsolated {
			received += parser.append([UInt8](value))
		}
	}

	private func fail(_ error: Error) {
		status = .failed(error.localizedDescription)
		if let ready {
			self.ready = nil
			ready.resume(throwing: error)
		}
	}
}

private extension UInt16 {
	var bigEndianBytes: [UInt8] { [UInt8(self >> 8), UInt8(self & 0xFF)] }
}
