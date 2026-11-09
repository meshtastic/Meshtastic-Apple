//
//  ConnectLink.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/8/26.
//

import Foundation
import UIKit
import UniformTypeIdentifiers

/// A node's connect code, `meshtastic://meshtastic/connections?address=<address>&pin=<PIN>`,
/// printed as a QR code or written to an NFC tag. The address is `x` and a Bluetooth address,
/// or `t` and a host with an optional port. Any page or app can open the link, so the app always
/// asks before it connects.
struct ConnectLink: Identifiable, Equatable {
	enum Address: Equatable {
		/// `AA:BB:CC:DD:EE:FF`, upper case. iOS hides a peripheral's hardware address, so this is
		/// only shown; the person picks the radio on Connect.
		case bluetooth(String)
		case tcp(host: String, port: Int)
	}

	static let defaultTCPPort = 4403

	let id = UUID()
	let address: Address
	/// Six digits, 100000 to 999999. Only on a Bluetooth address.
	let pin: String?

	/// The address as the prompt shows it.
	var displayAddress: String {
		switch address {
		case .bluetooth(let mac): mac
		case .tcp(let host, let port): "\(host):\(port)"
		}
	}

	/// Whether the URL is a connect link: the `connections` route on either form of the scheme.
	static func canHandle(_ url: URL) -> Bool {
		Router.isRoutable(url) && url.path == "/connections"
	}

	/// The link in a URL, or nil when its address is missing, malformed or has a prefix other
	/// than `x` or `t`. Such a link opens Connect without connecting.
	static func parse(_ components: URLComponents) -> ConnectLink? {
		let items = components.queryItems ?? []
		guard let raw = items.first(where: { $0.name == "address" })?.value,
			  let address = address(raw) else { return nil }
		let pin: String?
		if case .bluetooth = address, let value = items.first(where: { $0.name == "pin" })?.value, isPIN(value) {
			pin = value
		} else {
			pin = nil
		}
		return ConnectLink(address: address, pin: pin)
	}

	static func address(_ raw: String) -> Address? {
		guard let prefix = raw.first else { return nil }
		let rest = String(raw.dropFirst())
		switch prefix {
		case "x":
			let octets = rest.split(separator: ":", omittingEmptySubsequences: false)
			guard octets.count == 6, octets.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isHexDigit) }) else { return nil }
			return .bluetooth(rest.uppercased())
		case "t":
			let parts = rest.split(separator: ":", omittingEmptySubsequences: false)
			guard (1...2).contains(parts.count), let host = parts.first, isHost(host) else { return nil }
			guard parts.count == 2 else { return .tcp(host: String(host), port: defaultTCPPort) }
			guard parts[1].allSatisfy(\.isASCIIDigit), let port = Int(parts[1]), (1...65_535).contains(port) else { return nil }
			return .tcp(host: String(host), port: port)
		default:
			return nil
		}
	}

	/// Six ASCII digits from 100000 to 999999. Firmware stores the PIN as a number, so one with a
	/// leading zero could never match the radio's (design#177 requirement 3).
	static func isPIN(_ value: String) -> Bool {
		value.count == 6 && value.allSatisfy(\.isASCIIDigit) && value.first != "0"
	}

	/// A host name or IPv4 address: letters, digits, dots and hyphens.
	private static func isHost(_ host: Substring) -> Bool {
		!host.isEmpty && host.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }
	}

	/// Copies the PIN for the person to paste into the system's pairing dialog. Kept on this
	/// device and cleared after a few minutes, since it unlocks the radio.
	static func copyPIN(_ pin: String) {
		UIPasteboard.general.setItems(
			[[UTType.utf8PlainText.identifier: pin]],
			options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(5 * 60)]
		)
	}
}

private extension Character {
	var isASCIIDigit: Bool { isASCII && isNumber }
}
