//
//  MeshShareStore.swift
//  Meshtastic
//

import Foundation
import Security

enum MeshShareStore {
	static let service = "org.meshtastic.apple.message-sharing"
	static let snapshotAccount = "recent-radio-snapshot"

	enum StoreError: LocalizedError {
		case encodingFailed
		case keychain(OSStatus)

		var errorDescription: String? {
			switch self {
			case .encodingFailed:
				return "The recent radio snapshot could not be encoded."
			case .keychain(let status):
				return "The recent radio snapshot could not be saved (\(status))."
			}
		}
	}

	static func save(_ snapshot: MeshShareSnapshot) throws {
		let data: Data
		do {
			let encoder = JSONEncoder()
			encoder.dateEncodingStrategy = .millisecondsSince1970
			data = try encoder.encode(snapshot)
		} catch {
			throw StoreError.encodingFailed
		}

		let lookup = query
		let updateStatus = SecItemUpdate(
			lookup as CFDictionary,
			[kSecValueData: data] as CFDictionary
		)
		if updateStatus == errSecSuccess {
			return
		}
		if updateStatus != errSecItemNotFound {
			throw StoreError.keychain(updateStatus)
		}

		var insertion = lookup
		insertion[kSecValueData as String] = data
		insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
		let addStatus = SecItemAdd(insertion as CFDictionary, nil)
		guard addStatus == errSecSuccess else {
			throw StoreError.keychain(addStatus)
		}
	}

	static func load() -> MeshShareSnapshot? {
		var lookup = query
		lookup[kSecReturnData as String] = true
		lookup[kSecMatchLimit as String] = kSecMatchLimitOne
		var item: CFTypeRef?
		guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess,
			  let data = item as? Data else {
			return nil
		}
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .millisecondsSince1970
		guard let snapshot = try? decoder.decode(MeshShareSnapshot.self, from: data),
			  snapshot.version == MeshShareSnapshot.currentVersion else {
			return nil
		}
		return snapshot
	}

	static func delete() throws {
		let status = SecItemDelete(query as CFDictionary)
		guard status == errSecSuccess || status == errSecItemNotFound else {
			throw StoreError.keychain(status)
		}
	}

	private static var query: [String: Any] {
		[
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: snapshotAccount,
			kSecAttrSynchronizable as String: false
		]
	}
}
