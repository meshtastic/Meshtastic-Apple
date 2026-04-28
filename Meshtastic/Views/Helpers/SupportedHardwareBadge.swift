//
//  SwiftUIView.swift
//  Meshtastic
//
//  Created by Jake Bordens on 12/10/25.
//

import SwiftUI
import SwiftData

struct SupportedHardwareBadge: View {
	
	@Query var hardware: [DeviceHardwareEntity]
	@EnvironmentObject var meshtasticAPI: MeshtasticAPI
	
	init<T>(hwModelId: T) where T: BinaryInteger {
		let hwModel = Int64(hwModelId)
		_hardware = Query(filter: #Predicate<DeviceHardwareEntity> { hw in
			hw.hwModel == hwModel
		}, sort: [SortDescriptor(\.hwModelSlug)])
	}
	
	init(platformioTarget: String) {
		_hardware = Query(filter: #Predicate<DeviceHardwareEntity> { hw in
			hw.platformioTarget == platformioTarget
		}, sort: [SortDescriptor(\.hwModelSlug)])
	}
	
	var body: some View {
		if let device = hardware.first {
			VStack {
				Image(systemName: device.activelySupported ? "checkmark.seal.fill" : "x.circle")
					.font(.largeTitle)
					.foregroundStyle(device.activelySupported ? .green : .red)
				Text( device.activelySupported ? "Supported" : "Unsupported")
					.foregroundStyle(.gray)
					.font(.caption2)
					.fixedSize()
			}
		} else if meshtasticAPI.isLoadingDeviceList {
			// Still loading the database from the API
			VStack {
				ProgressView()
				Text("Loading")
					.foregroundStyle(.gray)
					.font(.caption2)
					.fixedSize()
			}
		} else {
			// Can't find this hardware in the database
			VStack {
				Image(systemName: "questionmark.circle.fill")
					.font(.largeTitle)
					.foregroundStyle(.gray)
				Text("Unknown")
					.foregroundStyle(.gray)
					.font(.caption2)
					.fixedSize()
			}
		}
	}
}
