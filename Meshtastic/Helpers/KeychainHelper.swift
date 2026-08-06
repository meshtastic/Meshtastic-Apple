//
//  KeychainHelper.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 6/17/25.
//
import Foundation
import Security

class KeychainHelper {

	static let standard = KeychainHelper()

	private init() {}

	func save(
		key: String,
		value: String,
		service: String = Bundle.main.bundleIdentifier!,
		accessibility: CFString = kSecAttrAccessibleWhenUnlocked,
		synchronizable: Bool = true
	) -> OSStatus {
		let data = value.data(using: .utf8)!

		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: key,
			kSecAttrSynchronizable as String: synchronizable ? kCFBooleanTrue! : kCFBooleanFalse!
		]

		let attributes: [String: Any] = [
			kSecValueData as String: data,
			kSecAttrAccessible as String: accessibility
		]

		let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
		if updateStatus != errSecItemNotFound {
			return updateStatus
		}

		var addQuery = query
		addQuery.merge(attributes) { _, new in new }
		return SecItemAdd(addQuery as CFDictionary, nil)
	}

	func read(
		key: String,
		service: String = Bundle.main.bundleIdentifier!,
		synchronizable: Bool = true
	) -> String? {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: key,
			kSecReturnData as String: kCFBooleanTrue!,
			kSecMatchLimit as String: kSecMatchLimitOne,
			kSecAttrSynchronizable as String: synchronizable ? kCFBooleanTrue! : kCFBooleanFalse!
		]

		var item: CFTypeRef?
		let status = SecItemCopyMatching(query as CFDictionary, &item)

		if status == errSecSuccess {
			if let data = item as? Data {
				return String(data: data, encoding: .utf8)
			}
		}
		return nil
	}

	func delete(
		key: String,
		service: String = Bundle.main.bundleIdentifier!,
		synchronizable: Bool = true
	) -> OSStatus {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: key,
			kSecAttrSynchronizable as String: synchronizable ? kCFBooleanTrue! : kCFBooleanFalse!
		]

		let status = SecItemDelete(query as CFDictionary)
		return status
	}
}
