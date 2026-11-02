//
//  TAKCertificateManager.swift
//  Meshtastic
//
//  Created by niccellular 12/26/25
//

import Foundation
import Security
import OSLog

/// Keeps the TAK server's certificates. They are issued for this install the first time the
/// server starts or a data package is exported, and kept in the keychain; nothing is shared
/// between installs. A server identity can also be imported, for the rare setup that needs one.
final class TAKCertificateManager: @unchecked Sendable {

	static let shared = TAKCertificateManager()

	private let service = "com.meshtastic.tak"
	/// The issued set, as JSON.
	private let issuedAccount = "tak.issued"
	private let serverIdentityTag = "com.meshtastic.tak.server.identity"
	private let serverIdentityCustomTag = "com.meshtastic.tak.server.identity.custom"

	/// What earlier builds kept: a server identity, CA and client identity shared by every
	/// install, and the client CA list. Removed on first use so nothing trusts them again.
	private let legacyClientCATag = "com.meshtastic.tak.client.ca"
	private let legacyAccounts = [
		"tak.custom.server.p12.data", "tak.custom.server.p12.password",
		"tak.custom.client.p12.data", "tak.custom.client.p12.password"
	]

	private init() {
		removeLegacyItems()
	}

	// MARK: - Issued certificates

	/// The set issued for this install, if there is one.
	func issuedCertificates() -> TAKIssuedCertificates? {
		guard let data = readItem(account: issuedAccount) else { return nil }
		do {
			return try JSONDecoder().decode(TAKIssuedCertificates.self, from: data)
		} catch {
			Logger.tak.error("The issued TAK certificates could not be read and will be reissued: \(error.localizedDescription, privacy: .public)")
			return nil
		}
	}

	/// The issued set, issuing one if there is none and reissuing the server certificate when it
	/// is about to run out. Takes a second or two the first time; call it off the main thread.
	@discardableResult
	func ensureIssuedCertificates() throws -> TAKIssuedCertificates {
		if let issued = issuedCertificates() {
			if TAKCertificateGenerator.serverNeedsReissue(issued) {
				Logger.tak.info("Reissuing the TAK server certificate under the same CA")
				let reissued = try TAKCertificateGenerator.reissueServer(issued)
				try store(reissued)
				return reissued
			}
			if getIssuedServerIdentity() == nil {
				try importIssuedServerIdentity(issued)
			}
			return issued
		}
		Logger.tak.info("Issuing TAK certificates for this install")
		let issued = try TAKCertificateGenerator.issue()
		try store(issued)
		return issued
	}

	/// A new CA, server and client. TAK clients set up with the old data package stop
	/// connecting until they import a new one.
	@discardableResult
	func regenerateCertificates() throws -> TAKIssuedCertificates {
		Logger.tak.info("Regenerating TAK certificates")
		let issued = try TAKCertificateGenerator.issue()
		try store(issued)
		return issued
	}

	private func store(_ issued: TAKIssuedCertificates) throws {
		let data = try JSONEncoder().encode(issued)
		let status = upsertItem(account: issuedAccount, value: data)
		guard status == errSecSuccess else {
			Logger.tak.error("Failed to keep the issued TAK certificates: \(status)")
			throw TAKCertificateError.keychainError(status)
		}
		try importIssuedServerIdentity(issued)
	}

	private func importIssuedServerIdentity(_ issued: TAKIssuedCertificates) throws {
		let identity = try identity(from: issued.serverP12, password: issued.password)
		try storeServerIdentity(identity, tag: serverIdentityTag)
	}

	// MARK: - What the server and the export use

	/// The one client certificate the server accepts, DER.
	func issuedClientCertificate() -> Data? {
		issuedCertificates()?.clientCertificate
	}

	/// The password on the files in the data package.
	func exportPassword() -> String? {
		issuedCertificates()?.password
	}

	/// The client identity for the data package.
	func clientP12ForExport() -> Data? {
		issuedCertificates()?.clientP12
	}

	/// The truststore for the data package: the issued CA certificate, or the imported server
	/// certificate when one is in use. Certificates only, never a key.
	func truststoreForExport() throws -> Data? {
		guard let issued = issuedCertificates() else { return nil }
		guard let custom = customServerIdentity() else { return issued.truststoreP12 }
		var certificate: SecCertificate?
		guard SecIdentityCopyCertificate(custom, &certificate) == errSecSuccess, let certificate else {
			throw TAKCertificateError.invalidCertificate
		}
		return try TAKCertificateGenerator.truststore(
			certificates: [SecCertificateCopyData(certificate) as Data],
			password: issued.password,
			friendlyName: "Meshtastic TAK Server"
		)
	}

	// MARK: - Server identity

	/// Import a server identity from PKCS#12 data. It replaces the issued one until reset.
	@discardableResult
	func importServerIdentity(from p12Data: Data, password: String) throws -> SecIdentity {
		let identity = try identity(from: p12Data, password: password)
		try storeServerIdentity(identity, tag: serverIdentityCustomTag)
		Logger.tak.info("Custom server identity imported")
		return identity
	}

	private func identity(from p12Data: Data, password: String) throws -> SecIdentity {
		let options: [String: Any] = [kSecImportExportPassphrase as String: password]
		var items: CFArray?
		let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &items)
		guard status == errSecSuccess else {
			Logger.tak.error("Failed to import PKCS#12: \(status)")
			throw TAKCertificateError.importFailed(status)
		}
		guard let itemArray = items as? [[String: Any]],
			  let firstItem = itemArray.first,
			  let identity = firstItem[kSecImportItemIdentity as String] as! SecIdentity? else { // swiftlint:disable:this force_cast
			throw TAKCertificateError.noIdentityFound
		}
		return identity
	}

	private func storeServerIdentity(_ identity: SecIdentity, tag: String) throws {
		deleteIdentity(tag: tag)
		let addQuery: [String: Any] = [
			kSecValueRef as String: identity,
			kSecAttrLabel as String: tag,
			kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
		]
		let status = SecItemAdd(addQuery as CFDictionary, nil)
		guard status == errSecSuccess || status == errSecDuplicateItem else {
			Logger.tak.error("Failed to store server identity in Keychain: \(status)")
			throw TAKCertificateError.keychainError(status)
		}
	}

	private func identity(tag: String) -> SecIdentity? {
		let query: [String: Any] = [
			kSecClass as String: kSecClassIdentity,
			kSecAttrLabel as String: tag,
			kSecReturnRef as String: true
		]
		var item: CFTypeRef?
		guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
		return (item as! SecIdentity) // swiftlint:disable:this force_cast
	}

	private func deleteIdentity(tag: String) {
		let query: [String: Any] = [
			kSecClass as String: kSecClassIdentity,
			kSecAttrLabel as String: tag
		]
		SecItemDelete(query as CFDictionary)
	}

	private func customServerIdentity() -> SecIdentity? {
		identity(tag: serverIdentityCustomTag)
	}

	private func getIssuedServerIdentity() -> SecIdentity? {
		identity(tag: serverIdentityTag)
	}

	/// The identity the server presents: an imported one if there is one, else the issued one.
	func getServerIdentity() -> SecIdentity? {
		customServerIdentity() ?? getIssuedServerIdentity()
	}

	func hasServerCertificate() -> Bool {
		getServerIdentity() != nil
	}

	func hasCustomServerCertificate() -> Bool {
		customServerIdentity() != nil
	}

	/// Drop the imported server identity and go back to the issued one.
	func resetToDefaultServerCertificate() {
		deleteIdentity(tag: serverIdentityCustomTag)
		Logger.tak.info("Back to the issued server certificate")
	}

	/// For display.
	func getServerCertificateInfo() -> String? {
		guard let identity = getServerIdentity() else { return nil }
		var certificate: SecCertificate?
		guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let cert = certificate else { return nil }
		let prefix = hasCustomServerCertificate() ? "Custom: " : "Issued: "
		if let summary = SecCertificateCopySubjectSummary(cert) as String? {
			return prefix + summary
		}
		return prefix + "Certificate loaded"
	}

	// MARK: - Keychain items

	private func upsertItem(account: String, value: Data) -> OSStatus {
		deleteItem(account: account)
		let addQuery: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			// Stays with this device: a backup restored elsewhere gets its own set.
			kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
			kSecValueData as String: value
		]
		return SecItemAdd(addQuery as CFDictionary, nil)
	}

	private func readItem(account: String) -> Data? {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			kSecReturnData as String: true
		]
		var item: CFTypeRef?
		guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
		return item as? Data
	}

	private func deleteItem(account: String) {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account
		]
		SecItemDelete(query as CFDictionary)
	}

	private func removeLegacyItems() {
		for account in legacyAccounts {
			deleteItem(account: account)
		}
		let caQuery: [String: Any] = [
			kSecClass as String: kSecClassCertificate,
			kSecAttrLabel as String: legacyClientCATag
		]
		SecItemDelete(caQuery as CFDictionary)
		// The shared server identity sat under the tag the issued one uses now.
		if issuedCertificates() == nil {
			deleteIdentity(tag: serverIdentityTag)
		}
	}
}

// MARK: - Certificate Errors

enum TAKCertificateError: LocalizedError {
	case importFailed(OSStatus)
	case noIdentityFound
	case invalidCertificate
	case keychainError(OSStatus)

	var errorDescription: String? {
		switch self {
		case .importFailed(let status):
			return "Failed to import PKCS#12: \(securityErrorMessage(status))"
		case .noIdentityFound:
			return "No identity (certificate + private key) found in PKCS#12 file"
		case .invalidCertificate:
			return "Invalid certificate data"
		case .keychainError(let status):
			return "Keychain error: \(securityErrorMessage(status))"
		}
	}

	private func securityErrorMessage(_ status: OSStatus) -> String {
		if let message = SecCopyErrorMessageString(status, nil) {
			return message as String
		}
		return "Error code: \(status)"
	}
}
