//
//  CardinalDirection.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/11/26.
//

import Foundation

func cardinalValue(from heading: Double) -> String {
	switch heading {
	case 0 ..< 22.5:
		return "North"
	case 22.5 ..< 67.5:
		return "North East"
	case 67.5 ..< 112.5:
		return "East"
	case 112.5 ..< 157.5:
		return "South East"
	case 157.5 ..< 202.5:
		return "South"
	case 202.5 ..< 247.5:
		return "South West"
	case 247.5 ..< 292.5:
		return "West"
	case 292.5 ..< 337.5:
		return "North West"
	case 337.5 ... 360.0:
		return "North"
	default:
		return ""
	}
}
