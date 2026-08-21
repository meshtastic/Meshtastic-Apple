//
//  MeshShareStore.swift
//  Meshtastic
//

import Foundation
import Security

enum MeshShareStore {
	static let service = "org.meshtastic.apple.message-sharing"
	static let snapshotAccount = "recent-radio-snapshot"
	static let accessGroupInfoKey = "MeshtasticMessageSharingAccessGroup"

	enum StoreError: LocalizedError {
		case encodingFailed
		case missingAccessGroup
		case keychain(OSStatus)

		var errorDescription: String? {
			switch self {
			case .encodingFailed:
				return "The recent radio snapshot could not be encoded."
			case .missingAccessGroup:
				return "The Messages sharing Keychain group is not configured."
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

		guard let accessGroup else {
			throw StoreError.missingAccessGroup
		}
		let lookup = query(accessGroup: accessGroup)
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
		guard let accessGroup else {
			return nil
		}
		var lookup = query(accessGroup: accessGroup)
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
		guard let accessGroup else {
			throw StoreError.missingAccessGroup
		}
		let status = SecItemDelete(query(accessGroup: accessGroup) as CFDictionary)
		guard status == errSecSuccess || status == errSecItemNotFound else {
			throw StoreError.keychain(status)
		}
	}

	static func query(accessGroup: String) -> [String: Any] {
		return [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: snapshotAccount,
			kSecAttrAccessGroup as String: accessGroup,
			kSecAttrSynchronizable as String: false
		]
	}

	private static var accessGroup: String? {
		guard let value = Bundle.main.object(forInfoDictionaryKey: accessGroupInfoKey) as? String,
			  !value.isEmpty,
			  !value.contains("$(") else {
			return nil
		}
		return value
	}
}
