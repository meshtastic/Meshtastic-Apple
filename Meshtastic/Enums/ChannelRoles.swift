//
//  ChannelRoles.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/21/22.
//
import Foundation

// Default of 0 is Client
enum ChannelRoles: Int, CaseIterable, Identifiable {

	case disabled = 0
	case primary = 1
	case secondary = 2

	var id: Int { self.rawValue }
	var description: String {
		switch self {

		case .disabled:
			return NSLocalizedString("channel.role.disabled", comment: "Disabled")
		case .primary:
			return NSLocalizedString("channel.role.primary", comment: "Primary")
		case .secondary:
			return NSLocalizedString("channel.role.secondary", comment: "Secondary")
		}
	}
	func protoEnumValue() -> Channel.Role {

		switch self {

		case .disabled:
			return Channel.Role.disabled
		case .primary:
			return Channel.Role.primary
		case .secondary:
			return Channel.Role.secondary
		}
	}
}
