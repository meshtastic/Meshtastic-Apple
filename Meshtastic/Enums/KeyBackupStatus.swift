//
//  KeyBackupStatus.swift
//  Meshtastic
//

import Foundation
import CryptoKit

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
}

enum KeyBackupStatus: Equatable {
	case saved
	case saveFailed

	var description: String {
		switch self {
		case .saved:
			return "Identity key pair backed up to iCloud Keychain.".localized
		case .saveFailed:
			return "Identity key pair could not be backed up to iCloud Keychain.".localized
		}
	}

	var success: Bool {
		switch self {
		case .saved:
			return true
		case .saveFailed:
			return false
		}
	}
}
