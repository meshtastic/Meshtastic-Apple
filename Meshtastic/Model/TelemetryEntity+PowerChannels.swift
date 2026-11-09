//
//  TelemetryEntity+PowerChannels.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/9/26.
//

import Foundation

extension TelemetryEntity {

	/// PowerMetrics carries up to eight voltage and current channels.
	static let powerChannelCount = 8

	/// The voltage on a power channel, counting from zero.
	func powerVoltage(channel index: Int) -> Float? {
		switch index {
		case 0: powerCh1Voltage
		case 1: powerCh2Voltage
		case 2: powerCh3Voltage
		case 3: powerCh4Voltage
		case 4: powerCh5Voltage
		case 5: powerCh6Voltage
		case 6: powerCh7Voltage
		case 7: powerCh8Voltage
		default: nil
		}
	}

	/// The current on a power channel, counting from zero.
	func powerCurrent(channel index: Int) -> Float? {
		switch index {
		case 0: powerCh1Current
		case 1: powerCh2Current
		case 2: powerCh3Current
		case 3: powerCh4Current
		case 4: powerCh5Current
		case 5: powerCh6Current
		case 6: powerCh7Current
		case 7: powerCh8Current
		default: nil
		}
	}

	func hasPowerReading(channel index: Int) -> Bool {
		powerVoltage(channel: index) != nil || powerCurrent(channel: index) != nil
	}
}

extension Sequence where Element == TelemetryEntity {
	/// The power channels, counting from zero, that report anything in these readings.
	var reportedPowerChannels: [Int] {
		(0..<TelemetryEntity.powerChannelCount).filter { index in
			contains { $0.hasPowerReading(channel: index) }
		}
	}
}

enum PowerChannelLabel {
	/// The name shown for a power channel, counting from zero: the user's label from `labels`, or
	/// "Channel N" when it's blank (design#53 requirement 10).
	static func name(_ index: Int, in labels: [String]) -> String {
		let custom = index < labels.count ? labels[index].trimmingCharacters(in: .whitespaces) : ""
		return custom.isEmpty ? String(format: "Channel %d".localized, index + 1) : custom
	}
}
