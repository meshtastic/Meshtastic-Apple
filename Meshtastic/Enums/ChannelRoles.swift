//
//  ChannelRoles.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/21/22.
//
import Foundation
import MeshtasticProtobufs

// Default of 0 is Client
enum ChannelRoles: Int, CaseIterable, Identifiable {

	case disabled = 0
	case primary = 1
	case secondary = 2

	var id: Int { self.rawValue }
	var description: String {
		switch self {

		case .disabled:
			return "channel.role.disabled".localized
		case .primary:
			return "channel.role.primary".localized
		case .secondary:
			return "channel.role.secondary".localized
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
