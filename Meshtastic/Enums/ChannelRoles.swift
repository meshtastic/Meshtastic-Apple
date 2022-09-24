//
//  ChannelRoles.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/21/22.
//

// Default of 0 is Client
enum ChannelRoles: Int, CaseIterable, Identifiable {

	case disabled = 0
	case primary = 1
	case secondary = 2

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
			
			case .disabled:
				return "Disabled"
			case .primary:
				return "Primary"
			case .secondary:
				return "Secondary"
			}
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
