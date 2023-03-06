//
//  CannedMessagesConfigEnums.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/10/22.
//
import Foundation

// Default of 0 is unset
enum ConfigPresets: Int, CaseIterable, Identifiable {

	case unset = 0
	case rakRotaryEncoder = 1
	case cardKB = 2

	var id: Int { self.rawValue }
	var description: String {
		switch self {

		case .unset:
			return NSLocalizedString("canned.messages.preset.manual", comment: "Manual Configuration")
		case .rakRotaryEncoder:
			return NSLocalizedString("canned.messages.preset.rakrotary", comment: "RAK Rotary Encoder Module")
		case .cardKB:
			return NSLocalizedString("canned.messages.preset.cardkb", comment: "M5 Stack Card KB / RAK Keypad")
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
			return NSLocalizedString("inputevent.none", comment: "None")
		case .up:
			return NSLocalizedString("inputevent.up", comment: "Up")
		case .down:
			return NSLocalizedString("inputevent.down", comment: "Down")
		case .left:
			return NSLocalizedString("inputevent.left", comment: "Left")
		case .right:
			return NSLocalizedString("inputevent.right", comment: "Right")
		case .select:
			return NSLocalizedString("inputevent.select", comment: "Select")
		case .back:
			return NSLocalizedString("inputevent.back", comment: "Back")
		case .cancel:
			return NSLocalizedString("inputevent.cancel", comment: "Cancel")
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
