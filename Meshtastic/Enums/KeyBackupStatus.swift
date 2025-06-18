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
			return "Private Key saved successfully to iCloud keychain.".localized
		case .restored:
			return "Private Key restored successfully from iCloud keychain.".localized
		case .deleted:
			return "Private Key deleted successfully from iCloud keychain.".localized
		case .saveFailed:
			return "Private Key failed to save to iCloud keychain.".localized
		case .restoreFailed:
			return "Private Key value not found in iCloud keychain.".localized
		case .deleteFailed:
			return "Private Key failed to delete from iCloud keychain.".localized
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
