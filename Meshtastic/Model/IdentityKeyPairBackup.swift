//
//  IdentityKeyPairBackup.swift
//  Meshtastic
//

// MARK: IdentityKeyPairBackup

import CryptoKit
import Foundation

struct IdentityKeyPairBackup: Codable, Equatable {
	let privateKey: Data
	let publicKey: Data

	static func isValid(privateKey: Data, publicKey: Data) -> Bool {
		guard privateKey.count == 32, publicKey.count == 32 else {
			return false
		}

		do {
			let derivedPublicKey = try Curve25519.KeyAgreement.PrivateKey(
				rawRepresentation: privateKey
			).publicKey.rawRepresentation
			return derivedPublicKey == publicKey
		} catch {
			return false
		}
	}

	static func isAbsentOrValid(privateKey: Data, publicKey: Data) -> Bool {
		(privateKey.isEmpty && publicKey.isEmpty) || isValid(privateKey: privateKey, publicKey: publicKey)
	}
}
