//
//  KeyBackupStatus.swift
//  Meshtastic
//

import Foundation

struct IdentityKeyPairBackup: Codable, Equatable {
	let privateKey: Data
	let publicKey: Data
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
