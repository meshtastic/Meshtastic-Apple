//
//  TAKCertificateGenerator.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/1/26.
//

import Foundation
import Security
import CryptoKit
import CommonCrypto

/// The certificates the TAK server and its clients use, issued for one install: a CA, a server
/// identity for 127.0.0.1, a client identity, and the files a TAK client imports.
struct TAKIssuedCertificates: Codable, Equatable {
	/// DER.
	let caCertificate: Data
	/// The CA's private key, PKCS#1, kept so the server certificate can be reissued under the
	/// same CA when it runs out, which the TAK client never notices. It issues nothing else: the
	/// server accepts only the one client certificate below, not anything this CA signed.
	let caPrivateKey: Data
	let serverCertificate: Data
	let serverNotAfter: Date
	let clientCertificate: Data
	/// PKCS#12 with the server certificate, its key and the CA.
	let serverP12: Data
	/// PKCS#12 with the client certificate, its key and the CA: what the TAK client presents.
	let clientP12: Data
	/// PKCS#12 holding only the CA certificate: what the TAK client trusts. No key in it.
	let truststoreP12: Data
	/// The password on all three PKCS#12 files.
	let password: String
}

/// Issues the TAK certificates. Everything is RSA-2048 with SHA-256, and the PKCS#12 files use
/// the SHA-1 and 3DES ciphers from the original standard, which is what ATAK on old Android and
/// iTAK both read; newer AES-based files aren't read everywhere.
enum TAKCertificateGenerator {

	enum IssueError: Error {
		case keyGeneration(String)
		case signing(String)
		case cipher(Int32)
	}

	static let organization = "Meshtastic"
	static let caCommonName = "Meshtastic TAK CA"
	static let serverCommonName = "localhost"
	static let clientCommonName = "Meshtastic TAK Client"
	static let day: TimeInterval = 24 * 60 * 60
	/// Ten years for the CA and the client: they only ever meet each other on one device.
	static let caValidity: TimeInterval = 3650 * day
	/// Apple refuses a TLS server certificate valid for more than 825 days, whatever CA issued
	/// it, and iTAK checks our server by that rule. Two years, and it is reissued before then.
	static let serverValidity: TimeInterval = 730 * day
	/// How long before the server certificate runs out it is reissued.
	static let serverRenewal: TimeInterval = 30 * day

	static func issue(now: Date = .now, serverValidity: TimeInterval = serverValidity) throws -> TAKIssuedCertificates {
		let caKey = try RSAKey()
		let clientKey = try RSAKey()
		let notBefore = now.addingTimeInterval(-day)
		let notAfter = now.addingTimeInterval(caValidity)

		let caName = X509.name(commonName: caCommonName, organization: organization)
		let caCert = try X509.certificate(
			subject: caName, subjectKey: caKey, issuer: X509.Issuer(name: caName, key: caKey),
			validity: X509.Validity(notBefore: notBefore, notAfter: notAfter),
			extensions: [
				X509.basicConstraints(isCA: true),
				X509.keyUsage(bits: X509.KeyUsage.keyCertSign | X509.KeyUsage.cRLSign),
				X509.subjectKeyIdentifier(for: caKey),
				X509.authorityKeyIdentifier(for: caKey)
			])
		let password = randomPassword()
		let server = try serverIdentity(caKey: caKey, caCertificate: caCert, password: password, now: now, validity: serverValidity)
		let clientCert = try X509.certificate(
			subject: X509.name(commonName: clientCommonName, organization: organization), subjectKey: clientKey,
			issuer: X509.Issuer(name: caName, key: caKey),
			validity: X509.Validity(notBefore: notBefore, notAfter: notAfter),
			extensions: [
				X509.basicConstraints(isCA: false),
				X509.keyUsage(bits: X509.KeyUsage.digitalSignature | X509.KeyUsage.keyEncipherment),
				X509.extendedKeyUsage(X509.OID.clientAuth),
				X509.subjectKeyIdentifier(for: clientKey),
				X509.authorityKeyIdentifier(for: caKey)
			])

		return TAKIssuedCertificates(
			caCertificate: caCert,
			caPrivateKey: try caKey.privateKeyDER(),
			serverCertificate: server.certificate,
			serverNotAfter: server.notAfter,
			clientCertificate: clientCert,
			serverP12: server.p12,
			clientP12: try PKCS12.encode(certificates: [clientCert, caCert], privateKey: try clientKey.pkcs8(), password: password, friendlyName: clientCommonName),
			truststoreP12: try PKCS12.encode(certificates: [caCert], privateKey: nil, password: password, friendlyName: caCommonName),
			password: password
		)
	}

	/// Whether the server certificate is close enough to running out to be reissued.
	static func serverNeedsReissue(_ issued: TAKIssuedCertificates, now: Date = .now) -> Bool {
		issued.serverNotAfter.timeIntervalSince(now) < serverRenewal
	}

	/// The same CA and client with a new server certificate and key. The TAK client keeps its
	/// files: it trusts the CA, not the server certificate.
	static func reissueServer(_ issued: TAKIssuedCertificates, now: Date = .now) throws -> TAKIssuedCertificates {
		let caKey = try RSAKey(privateKeyDER: issued.caPrivateKey)
		let server = try serverIdentity(caKey: caKey, caCertificate: issued.caCertificate, password: issued.password, now: now, validity: serverValidity)
		return TAKIssuedCertificates(
			caCertificate: issued.caCertificate,
			caPrivateKey: issued.caPrivateKey,
			serverCertificate: server.certificate,
			serverNotAfter: server.notAfter,
			clientCertificate: issued.clientCertificate,
			serverP12: server.p12,
			clientP12: issued.clientP12,
			truststoreP12: issued.truststoreP12,
			password: issued.password
		)
	}

	private struct ServerIdentity {
		let certificate: Data
		let notAfter: Date
		let p12: Data
	}

	private static func serverIdentity(
		caKey: RSAKey, caCertificate: Data, password: String, now: Date, validity: TimeInterval
	) throws -> ServerIdentity {
		let serverKey = try RSAKey()
		let notAfter = now.addingTimeInterval(validity)
		let caName = X509.name(commonName: caCommonName, organization: organization)
		let certificate = try X509.certificate(
			subject: X509.name(commonName: serverCommonName, organization: organization), subjectKey: serverKey,
			issuer: X509.Issuer(name: caName, key: caKey),
			validity: X509.Validity(notBefore: now.addingTimeInterval(-day), notAfter: notAfter),
			extensions: [
				X509.basicConstraints(isCA: false),
				X509.keyUsage(bits: X509.KeyUsage.digitalSignature | X509.KeyUsage.keyEncipherment),
				X509.extendedKeyUsage(X509.OID.serverAuth),
				X509.subjectAltName(dnsName: "localhost", ipv4: [127, 0, 0, 1]),
				X509.subjectKeyIdentifier(for: serverKey),
				X509.authorityKeyIdentifier(for: caKey)
			])
		let p12 = try PKCS12.encode(certificates: [certificate, caCertificate], privateKey: try serverKey.pkcs8(), password: password, friendlyName: "Meshtastic TAK Server")
		return ServerIdentity(certificate: certificate, notAfter: notAfter, p12: p12)
	}

	/// A PKCS#12 holding only certificates, under `password`: a truststore for a TAK client.
	static func truststore(certificates: [Data], password: String, friendlyName: String) throws -> Data {
		try PKCS12.encode(certificates: certificates, privateKey: nil, password: password, friendlyName: friendlyName)
	}

	/// Twenty letters and digits from the system's random source.
	static func randomPassword() -> String {
		let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789")
		var generator = SystemRandomNumberGenerator()
		return String((0..<20).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &generator)] })
	}

	static func randomBytes(_ count: Int) -> Data {
		var bytes = [UInt8](repeating: 0, count: count)
		_ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
		return Data(bytes)
	}
}

// MARK: - Keys

/// An RSA-2048 key pair that lives only in memory.
struct RSAKey {
	let key: SecKey

	init() throws {
		let attributes: [String: Any] = [
			kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
			kSecAttrKeySizeInBits as String: 2048,
			kSecAttrIsPermanent as String: false
		]
		var error: Unmanaged<CFError>?
		guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
			throw TAKCertificateGenerator.IssueError.keyGeneration(error?.takeRetainedValue().localizedDescription ?? "unknown")
		}
		self.key = key
	}

	/// A key kept earlier as PKCS#1.
	init(privateKeyDER: Data) throws {
		let attributes: [String: Any] = [
			kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
			kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
			kSecAttrKeySizeInBits as String: 2048
		]
		var error: Unmanaged<CFError>?
		guard let key = SecKeyCreateWithData(privateKeyDER as CFData, attributes as CFDictionary, &error) else {
			throw TAKCertificateGenerator.IssueError.keyGeneration(error?.takeRetainedValue().localizedDescription ?? "unreadable key")
		}
		self.key = key
	}

	/// PKCS#1 RSAPrivateKey.
	func privateKeyDER() throws -> Data {
		var error: Unmanaged<CFError>?
		guard let data = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
			throw TAKCertificateGenerator.IssueError.keyGeneration(error?.takeRetainedValue().localizedDescription ?? "export")
		}
		return data
	}

	/// PKCS#1 RSAPublicKey.
	func publicKeyDER() throws -> Data {
		guard let publicKey = SecKeyCopyPublicKey(key) else {
			throw TAKCertificateGenerator.IssueError.keyGeneration("no public key")
		}
		var error: Unmanaged<CFError>?
		guard let data = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
			throw TAKCertificateGenerator.IssueError.keyGeneration(error?.takeRetainedValue().localizedDescription ?? "export")
		}
		return data
	}

	/// SubjectPublicKeyInfo.
	func subjectPublicKeyInfo() throws -> Data {
		DER.sequence([X509.rsaAlgorithm, DER.bitString(try publicKeyDER())])
	}

	/// PKCS#8 PrivateKeyInfo, unencrypted.
	func pkcs8() throws -> Data {
		DER.sequence([DER.integer(0), X509.rsaAlgorithm, DER.octetString(try privateKeyDER())])
	}

	/// SHA-1 of the public key, the usual key identifier.
	func keyIdentifier() throws -> Data {
		Data(Insecure.SHA1.hash(data: try publicKeyDER()))
	}

	func sign(_ message: Data) throws -> Data {
		var error: Unmanaged<CFError>?
		guard let signature = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, message as CFData, &error) as Data? else {
			throw TAKCertificateGenerator.IssueError.signing(error?.takeRetainedValue().localizedDescription ?? "unknown")
		}
		return signature
	}
}

// MARK: - X.509

enum X509 {
	enum OID {
		static let rsaEncryption = "1.2.840.113549.1.1.1"
		static let sha256WithRSA = "1.2.840.113549.1.1.11"
		static let commonName = "2.5.4.3"
		static let organization = "2.5.4.10"
		static let basicConstraints = "2.5.29.19"
		static let keyUsage = "2.5.29.15"
		static let extendedKeyUsage = "2.5.29.37"
		static let subjectAltName = "2.5.29.17"
		static let subjectKeyIdentifier = "2.5.29.14"
		static let authorityKeyIdentifier = "2.5.29.35"
		static let serverAuth = "1.3.6.1.5.5.7.3.1"
		static let clientAuth = "1.3.6.1.5.5.7.3.2"
	}

	/// KeyUsage bits, numbered as in RFC 5280, as a byte with bit 0 at the top.
	enum KeyUsage {
		static let digitalSignature: UInt8 = 0b1000_0000
		static let keyEncipherment: UInt8 = 0b0010_0000
		static let keyCertSign: UInt8 = 0b0000_0100
		static let cRLSign: UInt8 = 0b0000_0010
	}

	static let rsaAlgorithm = DER.sequence([DER.oid(OID.rsaEncryption), DER.null])
	static let signatureAlgorithm = DER.sequence([DER.oid(OID.sha256WithRSA), DER.null])

	static func name(commonName: String, organization: String) -> Data {
		DER.sequence([
			DER.set([DER.sequence([DER.oid(OID.organization), DER.utf8String(organization)])]),
			DER.set([DER.sequence([DER.oid(OID.commonName), DER.utf8String(commonName)])])
		])
	}

	struct Issuer {
		let name: Data
		let key: RSAKey
	}

	struct Validity {
		let notBefore: Date
		let notAfter: Date
	}

	static func certificate(subject: Data, subjectKey: RSAKey, issuer: Issuer, validity: Validity, extensions: [Data]) throws -> Data {
		let tbs = DER.sequence([
			DER.explicit(0, DER.integer(2)),
			DER.integer(serialNumber()),
			signatureAlgorithm,
			issuer.name,
			DER.sequence([DER.utcTime(validity.notBefore), DER.utcTime(validity.notAfter)]),
			subject,
			try subjectKey.subjectPublicKeyInfo(),
			DER.explicit(3, DER.sequence(extensions))
		])
		return DER.sequence([tbs, signatureAlgorithm, DER.bitString(try issuer.key.sign(tbs))])
	}

	/// A positive 16-byte serial number, random so no two issues share one.
	static func serialNumber() -> Data {
		var serial = TAKCertificateGenerator.randomBytes(16)
		serial[0] &= 0x7F
		serial[0] |= 0x40
		return serial
	}

	static func ext(_ oid: String, critical: Bool, _ value: Data) -> Data {
		DER.sequence([DER.oid(oid)] + (critical ? [DER.boolean(true)] : []) + [DER.octetString(value)])
	}

	static func basicConstraints(isCA: Bool) -> Data {
		ext(OID.basicConstraints, critical: true, DER.sequence(isCA ? [DER.boolean(true)] : []))
	}

	static func keyUsage(bits: UInt8) -> Data {
		ext(OID.keyUsage, critical: true, DER.bitString(Data([bits]), unusedBits: UInt8(bits.trailingZeroBitCount)))
	}

	static func extendedKeyUsage(_ purpose: String) -> Data {
		ext(OID.extendedKeyUsage, critical: false, DER.sequence([DER.oid(purpose)]))
	}

	static func subjectAltName(dnsName: String, ipv4: [UInt8]) -> Data {
		ext(OID.subjectAltName, critical: false, DER.sequence([
			DER.implicit(2, Data(dnsName.utf8)),
			DER.implicit(7, Data(ipv4))
		]))
	}

	static func subjectKeyIdentifier(for key: RSAKey) throws -> Data {
		ext(OID.subjectKeyIdentifier, critical: false, DER.octetString(try key.keyIdentifier()))
	}

	static func authorityKeyIdentifier(for key: RSAKey) throws -> Data {
		ext(OID.authorityKeyIdentifier, critical: false, DER.sequence([DER.implicit(0, try key.keyIdentifier())]))
	}
}

// MARK: - PKCS#12

enum PKCS12 {
	enum OID {
		static let data = "1.2.840.113549.1.7.1"
		static let encryptedData = "1.2.840.113549.1.7.6"
		static let pbeWithSHAAnd3KeyTripleDESCBC = "1.2.840.113549.1.12.1.3"
		static let certBag = "1.2.840.113549.1.12.10.1.3"
		static let pkcs8ShroudedKeyBag = "1.2.840.113549.1.12.10.1.2"
		static let x509Certificate = "1.2.840.113549.1.9.22.1"
		static let friendlyName = "1.2.840.113549.1.9.20"
		static let localKeyId = "1.2.840.113549.1.9.21"
		static let sha1 = "1.3.14.3.2.26"
	}

	static let iterations = 2048

	/// A PKCS#12 file: the certificates, first one the leaf, in an encrypted safe, and the leaf's
	/// private key, when there is one, in a shrouded key bag. Both under `password`.
	static func encode(certificates: [Data], privateKey: Data?, password: String, friendlyName: String) throws -> Data {
		let localKeyId = DER.octetString(Data(Insecure.SHA1.hash(data: certificates[0])))
		let name = DER.sequence([DER.oid(OID.friendlyName), DER.set([DER.bmpString(friendlyName)])])
		let keyId = DER.sequence([DER.oid(OID.localKeyId), DER.set([localKeyId])])

		let certBags = certificates.enumerated().map { index, cert in
			DER.sequence([
				DER.oid(OID.certBag),
				DER.explicit(0, DER.sequence([DER.oid(OID.x509Certificate), DER.explicit(0, DER.octetString(cert))])),
				DER.set(index == 0 && privateKey != nil ? [name, keyId] : [name])
			])
		}
		var safes = [try encryptedData(DER.sequence(certBags), password: password)]

		if let privateKey {
			let salt = TAKCertificateGenerator.randomBytes(8)
			let shrouded = DER.sequence([
				pbeAlgorithm(salt: salt),
				DER.octetString(try PBE.encrypt(privateKey, password: password, salt: salt))
			])
			let keyBag = DER.sequence([
				DER.oid(OID.pkcs8ShroudedKeyBag),
				DER.explicit(0, shrouded),
				DER.set([name, keyId])
			])
			safes.append(DER.sequence([DER.oid(OID.data), DER.explicit(0, DER.octetString(DER.sequence([keyBag])))]))
		}

		let authenticatedSafe = DER.sequence(safes)
		let macSalt = TAKCertificateGenerator.randomBytes(8)
		let macKey = PBE.derive(password: password, salt: macSalt, id: 3, length: 20)
		let mac = Data(HMAC<Insecure.SHA1>.authenticationCode(for: authenticatedSafe, using: SymmetricKey(data: macKey)))
		let macData = DER.sequence([
			DER.sequence([DER.sequence([DER.oid(OID.sha1), DER.null]), DER.octetString(mac)]),
			DER.octetString(macSalt),
			DER.integer(iterations)
		])
		return DER.sequence([
			DER.integer(3),
			DER.sequence([DER.oid(OID.data), DER.explicit(0, DER.octetString(authenticatedSafe))]),
			macData
		])
	}

	private static func pbeAlgorithm(salt: Data) -> Data {
		DER.sequence([
			DER.oid(OID.pbeWithSHAAnd3KeyTripleDESCBC),
			DER.sequence([DER.octetString(salt), DER.integer(iterations)])
		])
	}

	private static func encryptedData(_ content: Data, password: String) throws -> Data {
		let salt = TAKCertificateGenerator.randomBytes(8)
		let encrypted = try PBE.encrypt(content, password: password, salt: salt)
		return DER.sequence([
			DER.oid(OID.encryptedData),
			DER.explicit(0, DER.sequence([
				DER.integer(0),
				DER.sequence([DER.oid(OID.data), pbeAlgorithm(salt: salt), DER.implicit(0, encrypted)])
			]))
		])
	}

	/// pbeWithSHAAnd3-KeyTripleDES-CBC, with the key derivation from RFC 7292 appendix B.
	enum PBE {
		static func encrypt(_ plaintext: Data, password: String, salt: Data) throws -> Data {
			let key = derive(password: password, salt: salt, id: 1, length: 24)
			let iv = derive(password: password, salt: salt, id: 2, length: 8)
			var out = [UInt8](repeating: 0, count: plaintext.count + kCCBlockSize3DES)
			var written = 0
			let status = key.withUnsafeBytes { keyBytes in
				iv.withUnsafeBytes { ivBytes in
					plaintext.withUnsafeBytes { inBytes in
						CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithm3DES), CCOptions(kCCOptionPKCS7Padding),
								keyBytes.baseAddress, kCCKeySize3DES, ivBytes.baseAddress,
								inBytes.baseAddress, plaintext.count, &out, out.count, &written)
					}
				}
			}
			guard status == kCCSuccess else { throw TAKCertificateGenerator.IssueError.cipher(status) }
			return Data(out[0..<written])
		}

		/// `id` is 1 for a key, 2 for an IV and 3 for the MAC key.
		static func derive(password: String, salt: Data, id: UInt8, length: Int) -> Data {
			let u = 20, v = 64
			// The password as UTF-16BE with a terminating zero, as the standard says.
			var passwordBytes = Data()
			for unit in password.utf16 {
				passwordBytes.append(UInt8(unit >> 8))
				passwordBytes.append(UInt8(unit & 0xFF))
			}
			passwordBytes.append(contentsOf: [0, 0])

			func repeated(_ data: Data) -> Data {
				guard !data.isEmpty else { return Data() }
				let blocks = (data.count + v - 1) / v
				var out = Data(capacity: blocks * v)
				while out.count < blocks * v {
					out.append(data.prefix(blocks * v - out.count))
				}
				return out
			}
			let diversifier = Data(repeating: id, count: v)
			var combined = repeated(salt) + repeated(passwordBytes)
			var result = Data()
			let rounds = (length + u - 1) / u
			for _ in 0..<rounds {
				var hash = Data(Insecure.SHA1.hash(data: diversifier + combined))
				for _ in 1..<PKCS12.iterations {
					hash = Data(Insecure.SHA1.hash(data: hash))
				}
				result.append(hash)
				var block = Data()
				while block.count < v { block.append(hash.prefix(v - block.count)) }
				// Add block + 1 to each v-byte piece of the combined input, as big numbers.
				for offset in stride(from: 0, to: combined.count, by: v) {
					var carry: UInt16 = 1
					for index in stride(from: v - 1, through: 0, by: -1) {
						let sum = UInt16(combined[offset + index]) + UInt16(block[index]) + carry
						combined[offset + index] = UInt8(sum & 0xFF)
						carry = sum >> 8
					}
				}
			}
			return result.prefix(length)
		}
	}
}

// MARK: - DER

/// Just enough DER to write certificates and PKCS#12 files.
enum DER {
	static let null = Data([0x05, 0x00])

	static func tlv(_ tag: UInt8, _ content: Data) -> Data {
		var out = Data([tag])
		let count = content.count
		if count < 0x80 {
			out.append(UInt8(count))
		} else {
			var lengthBytes = [UInt8]()
			var remaining = count
			while remaining > 0 {
				lengthBytes.insert(UInt8(remaining & 0xFF), at: 0)
				remaining >>= 8
			}
			out.append(0x80 | UInt8(lengthBytes.count))
			out.append(contentsOf: lengthBytes)
		}
		out.append(content)
		return out
	}

	static func sequence(_ items: [Data]) -> Data { tlv(0x30, items.reduce(Data(), +)) }
	static func set(_ items: [Data]) -> Data { tlv(0x31, items.reduce(Data(), +)) }
	static func octetString(_ data: Data) -> Data { tlv(0x04, data) }
	static func boolean(_ value: Bool) -> Data { tlv(0x01, Data([value ? 0xFF : 0x00])) }
	static func utf8String(_ string: String) -> Data { tlv(0x0C, Data(string.utf8)) }
	/// Constructed, context-specific.
	static func explicit(_ tag: UInt8, _ content: Data) -> Data { tlv(0xA0 | tag, content) }
	/// Primitive, context-specific.
	static func implicit(_ tag: UInt8, _ content: Data) -> Data { tlv(0x80 | tag, content) }

	static func integer(_ value: Int) -> Data {
		var bytes = [UInt8]()
		var remaining = value
		repeat {
			bytes.insert(UInt8(remaining & 0xFF), at: 0)
			remaining >>= 8
		} while remaining > 0
		if bytes[0] & 0x80 != 0 { bytes.insert(0, at: 0) }
		return tlv(0x02, Data(bytes))
	}

	/// A positive integer from big-endian bytes.
	static func integer(_ magnitude: Data) -> Data {
		var bytes = magnitude
		while bytes.count > 1, bytes[0] == 0, bytes[1] & 0x80 == 0 { bytes.removeFirst() }
		if bytes.first.map({ $0 & 0x80 != 0 }) ?? true { bytes.insert(0, at: 0) }
		return tlv(0x02, bytes)
	}

	static func bitString(_ data: Data, unusedBits: UInt8 = 0) -> Data {
		tlv(0x03, Data([unusedBits]) + data)
	}

	static func bmpString(_ string: String) -> Data {
		var bytes = Data()
		for unit in string.utf16 {
			bytes.append(UInt8(unit >> 8))
			bytes.append(UInt8(unit & 0xFF))
		}
		return tlv(0x1E, bytes)
	}

	static func utcTime(_ date: Date) -> Data {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(identifier: "UTC")
		formatter.dateFormat = "yyMMddHHmmss'Z'"
		return tlv(0x17, Data(formatter.string(from: date).utf8))
	}

	static func oid(_ dotted: String) -> Data {
		let parts = dotted.split(separator: ".").map { Int($0)! }
		var bytes = [UInt8(parts[0] * 40 + parts[1])]
		for part in parts.dropFirst(2) {
			var encoded = [UInt8(part & 0x7F)]
			var remaining = part >> 7
			while remaining > 0 {
				encoded.insert(UInt8(remaining & 0x7F) | 0x80, at: 0)
				remaining >>= 7
			}
			bytes.append(contentsOf: encoded)
		}
		return tlv(0x06, Data(bytes))
	}
}
