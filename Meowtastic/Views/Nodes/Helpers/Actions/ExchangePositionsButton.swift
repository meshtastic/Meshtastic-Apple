import CoreData
import SwiftUI

struct ExchangePositionsButton: View {
	var bleManager: BLEManager
	var node: NodeInfoEntity

	@State
	private var isPresentingPositionSentAlert = false

	var body: some View {
		Button {
			isPresentingPositionSentAlert = bleManager.sendPosition(
				channel: node.channel,
				destNum: node.num,
				wantResponse: true
			)
		} label: {
			Label {
				Text("Exchange Positions")
			} icon: {
				Image(systemName: "arrow.triangle.2.circlepath")
					.symbolRenderingMode(.monochrome)
					.foregroundColor(.accentColor)
			}
		}.alert(
			"Position Sent",
			isPresented: $isPresentingPositionSentAlert
		) {
			Button("OK") { }
				.keyboardShortcut(.defaultAction)
		} message: {
			Text("Your position has been sent with a request for a response with their position.")
		}
	}
}
