//
//  TAKCertificateManager.swift
//  Meshtastic
//
//  Created by niccellular 12/26/25
//

import Foundation
import Security
import OSLog

/// Manages TLS certificates for the TAK server
/// Handles server identity (PKCS#12) and client CA certificates (PEM)
final class TAKCertificateManager {

	static let shared = TAKCertificateManager()

	// Keychain tags for certificate storage
	private let serverIdentityTag = "com.meshtastic.tak.server.identity"
	private let serverIdentityCustomTag = "com.meshtastic.tak.server.identity.custom"
	private let clientCATag = "com.meshtastic.tak.client.ca"

	// Bundled certificate password
	private let bundledPassword = "meshtastic"

	// Storage keys for custom P12 data (for data package generation)
	private let customServerP12DataKey = "tak.custom.server.p12.data"
	private let customServerP12PasswordKey = "tak.custom.server.p12.password"
	private let customClientP12DataKey = "tak.custom.client.p12.data"
	private let customClientP12PasswordKey = "tak.custom.client.p12.password"

	private init() {
		// Load bundled defaults on first launch if no custom cert exists
		loadBundledDefaultsIfNeeded()
	}

	/// Force reload all bundled certificates (useful after app update with new certs)
	func reloadBundledCertificates() {
		Logger.tak.info("Reloading bundled certificates...")

		// Clear custom certificate data
		clearCustomCertificateData()

		// Delete existing certificates
		deleteServerIdentity()
		deleteClientCACertificates()

		// Reload bundled defaults
		loadBundledServerIdentity()
		loadBundledClientCA()

		Logger.tak.info("Bundled certificates reloaded")
	}

	// MARK: - Bundled Default Certificates

	/// Load bundled default certificates if no custom certificates are configured
	private func loadBundledDefaultsIfNeeded() {
		// Only load if no custom server identity exists
		if !hasCustomServerCertificate() && getServerIdentity() == nil {
			loadBundledServerIdentity()
		}

		// Only load if no client CA exists
		if !hasClientCACertificate() {
			loadBundledClientCA()
		}
	}

	/// Load the bundled server identity (p12)
	private func loadBundledServerIdentity() {
		// Try subdirectory first, then root level (Xcode may flatten folder structure)
		let p12URL = Bundle.main.url(forResource: "server", withExtension: "p12", subdirectory: "Certificates")
			?? Bundle.main.url(forResource: "server", withExtension: "p12")

		guard let url = p12URL, let p12Data = try? Data(contentsOf: url) else {
			Logger.tak.warning("Bundled server.p12 not found in app bundle")
			return
		}

		do {
			_ = try importServerIdentity(from: p12Data, password: bundledPassword, isCustom: false)
			Logger.tak.info("Loaded bundled default server certificate")
		} catch {
			Logger.tak.error("Failed to load bundled server certificate: \(error.localizedDescription)")
		}
	}

	/// Load the bundled client CA certificate (pem)
	private func loadBundledClientCA() {
		// Try subdirectory first, then root level (Xcode may flatten folder structure)
		let pemURL = Bundle.main.url(forResource: "ca", withExtension: "pem", subdirectory: "Certificates")
			?? Bundle.main.url(forResource: "ca", withExtension: "pem")

		guard let url = pemURL, let pemData = try? Data(contentsOf: url) else {
			Logger.tak.warning("Bundled ca.pem not found in app bundle")
			return
		}

		do {
			_ = try importClientCACertificate(from: pemData)
			Logger.tak.info("Loaded bundled default CA certificate")
		} catch {
			Logger.tak.error("Failed to load bundled CA certificate: \(error.localizedDescription)")
		}
	}

	/// Check if using custom (user-imported) server certificate
	func hasCustomServerCertificate() -> Bool {
		let query: [String: Any] = [
			kSecClass as String: kSecClassIdentity,
			kSecAttrLabel as String: serverIdentityCustomTag,
			kSecReturnRef as String: true
		]
		var item: CFTypeRef?
		return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
	}

	/// Get the bundled CA certificate data for sharing to TAK
	func getBundledCACertificateData() -> Data? {
		let pemURL = Bundle.main.url(forResource: "ca", withExtension: "pem", subdirectory: "Certificates")
			?? Bundle.main.url(forResource: "ca", withExtension: "pem")

		guard let url = pemURL, let pemData = try? Data(contentsOf: url) else {
			return nil
		}
		return pemData
	}

	/// Get URL to bundled CA certificate for sharing
	func getBundledCACertificateURL() -> URL? {
		return Bundle.main.url(forResource: "ca", withExtension: "pem", subdirectory: "Certificates")
			?? Bundle.main.url(forResource: "ca", withExtension: "pem")
	}

	/// Get the bundled server P12 data for sharing to TAK (used as truststore)
	func getBundledServerP12Data() -> Data? {
		let p12URL = Bundle.main.url(forResource: "server", withExtension: "p12", subdirectory: "Certificates")
			?? Bundle.main.url(forResource: "server", withExtension: "p12")

		guard let url = p12URL, let p12Data = try? Data(contentsOf: url) else {
			return nil
		}
		return p12Data
	}

	/// Get the password for bundled certificates (for data package)
	func getBundledCertificatePassword() -> String {
		return bundledPassword
	}

	/// Get the bundled client P12 data for sharing to TAK (for mutual TLS)
	func getBundledClientP12Data() -> Data? {
		let p12URL = Bundle.main.url(forResource: "client", withExtension: "p12", subdirectory: "Certificates")
			?? Bundle.main.url(forResource: "client", withExtension: "p12")

		guard let url = p12URL, let p12Data = try? Data(contentsOf: url) else {
			return nil
		}
		return p12Data
	}

	/// Check if a bundled client certificate exists
	func hasBundledClientCertificate() -> Bool {
		return getBundledClientP12Data() != nil
	}

	// MARK: - Active Certificate Data (for Data Package)

	/// Get the active server P12 data (custom if available, otherwise bundled)
	/// Used for generating data packages
	func getActiveServerP12Data() -> Data? {
		// Check for custom certificate first
		if hasCustomServerCertificate(),
		   let customData = getCustomServerP12DataFromKeychain() {
			Logger.tak.debug("Using custom server P12 for data package")
			return customData
		}
		// Fall back to bundled
		Logger.tak.debug("Using bundled server P12 for data package")
		return getBundledServerP12Data()
	}

	/// Get the active client P12 data (custom if available, otherwise bundled)
	/// Used for generating data packages
	func getActiveClientP12Data() -> Data? {
		// Check for custom certificate first
		if let customData = getCustomClientP12DataFromKeychain() {
			Logger.tak.debug("Using custom client P12 for data package")
			return customData
		}
		// Fall back to bundled
		Logger.tak.debug("Using bundled client P12 for data package")
		return getBundledClientP12Data()
	}

	/// Get the password for the active server certificate
	func getActiveServerCertificatePassword() -> String {
		if hasCustomServerCertificate(),
		   let customPassword = getCustomServerP12PasswordFromKeychain() {
			return customPassword
		}
		return bundledPassword
	}

	/// Get the password for the active client certificate
	func getActiveClientCertificatePassword() -> String {
		if let customPassword = getCustomClientP12PasswordFromKeychain() {
			return customPassword
		}
		return bundledPassword
	}

	/// Import a custom client P12 certificate (for data package generation)
	func importCustomClientP12(data: Data, password: String) {
		storeCustomClientP12InKeychain(p12Data: data, password: password)
		Logger.tak.info("Custom client P12 imported for data package")
	}

	/// Check if custom client P12 is available
	func hasCustomClientP12() -> Bool {
		return getCustomClientP12DataFromKeychain() != nil
	}

	/// Clear custom certificate data (called when resetting to defaults)
	private func clearCustomCertificateData() {
		// Clear server P12 from Keychain
		deleteCustomServerP12FromKeychain()

		// Clear client P12 from Keychain
		deleteCustomClientP12FromKeychain()

		Logger.tak.debug("Cleared custom certificate data")
	}

	// MARK: - Server Identity (PKCS#12)

	/// Import server identity from PKCS#12 (.p12) file data
	/// - Parameters:
	///   - p12Data: The raw PKCS#12 file data
	///   - password: Password to decrypt the PKCS#12 file
	///   - isCustom: Whether this is a user-imported custom certificate (default: true)
	/// - Returns: The imported SecIdentity
	func importServerIdentity(from p12Data: Data, password: String, isCustom: Bool = true) throws -> SecIdentity {
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

		// Store in Keychain for persistence
		try storeServerIdentity(identity, isCustom: isCustom)

		// Store the raw P12 data and password for data package generation (only for custom certs)
		if isCustom {
			storeCustomServerP12InKeychain(p12Data: p12Data, password: password)
			Logger.tak.debug("Stored custom server P12 data for data package generation in Keychain")
		}

		Logger.tak.info("Server identity imported successfully (custom: \(isCustom))")
		return identity
	}

	/// Store custom server PKCS#12 data and its password in the Keychain
	private func storeCustomServerP12InKeychain(p12Data: Data, password: String) {
		let service = "com.meshtastic.tak"

		// Helper to upsert a generic password item
		func upsertKeychainItem(account: String, value: Data) -> OSStatus {
			let deleteQuery: [String: Any] = [
				kSecClass as String: kSecClassGenericPassword,
				kSecAttrService as String: service,
				kSecAttrAccount as String: account
			]
			SecItemDelete(deleteQuery as CFDictionary)

			let addQuery: [String: Any] = [
				kSecClass as String: kSecClassGenericPassword,
				kSecAttrService as String: service,
				kSecAttrAccount as String: account,
				kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
				kSecValueData as String: value
			]

			return SecItemAdd(addQuery as CFDictionary, nil)
		}

		let dataStatus = upsertKeychainItem(account: customServerP12DataKey, value: p12Data)
		if dataStatus != errSecSuccess {
			Logger.tak.error("Failed to store custom server P12 data in Keychain: \(dataStatus)")
		}

		if let passwordData = password.data(using: .utf8) {
			let passwordStatus = upsertKeychainItem(account: customServerP12PasswordKey, value: passwordData)
			if passwordStatus != errSecSuccess {
				Logger.tak.error("Failed to store custom server P12 password in Keychain: \(passwordStatus)")
			}
		} else {
			Logger.tak.error("Failed to encode custom server P12 password as UTF-8 data")
		}
	}

	/// Retrieve custom server P12 data from Keychain
	private func getCustomServerP12DataFromKeychain() -> Data? {
		let service = "com.meshtastic.tak"
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: customServerP12DataKey,
			kSecReturnData as String: true
		]

		var item: CFTypeRef?
		let status = SecItemCopyMatching(query as CFDictionary, &item)

		guard status == errSecSuccess, let data = item as? Data else {
			return nil
		}

		return data
	}

	/// Retrieve custom server P12 password from Keychain
	private func getCustomServerP12PasswordFromKeychain() -> String? {
		let service = "com.meshtastic.tak"
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: customServerP12PasswordKey,
			kSecReturnData as String: true
		]

		var item: CFTypeRef?
		let status = SecItemCopyMatching(query as CFDictionary, &item)

		guard status == errSecSuccess,
			  let data = item as? Data,
			  let password = String(data: data, encoding: .utf8) else {
			return nil
		}

		return password
	}

	/// Delete custom server P12 data from Keychain
	private func deleteCustomServerP12FromKeychain() {
		let service = "com.meshtastic.tak"

		let dataQuery: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: customServerP12DataKey
		]
		SecItemDelete(dataQuery as CFDictionary)

		let passwordQuery: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: customServerP12PasswordKey
		]
		SecItemDelete(passwordQuery as CFDictionary)
	}

	/// Store custom client PKCS#12 data and its password in the Keychain
	private func storeCustomClientP12InKeychain(p12Data: Data, password: String) {
		let service = "com.meshtastic.tak"

		// Helper to upsert a generic password item
		func upsertKeychainItem(account: String, value: Data) -> OSStatus {
			let deleteQuery: [String: Any] = [
				kSecClass as String: kSecClassGenericPassword,
				kSecAttrService as String: service,
				kSecAttrAccount as String: account
			]
			SecItemDelete(deleteQuery as CFDictionary)

			let addQuery: [String: Any] = [
				kSecClass as String: kSecClassGenericPassword,
				kSecAttrService as String: service,
				kSecAttrAccount as String: account,
				kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
				kSecValueData as String: value
			]

			return SecItemAdd(addQuery as CFDictionary, nil)
		}

		let dataStatus = upsertKeychainItem(account: customClientP12DataKey, value: p12Data)
		if dataStatus != errSecSuccess {
			Logger.tak.error("Failed to store custom client P12 data in Keychain: \(dataStatus)")
		}

		if let passwordData = password.data(using: .utf8) {
			let passwordStatus = upsertKeychainItem(account: customClientP12PasswordKey, value: passwordData)
			if passwordStatus != errSecSuccess {
				Logger.tak.error("Failed to store custom client P12 password in Keychain: \(passwordStatus)")
			}
		} else {
			Logger.tak.error("Failed to encode custom client P12 password as UTF-8 data")
		}
	}

	/// Retrieve custom client P12 data from Keychain
	private func getCustomClientP12DataFromKeychain() -> Data? {
		let service = "com.meshtastic.tak"
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: customClientP12DataKey,
			kSecReturnData as String: true
		]

		var item: CFTypeRef?
		let status = SecItemCopyMatching(query as CFDictionary, &item)

		guard status == errSecSuccess, let data = item as? Data else {
			return nil
		}

		return data
	}

	/// Retrieve custom client P12 password from Keychain
	private func getCustomClientP12PasswordFromKeychain() -> String? {
		let service = "com.meshtastic.tak"
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: customClientP12PasswordKey,
			kSecReturnData as String: true
		]

		var item: CFTypeRef?
		let status = SecItemCopyMatching(query as CFDictionary, &item)

		guard status == errSecSuccess,
			  let data = item as? Data,
			  let password = String(data: data, encoding: .utf8) else {
			return nil
		}

		return password
	}

	/// Delete custom client P12 data from Keychain
	private func deleteCustomClientP12FromKeychain() {
		let service = "com.meshtastic.tak"

		let dataQuery: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: customClientP12DataKey
		]
		SecItemDelete(dataQuery as CFDictionary)

		let passwordQuery: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: customClientP12PasswordKey
		]
		SecItemDelete(passwordQuery as CFDictionary)
	}
	/// Store server identity in Keychain
	private func storeServerIdentity(_ identity: SecIdentity, isCustom: Bool = true) throws {
		let tag = isCustom ? serverIdentityCustomTag : serverIdentityTag

		// First delete any existing identity with this tag
		let deleteQuery: [String: Any] = [
			kSecClass as String: kSecClassIdentity,
			kSecAttrLabel as String: tag
		]
		SecItemDelete(deleteQuery as CFDictionary)

		// If storing custom cert, also delete the bundled one (custom takes precedence)
		if isCustom {
			let deleteBundledQuery: [String: Any] = [
				kSecClass as String: kSecClassIdentity,
				kSecAttrLabel as String: serverIdentityTag
			]
			SecItemDelete(deleteBundledQuery as CFDictionary)
		}

		// Add new identity
		let addQuery: [String: Any] = [
			kSecValueRef as String: identity,
			kSecAttrLabel as String: tag,
			kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
		]

		let status = SecItemAdd(addQuery as CFDictionary, nil)
		guard status == errSecSuccess else {
			Logger.tak.error("Failed to store server identity in Keychain: \(status)")
			throw TAKCertificateError.keychainError(status)
		}
	}

	/// Retrieve stored server identity from Keychain
	/// Custom certificates take precedence over bundled ones
	func getServerIdentity() -> SecIdentity? {
		// First try custom certificate
		let customQuery: [String: Any] = [
			kSecClass as String: kSecClassIdentity,
			kSecAttrLabel as String: serverIdentityCustomTag,
			kSecReturnRef as String: true
		]

		var item: CFTypeRef?
		var status = SecItemCopyMatching(customQuery as CFDictionary, &item)

		if status == errSecSuccess {
			return (item as! SecIdentity) // swiftlint:disable:this force_cast
		}

		// Fall back to bundled certificate
		let bundledQuery: [String: Any] = [
			kSecClass as String: kSecClassIdentity,
			kSecAttrLabel as String: serverIdentityTag,
			kSecReturnRef as String: true
		]

		status = SecItemCopyMatching(bundledQuery as CFDictionary, &item)

		guard status == errSecSuccess else {
			if status != errSecItemNotFound {
				Logger.tak.warning("Failed to retrieve server identity: \(status)")
			}
			return nil
		}

		return (item as! SecIdentity) // swiftlint:disable:this force_cast
	}

	/// Check if server certificate is configured
	func hasServerCertificate() -> Bool {
		return getServerIdentity() != nil
	}

	/// Delete custom server identity and reload bundled default
	func deleteServerIdentity() {
		// Delete custom certificate
		let customQuery: [String: Any] = [
			kSecClass as String: kSecClassIdentity,
			kSecAttrLabel as String: serverIdentityCustomTag
		]
		let customStatus = SecItemDelete(customQuery as CFDictionary)

		// Delete bundled certificate too
		let bundledQuery: [String: Any] = [
			kSecClass as String: kSecClassIdentity,
			kSecAttrLabel as String: serverIdentityTag
		]
		let bundledStatus = SecItemDelete(bundledQuery as CFDictionary)

		if customStatus == errSecSuccess || bundledStatus == errSecSuccess {
			Logger.tak.info("Server identity deleted")
		}

		// Reload bundled default
		loadBundledServerIdentity()
	}

	/// Reset to bundled default certificate (deletes custom certificate)
	func resetToDefaultServerCertificate() {
		// Clear custom certificate data from Keychain
		clearCustomCertificateData()

		// Delete custom certificate
		let customQuery: [String: Any] = [
			kSecClass as String: kSecClassIdentity,
			kSecAttrLabel as String: serverIdentityCustomTag
		]
		SecItemDelete(customQuery as CFDictionary)

		// Delete existing bundled and reload
		let bundledQuery: [String: Any] = [
			kSecClass as String: kSecClassIdentity,
			kSecAttrLabel as String: serverIdentityTag
		]
		SecItemDelete(bundledQuery as CFDictionary)

		loadBundledServerIdentity()
		Logger.tak.info("Reset to bundled default server certificate")
	}

	/// Get certificate info for display purposes
	func getServerCertificateInfo() -> String? {
		guard let identity = getServerIdentity() else { return nil }

		var certificate: SecCertificate?
		let status = SecIdentityCopyCertificate(identity, &certificate)
		guard status == errSecSuccess, let cert = certificate else { return nil }

		let isCustom = hasCustomServerCertificate()
		let prefix = isCustom ? "Custom: " : "Default: "

		if let summary = SecCertificateCopySubjectSummary(cert) as String? {
			return prefix + summary
		}

		return prefix + "Certificate loaded"
	}

	// MARK: - Client CA Certificates (PEM)

	/// Import client CA certificate from PEM file data
	/// - Parameter pemData: The raw PEM file data
	/// - Returns: The imported SecCertificate
	func importClientCACertificate(from pemData: Data) throws -> SecCertificate {
		// Extract DER data from PEM format
		let derData = try extractDERFromPEM(pemData)

		guard let certificate = SecCertificateCreateWithData(nil, derData as CFData) else {
			throw TAKCertificateError.invalidCertificate
		}

		// Store in Keychain
		try storeClientCACertificate(certificate)

		Logger.tak.info("Client CA certificate imported successfully")
		return certificate
	}

	/// Extract DER-encoded certificate data from PEM format
	private func extractDERFromPEM(_ pemData: Data) throws -> Data {
		guard let pemString = String(data: pemData, encoding: .utf8) else {
			throw TAKCertificateError.invalidPEM
		}

		// Remove PEM headers and whitespace
		let base64 = pemString
			.replacingOccurrences(of: "-----BEGIN CERTIFICATE-----", with: "")
			.replacingOccurrences(of: "-----END CERTIFICATE-----", with: "")
			.replacingOccurrences(of: "\n", with: "")
			.replacingOccurrences(of: "\r", with: "")
			.trimmingCharacters(in: .whitespaces)

		guard let derData = Data(base64Encoded: base64) else {
			throw TAKCertificateError.invalidPEM
		}

		return derData
	}

	/// Store client CA certificate in Keychain
	private func storeClientCACertificate(_ certificate: SecCertificate) throws {
		let addQuery: [String: Any] = [
			kSecClass as String: kSecClassCertificate,
			kSecValueRef as String: certificate,
			kSecAttrLabel as String: clientCATag,
			kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
		]

		let status = SecItemAdd(addQuery as CFDictionary, nil)

		// Ignore duplicate item errors (certificate already imported)
		guard status == errSecSuccess || status == errSecDuplicateItem else {
			Logger.tak.error("Failed to store client CA certificate: \(status)")
			throw TAKCertificateError.keychainError(status)
		}
	}

	/// Get all stored client CA certificates
	func getClientCACertificates() -> [SecCertificate] {
		let query: [String: Any] = [
			kSecClass as String: kSecClassCertificate,
			kSecAttrLabel as String: clientCATag,
			kSecReturnRef as String: true,
			kSecMatchLimit as String: kSecMatchLimitAll
		]

		var items: CFTypeRef?
		let status = SecItemCopyMatching(query as CFDictionary, &items)

		guard status == errSecSuccess else {
			if status != errSecItemNotFound {
				Logger.tak.warning("Failed to retrieve client CA certificates: \(status)")
			}
			return []
		}

		// Handle both single item and array returns
		if let certificates = items as? [SecCertificate] {
			return certificates
		} else if let certificate = items as! SecCertificate? { // swiftlint:disable:this force_cast
			return [certificate]
		}

		return []
	}

	/// Check if at least one client CA certificate is configured
	func hasClientCACertificate() -> Bool {
		return !getClientCACertificates().isEmpty
	}

	/// Delete all client CA certificates from Keychain
	func deleteClientCACertificates() {
		let query: [String: Any] = [
			kSecClass as String: kSecClassCertificate,
			kSecAttrLabel as String: clientCATag
		]
		let status = SecItemDelete(query as CFDictionary)
		if status == errSecSuccess || status == errSecItemNotFound {
			Logger.tak.info("Client CA certificates deleted")
		}
	}

	/// Get info about stored client CA certificates for display
	func getClientCACertificateInfo() -> [String] {
		let certificates = getClientCACertificates()
		return certificates.compactMap { cert in
			SecCertificateCopySubjectSummary(cert) as String?
		}
	}

	// MARK: - Certificate Validation

	/// Validate a client certificate against the stored CA certificates
	func validateClientCertificate(_ trust: SecTrust) -> Bool {
		let caCertificates = getClientCACertificates()

		guard !caCertificates.isEmpty else {
			Logger.tak.warning("No client CA certificates configured for validation")
			return false
		}

		// Set the anchor certificates (trusted CAs)
		SecTrustSetAnchorCertificates(trust, caCertificates as CFArray)
		SecTrustSetAnchorCertificatesOnly(trust, true)

		var error: CFError?
		let isValid = SecTrustEvaluateWithError(trust, &error)

		if !isValid {
			Logger.tak.warning("Client certificate validation failed: \(error?.localizedDescription ?? "unknown")")
		}

		return isValid
	}
}

// MARK: - Certificate Errors

enum TAKCertificateError: LocalizedError {
	case importFailed(OSStatus)
	case noIdentityFound
	case invalidCertificate
	case invalidPEM
	case keychainError(OSStatus)
	case certificateExpired
	case certificateNotYetValid

	var errorDescription: String? {
		switch self {
		case .importFailed(let status):
			return "Failed to import PKCS#12: \(securityErrorMessage(status))"
		case .noIdentityFound:
			return "No identity (certificate + private key) found in PKCS#12 file"
		case .invalidCertificate:
			return "Invalid certificate data"
		case .invalidPEM:
			return "Invalid PEM format - ensure file contains a valid certificate"
		case .keychainError(let status):
			return "Keychain error: \(securityErrorMessage(status))"
		case .certificateExpired:
			return "Certificate has expired"
		case .certificateNotYetValid:
			return "Certificate is not yet valid"
		}
	}

	private func securityErrorMessage(_ status: OSStatus) -> String {
		if let message = SecCopyErrorMessageString(status, nil) {
			return message as String
		}
		return "Error code: \(status)"
	}
}
