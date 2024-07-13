import Foundation
import SwiftUI

struct MQTTIcon: View {
	var connected: Bool = false
	var uplink: Bool = false
	var downlink: Bool = false
	var topic: String = ""

	@State
	var isPopoverOpen = false

	private var icon: String {
		if uplink && downlink {
			return "arrow.up.arrow.down.circle.fill"
		}
		else if uplink {
			return "arrow.up.circle.fill"
		}
		else if downlink {
			return "arrow.down.circle.fill"
		}
		else {
			return "slash.circle"
		}
	}

	private var color: Color {
		connected ? .green : .gray
	}

	var body: some View {
		Button(action: {
			if topic.length > 0 {
				self.isPopoverOpen.toggle()
			}
		}) {
			Image(systemName: icon)
				.foregroundColor(color)
				.padding(6)
				.background(color.opacity(0.3))
				.clipShape(Circle())
		}
		.popover(
			isPresented: self.$isPopoverOpen,
			arrowEdge: .bottom,
			content: {
				VStack(spacing: 0.5) {
					Text("Topic: " + topic)
						.padding(20)
					Button(
						"close",
						action: {
							self.isPopoverOpen = false
						}
					)
					.padding([.bottom], 20)
				}
				.presentationCompactAdaptation(.popover)
			}
		)
	}
}
