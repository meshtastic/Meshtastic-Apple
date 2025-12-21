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
	@EnvironmentObject var meshtasticAPI: MeshtasticAPI
	
	var body: some View {
		if let user = node.user {
		ViewThatFits(in: .horizontal) {
			HStack {
				Spacer()
						if let hwModelId = node.user?.hwModelId {
						VStack(alignment: .center) {
							Spacer()
							SupportedHardwareBadge(hwModelId: hwModelId)
						}
						.accessibilityElement(children: .combine)
						Spacer()
					}
					VStack(alignment: .center) {
//						HStack {
							DeviceHardwareImage(hwId: user.hwModelId)
								.frame(width: 100, height: 100)
								.cornerRadius(5)
//							if let image = try? meshtasticAPI.imageForNode(hwModelId: user.hwModelId) {
//								image
//									.resizable()
//									.aspectRatio(contentMode: .fit)
//									.frame(maxHeight: 150)
//									.cornerRadius(5)
//							} else {
//								Image(systemName: "person.crop.circle.badge.questionmark")
//									.resizable()
//									.aspectRatio(contentMode: .fit)
//									.frame(width: 75, height: 75)
//									.cornerRadius(5)
//							}
//						}
						.accessibilityElement(children: .combine)
					}
					Spacer()
				}
				.accessibilityElement(children: .combine)
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
					Text(String(node.user?.hwDisplayName ?? (node.user?.hwModel ?? "Unset".localized)))
				} else {
					Text(String("Incomplete".localized))
				}
			}
			.accessibilityElement(children: .combine)
		}
	}
}
