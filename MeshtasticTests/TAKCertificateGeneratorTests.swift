//
//  TAKCertificateGeneratorTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/1/26.
//

import Foundation
import Security
import Testing
@testable import Meshtastic

@Suite("TAK certificates issued per install")
struct TAKCertificateGeneratorTests {

	private func certificate(_ der: Data) throws -> SecCertificate {
		try #require(SecCertificateCreateWithData(nil, der as CFData))
	}

	/// Evaluates `leaf` against `policy` with the CA as the only anchor.
	private func trusts(_ leaf: Data, ca: Data, policy: SecPolicy) throws -> Bool {
		var trust: SecTrust?
		let status = SecTrustCreateWithCertificates([try certificate(leaf), try certificate(ca)] as CFArray, policy, &trust)
		#expect(status == errSecSuccess)
		let evaluated = try #require(trust)
		SecTrustSetAnchorCertificates(evaluated, [try certificate(ca)] as CFArray)
		SecTrustSetAnchorCertificatesOnly(evaluated, true)
		return SecTrustEvaluateWithError(evaluated, nil)
	}

	@Test("The server certificate is good for localhost and the client for client auth, both under the CA")
	func chainValidates() throws {
		let issued = try TAKCertificateGenerator.issue()
		#expect(try trusts(issued.serverCertificate, ca: issued.caCertificate, policy: SecPolicyCreateSSL(true, "localhost" as CFString)))
		#expect(try trusts(issued.clientCertificate, ca: issued.caCertificate, policy: SecPolicyCreateSSL(false, nil)))
		// Each leaf is for one job only.
		#expect(try !trusts(issued.clientCertificate, ca: issued.caCertificate, policy: SecPolicyCreateSSL(true, "localhost" as CFString)))
		#expect(try !trusts(issued.serverCertificate, ca: issued.caCertificate, policy: SecPolicyCreateSSL(false, nil)))
		// A leaf from another install is not trusted under this CA.
		let other = try TAKCertificateGenerator.issue()
		#expect(try !trusts(other.clientCertificate, ca: issued.caCertificate, policy: SecPolicyCreateSSL(false, nil)))
	}

	@Test("The identity files import with the password and carry the leaf and the CA")
	func identitiesImport() throws {
		let issued = try TAKCertificateGenerator.issue()
		for (p12, leaf) in [(issued.serverP12, issued.serverCertificate), (issued.clientP12, issued.clientCertificate)] {
			var items: CFArray?
			let status = SecPKCS12Import(p12 as CFData, [kSecImportExportPassphrase as String: issued.password] as CFDictionary, &items)
			#expect(status == errSecSuccess)
			let first = try #require((items as? [[String: Any]])?.first)
			let identity = try #require(first[kSecImportItemIdentity as String]).self as! SecIdentity // swiftlint:disable:this force_cast
			var cert: SecCertificate?
			#expect(SecIdentityCopyCertificate(identity, &cert) == errSecSuccess)
			#expect(SecCertificateCopyData(try #require(cert)) as Data == leaf)
			let chain = first[kSecImportItemCertChain as String] as? [SecCertificate]
			#expect(chain?.count == 2)
		}
		var items: CFArray?
		#expect(SecPKCS12Import(issued.clientP12 as CFData, [kSecImportExportPassphrase as String: "wrong"] as CFDictionary, &items) != errSecSuccess)
	}

	@Test("The truststore holds the CA and no key, in the ciphers every TAK client reads")
	func truststoreHasNoKey() throws {
		let issued = try TAKCertificateGenerator.issue()
		let keyBag = DER.oid(PKCS12.OID.pkcs8ShroudedKeyBag)
		let legacyCipher = DER.oid(PKCS12.OID.pbeWithSHAAnd3KeyTripleDESCBC)
		#expect(issued.truststoreP12.range(of: keyBag) == nil)
		#expect(issued.clientP12.range(of: keyBag) != nil)
		#expect(issued.serverP12.range(of: keyBag) != nil)
		for p12 in [issued.truststoreP12, issued.clientP12, issued.serverP12] {
			#expect(p12.range(of: legacyCipher) != nil)
		}
		var items: CFArray?
		let status = SecPKCS12Import(issued.truststoreP12 as CFData, [kSecImportExportPassphrase as String: issued.password] as CFDictionary, &items)
		if status == errSecSuccess, let first = (items as? [[String: Any]])?.first {
			#expect(first[kSecImportItemIdentity as String] == nil)
		}
	}

	@Test("Every issue is its own: new keys, serials and password")
	func eachIssueIsNew() throws {
		let a = try TAKCertificateGenerator.issue()
		let b = try TAKCertificateGenerator.issue()
		#expect(a.caCertificate != b.caCertificate)
		#expect(a.clientCertificate != b.clientCertificate)
		#expect(a.password != b.password)
		#expect(a.password.count == 20)
	}

	@Test("The server certificate stays within Apple's 825-day limit for TLS servers")
	func serverValidityFitsApple() throws {
		// Apple's SSL policy refuses a server certificate valid for more than 825 days, whatever
		// CA issued it, and iTAK checks the server with that policy.
		let tooLong = try TAKCertificateGenerator.issue(serverValidity: 826 * TAKCertificateGenerator.day)
		#expect(try !trusts(tooLong.serverCertificate, ca: tooLong.caCertificate, policy: SecPolicyCreateSSL(true, "localhost" as CFString)))
		let issued = try TAKCertificateGenerator.issue()
		#expect(try trusts(issued.serverCertificate, ca: issued.caCertificate, policy: SecPolicyCreateSSL(true, "127.0.0.1" as CFString)))
	}

	@Test("Reissuing the server keeps the CA, the client and the password; the new server is trusted under the old CA")
	func reissueKeepsClient() throws {
		let issued = try TAKCertificateGenerator.issue()
		#expect(!TAKCertificateGenerator.serverNeedsReissue(issued))
		let nearly = issued.serverNotAfter.addingTimeInterval(-TAKCertificateGenerator.serverRenewal + 60)
		#expect(TAKCertificateGenerator.serverNeedsReissue(issued, now: nearly))

		let reissued = try TAKCertificateGenerator.reissueServer(issued)
		#expect(reissued.caCertificate == issued.caCertificate)
		#expect(reissued.clientP12 == issued.clientP12)
		#expect(reissued.truststoreP12 == issued.truststoreP12)
		#expect(reissued.password == issued.password)
		#expect(reissued.serverCertificate != issued.serverCertificate)
		#expect(try trusts(reissued.serverCertificate, ca: issued.caCertificate, policy: SecPolicyCreateSSL(true, "localhost" as CFString)))
	}

	@Test("The issued set round-trips through the form it is kept in")
	func storesAndLoads() throws {
		let issued = try TAKCertificateGenerator.issue()
		let data = try JSONEncoder().encode(issued)
		#expect(try JSONDecoder().decode(TAKIssuedCertificates.self, from: data) == issued)
	}
}
