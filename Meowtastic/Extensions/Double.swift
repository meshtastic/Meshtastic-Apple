//
//  Double.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen on 4/25/23.
//
import Foundation

extension Double {
	var toBytes: String {
	  let formatter = MeasurementFormatter()
	  let measurement = Measurement(value: self, unit: UnitInformationStorage.bytes)
	  formatter.unitStyle = .short
	  formatter.unitOptions = .naturalScale
	  formatter.numberFormatter.maximumFractionDigits = 0
	  return formatter.string(from: measurement.converted(to: .megabytes))
	}
}
