//
//  CannedMessagesConfigEnums.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/10/22.
//
import Foundation
import MeshtasticProtobufs

// Default of 0 is unset
enum ConfigPresets: Int, CaseIterable, Identifiable {

	case unset = 0
	case rakRotaryEncoder = 1
	case cardKB = 2

	var id: Int { self.rawValue }
	var description: String {
		switch self {

		case .unset:
			return "canned.messages.preset.manual".localized
		case .rakRotaryEncoder:
			return "canned.messages.preset.rakrotary".localized
		case .cardKB:
			return "canned.messages.preset.cardkb".localized
		}
	}
}

// Default of 0 is off
enum InputEventChars: Int, CaseIterable, Identifiable {

	case none = 0
	case up = 17
	case down = 18
	case left = 19
	case right = 20
	case select = 10
	case back = 27
	case cancel = 24

	var id: Int { self.rawValue }
	var description: String {
		switch self {

		case .none:
			return "inputevent.none".localized
		case .up:
			return "inputevent.up".localized
		case .down:
			return "inputevent.down".localized
		case .left:
			return "inputevent.left".localized
		case .right:
			return "inputevent.right".localized
		case .select:
			return "inputevent.select".localized
		case .back:
			return "inputevent.back".localized
		case .cancel:
			return "inputevent.cancel".localized
		}
	}
	func protoEnumValue() -> ModuleConfig.CannedMessageConfig.InputEventChar {

		switch self {

		case .none:
			return ModuleConfig.CannedMessageConfig.InputEventChar.none
		case .up:
			return ModuleConfig.CannedMessageConfig.InputEventChar.up
		case .down:
			return ModuleConfig.CannedMessageConfig.InputEventChar.down
		case .left:
			return ModuleConfig.CannedMessageConfig.InputEventChar.left
		case .right:
			return ModuleConfig.CannedMessageConfig.InputEventChar.right
		case .select:
			return ModuleConfig.CannedMessageConfig.InputEventChar.select
		case .back:
			return ModuleConfig.CannedMessageConfig.InputEventChar.back
		case .cancel:
			return ModuleConfig.CannedMessageConfig.InputEventChar.cancel
		}
	}
}
