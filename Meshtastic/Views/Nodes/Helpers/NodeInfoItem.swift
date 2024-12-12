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
	var supported: Bool

	var body: some View {
		if let user = node.user {
		ViewThatFits(in: .horizontal) {
			HStack {
				Spacer()
					VStack(alignment: .center) {
						Spacer()
						Image(systemName: supported ? "checkmark.seal.fill" : "x.circle")
							.resizable()
							.aspectRatio(contentMode: .fill)      // << here !!
							.frame(width: 75, height: 75)
								.foregroundStyle(supported ? .green : .red)
						Text( supported ? "Supported" : "Unsupported")
								.foregroundStyle(.gray)
								.font(.callout)
					}
					Spacer()
					VStack(alignment: .center) {
						HStack {
							if user.hwModel != "UNSET" {
								Image(user.hardwareImage ?? "UNSET")
									.resizable()
									.aspectRatio(contentMode: .fit)
									.frame(maxHeight: 150)
									.cornerRadius(5)
							} else {
								Image(systemName: "person.crop.circle.badge.questionmark")
									.resizable()
									.aspectRatio(contentMode: .fit)
									.frame(width: 65, height: 65)
									.cornerRadius(5)
							}
						}
					}
					Spacer()
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
