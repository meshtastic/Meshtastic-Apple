//
//  UpdateIntervalPicker.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/4/25.
//
import SwiftUI

struct UpdateIntervalPicker: View {
	let config: IntervalConfiguration
	let pickerLabel: String
	
	@Binding var selectedInterval: UpdateInterval
	
	private var fixedOptions: [UpdateInterval] {
		config.allowedCases
			.map { UpdateInterval(from: $0.rawValue) }
	}

	init(config: IntervalConfiguration, pickerLabel: String, selectedInterval: Binding<UpdateInterval>) {
		self.config = config
		self.pickerLabel = pickerLabel
		self._selectedInterval = selectedInterval
	}
	
	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			Picker(pickerLabel, selection: $selectedInterval) {
				ForEach(fixedOptions, id: \.self) { interval in
					Text(interval.description)
						.tag(interval)
				}
			}
			
			if isOutOfRange {
				let interval: TimeInterval = Double(selectedInterval.intValue)
				let formatter = DateComponentsFormatter()
				if let formattedString = formatter.string(from: interval) {
					Text("⚠️ The configured value: (\(formattedString) seconds) is not one of the optimized options.")
						.font(.caption)
						.foregroundColor(.orange)
				}
			}
		}
	}
	private var isOutOfRange: Bool {
	   switch selectedInterval.type {
	   case .manual:
		   return true
	   case .fixed(let fixedCase):
		   return !config.allowedCases.contains(fixedCase)
	   }
   }
}
