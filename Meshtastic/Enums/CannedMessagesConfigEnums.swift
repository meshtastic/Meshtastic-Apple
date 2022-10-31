//
//  CannedMessagesConfigEnums.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/10/22.
//

// Default of 0 is unset
enum ConfigPresets : Int, CaseIterable, Identifiable {

	case unset = 0
	case rakRotaryEncoder = 1
	case cardKB = 2
	
	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
			
			case .unset:
				return "Manual Configuration"
			case .rakRotaryEncoder:
				return "RAK Rotary Encoder Module"
			case .cardKB:
				return "M5 Stack Card KB / RAK Keypad"
			}
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
		get {
			switch self {
			
			case .none:
				return "None"
			case .up:
				return "Up"
			case .down:
				return "Down"
			case .left:
				return "Left"
			case .right:
				return "Right"
			case .select:
				return "Select"
			case .back:
				return "Back"
			case .cancel:
				return "Cancel"
			}
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
