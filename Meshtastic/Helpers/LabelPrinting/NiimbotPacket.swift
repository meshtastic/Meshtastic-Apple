//
//  NiimbotPacket.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/25/26.
//

import Foundation

/// One packet of the Niimbot label printer protocol, as the printer sends and receives it:
/// `55 55 · type · length · data · checksum · AA AA`, where the checksum XORs the type, the
/// length and every data byte. Ported from niimprint as meshtastic/labeltastic vendors it.
struct NiimbotPacket: Equatable {
	let type: UInt8
	let data: [UInt8]

	init(_ type: UInt8, _ data: [UInt8]) {
		self.type = type
		self.data = data
	}

	var bytes: [UInt8] {
		let checksum = data.reduce(type ^ UInt8(data.count)) { $0 ^ $1 }
		return [0x55, 0x55, type, UInt8(data.count)] + data + [checksum, 0xAA, 0xAA]
	}
}

/// The requests the print sequence uses. A reply's type is the request's plus an offset
/// that depends on the request (see `NiimbotPrinter.transceive`).
enum NiimbotRequest: UInt8 {
	case startPrint = 0x01
	case startPagePrint = 0x03
	case setDimension = 0x13
	case setLabelDensity = 0x21
	case setLabelType = 0x23
	case getInfo = 0x40
	case getPrintStatus = 0xA3
	case printerStatusData = 0xA5
	case connect = 0xC1
	case heartbeat = 0xDC
	case endPagePrint = 0xE3
	case endPrint = 0xF3
}

/// Collects bytes from the printer's notifications and yields whole packets. A
/// notification can carry part of a packet or several; bytes that don't start a packet are
/// dropped until the next `55 55`.
struct NiimbotPacketParser {
	private var buffer: [UInt8] = []

	mutating func append(_ bytes: [UInt8]) -> [NiimbotPacket] {
		buffer += bytes
		var packets: [NiimbotPacket] = []
		while true {
			while buffer.count >= 2, !(buffer[0] == 0x55 && buffer[1] == 0x55) {
				buffer.removeFirst()
			}
			guard buffer.count >= 4 else { break }
			let total = Int(buffer[3]) + 7
			guard buffer.count >= total else { break }
			let frame = Array(buffer[0..<total])
			buffer.removeFirst(total)
			let type = frame[2]
			let data = Array(frame[4..<(4 + Int(frame[3]))])
			let checksum = data.reduce(type ^ frame[3]) { $0 ^ $1 }
			guard checksum == frame[total - 3], frame[total - 2] == 0xAA, frame[total - 1] == 0xAA else {
				continue  // a corrupt frame is dropped; the request that wanted it times out
			}
			packets.append(NiimbotPacket(type, data))
		}
		return packets
	}
}

/// What a printer error packet (type 0xDB) means, per MultiMote/niimbluelib.
enum NiimbotPrinterError: LocalizedError, Equatable {
	case printer(code: UInt8)
	case unsupported(request: UInt8)
	case noResponse(request: UInt8)

	var errorDescription: String? {
		switch self {
		case .printer(let code):
			switch code {
			case 0x01: return String(localized: "The printer stopped: its cover is open.", comment: "Label printer error")
			case 0x02: return String(localized: "The printer stopped: it found no labels.", comment: "Label printer error")
			case 0x03: return String(localized: "The printer stopped: its battery is low.", comment: "Label printer error")
			case 0x05: return String(localized: "The print was canceled on the printer.", comment: "Label printer error")
			case 0x07: return String(localized: "The printer stopped: its print head is too hot.", comment: "Label printer error")
			case 0x08: return String(localized: "The printer stopped: the labels are out or the lid isn't latched.", comment: "Label printer error")
			case 0x09: return String(localized: "The printer is busy. Try again in a moment.", comment: "Label printer error")
			case 0x10: return String(localized: "The printer rejected this label roll.", comment: "Label printer error")
			default:
				let hex = String(code, radix: 16)
				return String(localized: "The printer stopped with error 0x\(hex).", comment: "Label printer error; the argument is a hex error code")
			}
		case .unsupported:
			return String(localized: "This printer doesn't support printing from Meshtastic.", comment: "Label printer error")
		case .noResponse:
			return String(localized: "The printer didn't answer. Check that it's on and nearby.", comment: "Label printer error")
		}
	}
}
