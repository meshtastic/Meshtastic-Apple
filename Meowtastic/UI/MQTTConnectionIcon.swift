import Foundation
import SwiftUI

struct MQTTConnectionIcon: View {
	var connected: Bool = false

	private var icon: String {
		if connected {
			return "icloud"
		}
		else {
			return "icloud.slash"
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
