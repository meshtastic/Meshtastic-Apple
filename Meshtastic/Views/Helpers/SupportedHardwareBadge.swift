//
//  SwiftUIView.swift
//  Meshtastic
//
//  Created by Jake Bordens on 12/10/25.
//

import SwiftUI

struct SupportedHardwareBadge: View {
	
	@Environment(\.managedObjectContext) var context
	@FetchRequest var hardware: FetchedResults<DeviceHardwareEntity>
	@EnvironmentObject var meshtasticAPI: MeshtasticAPI
	
	init<T>(hwModelId: T) where T: BinaryInteger, T: CVarArg {
		let predicate = NSPredicate(format: "hwModel == %d", hwModelId)
		_hardware = FetchRequest(
			entity: DeviceHardwareEntity.entity(),
			sortDescriptors: [NSSortDescriptor(key: "hwModelSlug", ascending: true)],
			predicate: predicate,
			animation: .default
		)
	}
	
	init(platformioTarget: String) {
		let predicate = NSPredicate(format: "platformioTarget == %@", platformioTarget)
		_hardware = FetchRequest(
			entity: DeviceHardwareEntity.entity(),
			sortDescriptors: [NSSortDescriptor(key: "hwModelSlug", ascending: true)],
			predicate: predicate,
			animation: .default
		)
	}
	
	var body: some View {
		switch hardware.count {
		case 1:
			let device = hardware[0]
			VStack {
				Image(systemName: device.activelySupported ? "checkmark.seal.fill" : "x.circle")
					.font(.largeTitle)
					.foregroundStyle(device.activelySupported ? .green : .red)
				Text( device.activelySupported ? "Supported" : "Unsupported")
					.foregroundStyle(.gray)
					.font(.caption2)
			}
			
		default:
			if meshtasticAPI.isLoadingDeviceList {
				// Still loading the database from the API
				VStack {
					ProgressView()
					Text("Loading")
						.foregroundStyle(.gray)
						.font(.caption2)
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
				}
			}
		}
	}
}
