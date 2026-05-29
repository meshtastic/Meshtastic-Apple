//
//  NymeaConstants.swift
//  Meshtastic
//
//  Implements the nymea-networkmanager BLE GATT profile for Wi-Fi provisioning.
//  Protocol reference: https://github.com/nymea/nymea-networkmanager
//

import Foundation
import CoreBluetooth

// MARK: - Service UUIDs

/// The nymea Wireless Service — provides Wi-Fi network configuration.
let nymeaWirelessServiceUUID = CBUUID(string: "E081FEC0-F757-4449-B9C9-BFA83133F7FC")

/// The nymea Network Service — provides NetworkManager enable/disable control.
let nymeaNetworkServiceUUID = CBUUID(string: "EF6D6610-B8AF-49E0-9ECA-AB343513641C")

// MARK: - Wireless Service Characteristic UUIDs

/// Write JSON commands to control the Wi-Fi manager. Responses arrive on `nymeaCommanderResponseUUID`.
let nymeaWirelessCommanderUUID = CBUUID(string: "E081FEC1-F757-4449-B9C9-BFA83133F7FC")

/// Notify — JSON command responses, chunked into ≤20-byte packets ending with `\n`.
let nymeaCommanderResponseUUID = CBUUID(string: "E081FEC2-F757-4449-B9C9-BFA83133F7FC")

/// Read/Notify — 1-byte wireless adapter connection state.
let nymeaWirelessConnectionStatusUUID = CBUUID(string: "E081FEC3-F757-4449-B9C9-BFA83133F7FC")

/// Read/Notify — 1-byte wireless adapter mode (infrastructure, AP, etc.).
let nymeaWirelessModeUUID = CBUUID(string: "E081FEC4-F757-4449-B9C9-BFA83133F7FC")

// MARK: - Network Service Characteristic UUIDs

/// Read/Notify — 1-byte NetworkManager overall state.
let nymeaNetworkStatusUUID = CBUUID(string: "EF6D6611-B8AF-49E0-9ECA-AB343513641C")

/// Write — 1-byte network manager command.
let nymeaNetworkCommanderUUID = CBUUID(string: "EF6D6612-B8AF-49E0-9ECA-AB343513641C")

/// Notify — 1-byte result of the last network manager command.
let nymeaNetworkCommanderResponseUUID = CBUUID(string: "EF6D6613-B8AF-49E0-9ECA-AB343513641C")

/// Read/Notify — 1-byte: `0x00` = networking disabled, `0x01` = enabled.
let nymeaNetworkingEnabledUUID = CBUUID(string: "EF6D6614-B8AF-49E0-9ECA-AB343513641C")

/// Read/Notify — 1-byte: `0x00` = wireless disabled, `0x01` = enabled.
let nymeaWirelessEnabledUUID = CBUUID(string: "EF6D6615-B8AF-49E0-9ECA-AB343513641C")

// MARK: - Wireless Commands

/// Commands written to `nymeaWirelessCommanderUUID` as JSON `{ "c": <value>, "p": { ... } }\n`.
enum NymeaWirelessCommand: Int, Codable {
	case getNetworks    = 0
	case connect        = 1
	case connectHidden  = 2
	case disconnect     = 3
	case scan           = 4
	case getConnection  = 5
	case startAccessPoint = 6
}

// MARK: - Network Manager Commands

/// Raw byte values written to `nymeaNetworkCommanderUUID`.
enum NymeaNetworkCommand: UInt8 {
	case enableNetworking  = 0x00
	case disableNetworking = 0x01
	case enableWireless    = 0x02
	case disableWireless   = 0x03
}

// MARK: - Status Enumerations

/// Current wireless adapter connection state (read from `nymeaWirelessConnectionStatusUUID`).
enum NymeaWirelessConnectionStatus: UInt8, CustomStringConvertible {
	case unknown       = 0x00
	case unmanaged     = 0x01
	case unavailable   = 0x02
	case disconnected  = 0x03
	case prepare       = 0x04
	case config        = 0x05
	case needAuth      = 0x06
	case ipConfig      = 0x07
	case ipCheck       = 0x08
	case secondaries   = 0x09
	case activated     = 0x0A
	case deactivating  = 0x0B
	case failed        = 0x0C

	var description: String {
		switch self {
		case .unknown:      return "Unknown"
		case .unmanaged:    return "Unmanaged"
		case .unavailable:  return "Unavailable"
		case .disconnected: return "Disconnected"
		case .prepare:      return "Preparing"
		case .config:       return "Configuring"
		case .needAuth:     return "Needs Authentication"
		case .ipConfig:     return "Obtaining IP Address"
		case .ipCheck:      return "Checking Connection"
		case .secondaries:  return "Waiting for Secondary Connection"
		case .activated:    return "Connected"
		case .deactivating: return "Disconnecting"
		case .failed:       return "Failed"
		}
	}

	/// `true` while the device is actively trying to connect (not yet succeeded or failed).
	var isConnecting: Bool {
		switch self {
		case .prepare, .config, .needAuth, .ipConfig, .ipCheck, .secondaries: return true
		default: return false
		}
	}
}

/// Current wireless adapter mode (read from `nymeaWirelessModeUUID`).
enum NymeaWirelessMode: UInt8 {
	case unknown        = 0x00
	case adhoc          = 0x01
	case infrastructure = 0x02
	case accessPoint    = 0x03
}

/// Overall NetworkManager state (read from `nymeaNetworkStatusUUID`).
enum NymeaNetworkStatus: UInt8 {
	case unknown         = 0x00
	case asleep          = 0x01
	case disconnected    = 0x02
	case disconnecting   = 0x03
	case connecting      = 0x04
	case local           = 0x05
	case connectedSite   = 0x06
	case connectedGlobal = 0x07
}

// MARK: - Commander Response Error Codes

/// Error codes returned in the `"r"` field of a wireless commander response.
enum NymeaCommanderError: Int, Error, LocalizedError, Codable {
	case success                       = 0
	case invalidCommand                = 1
	case invalidParameter              = 2
	case networkManagerNotAvailable    = 3
	case wirelessNotAvailable          = 4
	case networkingDisabled            = 5
	case wirelessDisabled              = 6
	case unknown                       = 7

	var errorDescription: String? {
		switch self {
		case .success:                    return nil
		case .invalidCommand:             return "Invalid command"
		case .invalidParameter:           return "Invalid parameter"
		case .networkManagerNotAvailable: return "NetworkManager is not available on the device"
		case .wirelessNotAvailable:       return "Wireless adapter not available"
		case .networkingDisabled:         return "Networking is disabled"
		case .wirelessDisabled:           return "Wireless networking is disabled"
		case .unknown:                    return "Unknown error from device"
		}
	}
}

/// Error codes returned in the `"r"` field of a network service commander response.
enum NymeaNetworkCommanderError: UInt8, Error, LocalizedError {
	case success                    = 0x00
	case invalidValue               = 0x01
	case networkManagerNotAvailable = 0x02
	case wirelessNotAvailable       = 0x03
	case unknown                    = 0x04

	var errorDescription: String? {
		switch self {
		case .success:                    return nil
		case .invalidValue:               return "Invalid value"
		case .networkManagerNotAvailable: return "NetworkManager is not available"
		case .wirelessNotAvailable:       return "Wireless adapter not available"
		case .unknown:                    return "Unknown error"
		}
	}
}

// MARK: - JSON Command / Response Structures

/// A command packet sent to the wireless commander characteristic.
/// Serialises as `{"c":<cmd>,"p":{...}}\n` — the trailing newline is the protocol frame delimiter.
struct NymeaCommandPacket<P: Encodable>: Encodable {
	/// Command code (`"c"` field).
	let c: Int
	/// Optional parameters (`"p"` field). Omitted when `P == NoParams`.
	let p: P?

	init(command: NymeaWirelessCommand, params: P) {
		self.c = command.rawValue
		self.p = params
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(c, forKey: .c)
		if let p = p {
			try container.encode(p, forKey: .p)
		}
	}

	enum CodingKeys: String, CodingKey { case c, p }
}

/// Convenience no-parameter command packet.
struct NymeaSimpleCommand: Encodable {
	let c: Int
	init(command: NymeaWirelessCommand) { self.c = command.rawValue }
}

/// Decoded response from the wireless commander response characteristic.
struct NymeaResponsePacket: Decodable {
	/// Echo of the command code.
	let c: Int
	/// Result error code (0 = success).
	let r: Int
}

// MARK: - Wi-Fi Network Scan Result

/// A single Wi-Fi access point returned by `GetNetworks` (command 0) or the scan stream.
struct NymeaWifiNetwork: Identifiable, Decodable, Hashable {
	/// ESSID — the network name.
	let essid: String
	/// BSSID — the access point MAC address.
	let bssid: String
	/// Signal strength, 0–100 %.
	let signal: Int
	/// `true` if the network is WPA/WPA2 protected, `false` if open.
	let isProtected: Bool

	var id: String { bssid }

	/// Synthetic signal strength bucket (0–4) for displaying signal bars.
	var signalBars: Int {
		switch signal {
		case 76...100: return 4
		case 51...75:  return 3
		case 26...50:  return 2
		case 1...25:   return 1
		default:       return 0
		}
	}

	enum CodingKeys: String, CodingKey {
		case essid = "e"
		case bssid = "m"
		case signal = "s"
		case isProtected = "p"
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		essid = try container.decode(String.self, forKey: .essid)
		bssid = try container.decode(String.self, forKey: .bssid)
		signal = try container.decode(Int.self, forKey: .signal)
		let protectedFlag = try container.decode(Int.self, forKey: .isProtected)
		isProtected = protectedFlag != 0
	}
}

// MARK: - Get-Networks Response Payload

/// Payload of the GetNetworks (0) response — an array under `"p"`.
struct NymeaGetNetworksResponse: Decodable {
	/// Echo of the command code.
	let c: Int
	/// Result error code.
	let r: Int
	/// The list of discovered networks.
	let p: [NymeaWifiNetwork]?
}

// MARK: - Current Wi-Fi Connection Info

/// Payload of the GetConnection (5) response — the current Wi-Fi connection details.
struct NymeaWifiConnection: Decodable {
	/// ESSID of the connected network.
	let essid: String
	/// BSSID of the connected access point.
	let bssid: String
	/// Signal strength, 0–100 %.
	let signal: Int
	/// `true` if the network is protected.
	let isProtected: Bool
	/// Assigned IP address.
	let ipAddress: String

	enum CodingKeys: String, CodingKey {
		case essid = "e"
		case bssid = "m"
		case signal = "s"
		case isProtected = "p"
		case ipAddress = "i"
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		essid = try container.decode(String.self, forKey: .essid)
		bssid = try container.decode(String.self, forKey: .bssid)
		signal = try container.decode(Int.self, forKey: .signal)
		let protectedFlag = try container.decode(Int.self, forKey: .isProtected)
		isProtected = protectedFlag != 0
		ipAddress = try container.decode(String.self, forKey: .ipAddress)
	}
}

/// Wrapper for the GetConnection (5) response.
struct NymeaGetConnectionResponse: Decodable {
	let c: Int
	let r: Int
	let p: NymeaWifiConnection?
}

// MARK: - Connect Command Parameters

/// Parameters for the Connect (1) and ConnectHidden (2) commands.
struct NymeaConnectParams: Encodable {
	/// SSID.
	let e: String
	/// Password (empty string for open networks).
	let p: String
}
