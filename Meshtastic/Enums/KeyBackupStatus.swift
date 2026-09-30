//
//  iCloudStats.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 6/18/25.
//

enum KeyBackupStatus: String, CaseIterable, Equatable, Decodable {
	case saved
	case restored
	case deleted
	case saveFailed
	case restoreFailed
	case deleteFailed
	var description: String {
		switch self {
		case .saved:
			return String(localized: "Private Key saved successfully to iCloud keychain.", comment: "KeyBackupStatus.description")
		case .restored:
			return String(localized: "Private Key restored successfully from iCloud keychain.", comment: "KeyBackupStatus.description")
		case .deleted:
			return String(localized: "Private Key deleted successfully from iCloud keychain.", comment: "KeyBackupStatus.description")
		case .saveFailed:
			return String(localized: "Private Key failed to save to iCloud keychain.", comment: "KeyBackupStatus.description")
		case .restoreFailed:
			return String(localized: "Private Key value not found in iCloud keychain.", comment: "KeyBackupStatus.description")
		case .deleteFailed:
			return String(localized: "Private Key failed to delete from iCloud keychain.", comment: "KeyBackupStatus.description")
		}
	}
	var success: Bool {
		switch self {
		case .saved:
			return true
		case .restored:
			return true
		case .deleted:
			return true
		case .saveFailed:
			return false
		case .restoreFailed:
			return false
		case .deleteFailed:
			return false
		}
	}
}
