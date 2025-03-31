//
//  NodeInfoItem.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/9/23.
//

import SwiftUI
import CoreLocation
import MapKit

struct NodeInfoItem: View {

	@ObservedObject var node: NodeInfoEntity
	@State private var currentDevice: DeviceHardware?

	var body: some View {
		if let user = node.user {
		ViewThatFits(in: .horizontal) {
			HStack {
				Spacer()
					if user.hwModel != "UNSET" {
						VStack(alignment: .center) {
							Spacer()
							Image(systemName: currentDevice?.activelySupported ?? false ? "checkmark.seal.fill" : "seal.fill")
								.resizable()
								.aspectRatio(contentMode: .fill)
								.frame(width: 75, height: 75)
								.foregroundStyle(currentDevice?.activelySupported ?? false ? .green : .red)
							Text( currentDevice?.activelySupported ?? false ? "Full Support" : "Community Support")
								.foregroundStyle(.gray)
								.font(.callout)
						}
						Spacer()
					}
					VStack(alignment: .center) {
						HStack {
							if user.hardwareImage != "UNSET" {
								Image(user.hardwareImage ?? "UNSET")
									.resizable()
									.aspectRatio(contentMode: .fit)
									.frame(maxHeight: 150)
									.cornerRadius(5)
							} else {
								Image(systemName: "person.crop.circle.badge.questionmark")
									.resizable()
									.aspectRatio(contentMode: .fit)
									.frame(width: 75, height: 75)
									.cornerRadius(5)
							}
						}
					}
					Spacer()
				}
				.onAppear {
					Api().loadDeviceHardwareData { (hw) in
						for device in hw {
							let currentHardware = node.user?.hwModel ?? "UNSET"
							let deviceString = device.hwModelSlug.replacingOccurrences(of: "_", with: "").uppercased()
							if deviceString == currentHardware {
								currentDevice = device
							}
						}
					}
				}
			}
			.listRowSeparator(.hidden)
			HStack {
				Label {
					Text("Model")
				} icon: {
					Image(systemName: "flipphone")
						.symbolRenderingMode(.hierarchical)
				}
				Spacer()
				if user.hwModel != "UNSET" {
					Text(String(node.user?.hwDisplayName ?? (node.user?.hwModel ?? "unset".localized)))
				} else {
					Text(String("incomplete".localized))
				}
			}
		}
	}
}
