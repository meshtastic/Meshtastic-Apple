import Foundation
import SwiftUI

struct MQTTChannelIcon: View {
	var connected: Bool = false
	var uplink: Bool = false
	var downlink: Bool = false

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
		Image(systemName: icon)
			.resizable()
			.scaledToFit()
			.frame(width: 16, height: 16)
			.foregroundColor(color)
			.padding(8)
			.background(color.opacity(0.3))
			.clipShape(Circle())
	}
}
