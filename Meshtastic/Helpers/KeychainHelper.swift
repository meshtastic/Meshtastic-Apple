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

	func save(key: String, value: String, service: String = Bundle.main.bundleIdentifier!) -> OSStatus {
		let data = value.data(using: .utf8)!

		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: key,
			kSecValueData as String: data,
			kSecAttrSynchronizable as String: kCFBooleanTrue!,
			kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
		]

		SecItemDelete(query as CFDictionary) // Delete existing item if any

		let status = SecItemAdd(query as CFDictionary, nil)
		return status
	}

	func read(key: String, service: String = Bundle.main.bundleIdentifier!) -> String? {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: key,
			kSecReturnData as String: kCFBooleanTrue,
			kSecMatchLimit as String: kSecMatchLimitOne,
			kSecAttrSynchronizable as String: kCFBooleanTrue!
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

	func delete(key: String, service: String = Bundle.main.bundleIdentifier!) -> OSStatus {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: key,
			kSecAttrSynchronizable as String: kCFBooleanTrue!
		]

		let status = SecItemDelete(query as CFDictionary)
		return status
	}
}
