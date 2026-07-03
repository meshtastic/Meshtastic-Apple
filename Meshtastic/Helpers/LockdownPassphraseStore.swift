//
//  LockdownPassphraseStore.swift
//  Meshtastic
//
//  Per-peripheral passphrase cache for MESHTASTIC_LOCKDOWN-hardened nodes.
//  Backed by KeychainHelper with synchronizable=false (lockdown is a per-device
//  pairing, not iCloud-synced) and AfterFirstUnlockThisDeviceOnly accessibility
//  so silent auto-replay can run after a fresh app launch from a locked device.
//
import Foundation

struct StoredPassphrase: Codable, Equatable {
	let passphrase: String
	let bootsRemaining: UInt32
	let validUntilEpoch: UInt32
	/// Per-boot uptime cap in seconds. 0 = unlimited.
	/// See `LockdownAuth.max_session_seconds` (meshtastic/protobufs PR #916).
	let maxSessionSeconds: UInt32

	init(passphrase: String,
		 bootsRemaining: UInt32,
		 validUntilEpoch: UInt32,
		 maxSessionSeconds: UInt32 = 0) {
		self.passphrase = passphrase
		self.bootsRemaining = bootsRemaining
		self.validUntilEpoch = validUntilEpoch
		self.maxSessionSeconds = maxSessionSeconds
	}

	private enum CodingKeys: String, CodingKey {
		case passphrase, bootsRemaining, validUntilEpoch, maxSessionSeconds
	}

	/// Custom decoder so cached entries written before maxSessionSeconds existed
	/// still load cleanly with a default of 0.
	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		passphrase = try c.decode(String.self, forKey: .passphrase)
		bootsRemaining = try c.decode(UInt32.self, forKey: .bootsRemaining)
		validUntilEpoch = try c.decode(UInt32.self, forKey: .validUntilEpoch)
		maxSessionSeconds = try c.decodeIfPresent(UInt32.self, forKey: .maxSessionSeconds) ?? 0
	}
}

/// Protocol abstraction over `LockdownPassphraseStore` so tests can substitute
/// an in-memory fake without hitting the real iOS Keychain. Production code
/// uses the concrete class via `LockdownPassphraseStore.shared`.
protocol LockdownPassphraseStoring: AnyObject {
	func get(peripheralID: UUID) -> StoredPassphrase?
	@discardableResult func save(peripheralID: UUID, _ stored: StoredPassphrase) -> Bool
	@discardableResult func delete(peripheralID: UUID) -> Bool
}

final class LockdownPassphraseStore: LockdownPassphraseStoring {

	static let shared = LockdownPassphraseStore()

	private let service = "meshtastic.lockdown.passphrase"
	private let keychain: KeychainHelper

	init(keychain: KeychainHelper = .standard) {
		self.keychain = keychain
	}

	func get(peripheralID: UUID) -> StoredPassphrase? {
		let key = peripheralID.uuidString
		guard let json = keychain.read(key: key, service: service, synchronizable: false) else {
			return nil
		}
		guard let data = json.data(using: .utf8) else {
			// Malformed entry. Wipe so we don't keep returning nil through this branch.
			_ = keychain.delete(key: key, service: service, synchronizable: false)
			return nil
		}
		do {
			return try JSONDecoder().decode(StoredPassphrase.self, from: data)
		} catch {
			_ = keychain.delete(key: key, service: service, synchronizable: false)
			return nil
		}
	}

	@discardableResult
	func save(peripheralID: UUID, _ stored: StoredPassphrase) -> Bool {
		guard let data = try? JSONEncoder().encode(stored),
			  let json = String(data: data, encoding: .utf8) else {
			return false
		}
		let status = keychain.save(
			key: peripheralID.uuidString,
			value: json,
			service: service,
			accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
			synchronizable: false
		)
		return status == errSecSuccess
	}

	@discardableResult
	func delete(peripheralID: UUID) -> Bool {
		let status = keychain.delete(
			key: peripheralID.uuidString,
			service: service,
			synchronizable: false
		)
		return status == errSecSuccess || status == errSecItemNotFound
	}
}
