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
	case tbeamThreeButtonScreen = 2
	case cardKB = 3
	case facesKB = 4
	
	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
			
			case .unset:
				return "Manual Configuration"
			case .rakRotaryEncoder:
				return "RAK Rotary Encoder Module"
			case .tbeamThreeButtonScreen:
				return "TBEAM 3 Button OLED Screen"
			case .cardKB:
				return "M5 Stack Card KeyBoard"
			case .facesKB:
				return "M5 Stack Faces KeyBoard"
			}
		}
	}
}

// Default of 0 is off
enum InputEventChars: Int, CaseIterable, Identifiable {

	case keyNone = 0
	case keyUp = 17
	case keyDown = 18
	case keyLeft = 19
	case keyRight = 20
	case keySelect = 10
	case keyBack = 27
	case keyCancel = 24

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
			
			case .keyNone:
				return "None"
			case .keyUp:
				return "Up"
			case .keyDown:
				return "Down"
			case .keyLeft:
				return "Left"
			case .keyRight:
				return "Right"
			case .keySelect:
				return "Select"
			case .keyBack:
				return "Back"
			case .keyCancel:
				return "Cancel"
			}
		}
	}
	func protoEnumValue() -> ModuleConfig.CannedMessageConfig.InputEventChar {
		
		switch self {

		case .keyNone:
			return ModuleConfig.CannedMessageConfig.InputEventChar.none
		case .keyUp:
			return ModuleConfig.CannedMessageConfig.InputEventChar.up
		case .keyDown:
			return ModuleConfig.CannedMessageConfig.InputEventChar.down
		case .keyLeft:
			return ModuleConfig.CannedMessageConfig.InputEventChar.left
		case .keyRight:
			return ModuleConfig.CannedMessageConfig.InputEventChar.right
		case .keySelect:
			return ModuleConfig.CannedMessageConfig.InputEventChar.select
		case .keyBack:
			return ModuleConfig.CannedMessageConfig.InputEventChar.back
		case .keyCancel:
			return ModuleConfig.CannedMessageConfig.InputEventChar.cancel
		}
	}
}
