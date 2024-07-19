//
//  MQTTIcon.swift
//  Meshtastic
//
//  Created by Matthew Davies on 4/1/24.
//

import Foundation
import SwiftUI

struct MQTTIcon: View {
	var connected: Bool = false
	var uplink: Bool = false
	var downlink: Bool = false
	var topic: String = ""

	@State var isPopoverOpen = false

	var body: some View {
		Button( action: {
			if topic.length > 0 {self.isPopoverOpen.toggle()}
		}) {
			// the last one defaults to just showing up/down if it isn't specified b/c on the mqtt config screen, there's no information about uplink/downlink and no good alternative icon
			Image(systemName: uplink && downlink ? "arrow.up.arrow.down.circle.fill" : uplink ? "arrow.up.circle.fill" : downlink ? "arrow.down.circle.fill" : "arrow.up.arrow.down.circle.fill")
				.imageScale(.large)
				.foregroundColor(connected ? .green : .secondary)
				.symbolRenderingMode(.hierarchical)
		}.popover(isPresented: self.$isPopoverOpen, arrowEdge: .bottom, content: {
			VStack(spacing: 0.5) {
				Text("Topic: " + topic)
					.padding(20)
				Button("close", action: { self.isPopoverOpen = false }).padding([.bottom], 20)
			}
			.presentationCompactAdaptation(.popover)
		})
	}
}

struct MQTTIcon_Previews: PreviewProvider {
	static var previews: some View {
		VStack {
			MQTTIcon(connected: true)
			MQTTIcon(connected: false)

			MQTTIcon(connected: true, uplink: true, downlink: true)
			MQTTIcon(connected: false, uplink: true, downlink: true)

			MQTTIcon(connected: true, uplink: true)
			MQTTIcon(connected: false, uplink: true)

			MQTTIcon(connected: true, downlink: true)
			MQTTIcon(connected: false, downlink: true)
		}.previewLayout(.fixed(width: 25, height: 220))
	}
}
