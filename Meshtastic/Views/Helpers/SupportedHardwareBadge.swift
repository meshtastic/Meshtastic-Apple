//
//  SwiftUIView.swift
//  Meshtastic
//
//  Created by Jake Bordens on 12/10/25.
//

import SwiftUI
@preconcurrency import SwiftData

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

	private var presentation: HardwareCatalogPresentation? {
		guard let hwModel = hardware.first?.hwModel else { return nil }
		return HardwareCatalogResolver.presentation(for: hwModel, in: hardware)
	}
	
	var body: some View {
		if let activelySupported = presentation?.activelySupported {
			VStack {
				Image(systemName: activelySupported ? "checkmark.seal.fill" : "x.circle")
					.font(.largeTitle)
					.foregroundStyle(activelySupported ? .green : .red)
				Text( activelySupported ? "Supported" : "Unsupported")
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
