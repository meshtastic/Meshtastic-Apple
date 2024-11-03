//
//  DetectionSensorEnums.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/11/24.
//
import MeshtasticProtobufs

enum TriggerTypes: Int, CaseIterable, Identifiable {

	case logicLow = 0
	case logicHigh = 1
	case fallingEdge = 2
	case risingEdge = 3
	case eitherEdgeActiveLow = 4
	case eitherEdgeActiveHigh = 5

	var id: Int { self.rawValue }

	var name: String {
		switch self {
		case .logicLow:
			return "Low"
		case .logicHigh:
			return "High"
		case .fallingEdge:
			return "Falling Edge"
		case .risingEdge:
			return "Rising Edge"
		case .eitherEdgeActiveLow:
			return "Either Edge Low"
		case .eitherEdgeActiveHigh:
			return "Either Edge Hight"
		}
	}
	func protoEnumValue() -> ModuleConfig.DetectionSensorConfig.TriggerType {

		switch self {
		case .logicLow:
			return  ModuleConfig.DetectionSensorConfig.TriggerType.logicLow
		case .logicHigh:
			return  ModuleConfig.DetectionSensorConfig.TriggerType.logicHigh
		case .fallingEdge:
			return ModuleConfig.DetectionSensorConfig.TriggerType.fallingEdge
		case .risingEdge:
			return ModuleConfig.DetectionSensorConfig.TriggerType.risingEdge
		case .eitherEdgeActiveLow:
			return ModuleConfig.DetectionSensorConfig.TriggerType.eitherEdgeActiveLow
		case .eitherEdgeActiveHigh:
			return ModuleConfig.DetectionSensorConfig.TriggerType.eitherEdgeActiveHigh
		}
	}
}
