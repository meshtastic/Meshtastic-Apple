import SwiftUI

/// Opens the direct message thread with a node in the Messages tab.
struct MessageNodeButton: View {

	let nodeNum: Int64

	var body: some View {
		Button {
			if let url = URL(string: "meshtastic:///messages?userNum=\(nodeNum)") {
				UIApplication.shared.open(url)
			}
		} label: {
			Label("Message", systemImage: "message")
		}
	}
}
