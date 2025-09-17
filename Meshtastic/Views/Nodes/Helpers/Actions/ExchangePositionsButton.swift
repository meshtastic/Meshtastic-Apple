import CoreData
import SwiftUI

struct ExchangePositionsButton: View {
	var node: NodeInfoEntity

	@EnvironmentObject var accessoryManager: AccessoryManager

	@State private var isPresentingPositionSentAlert: Bool = false
	@State private var isPresentingPositionFailedAlert: Bool = false

    var body: some View {
		let hopsAway = Int32(truncatingIfNeeded: node.hopsAway > node.loRaConfig?.hopLimit ?? 0 ? node.hopsAway : node.loRaConfig?.hopLimit ?? 0)
		Button {
			Task {
				do {
					try await accessoryManager.sendPosition(
						channel: node.channel,
						destNum: node.num,
						hopsAway: hopsAway,
						wantResponse: true
					)
					Task { @MainActor in
						isPresentingPositionSentAlert = true
						DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
							isPresentingPositionSentAlert = false
						}
					}
				} catch {
					Task { @MainActor in
						isPresentingPositionFailedAlert = true
						DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
							isPresentingPositionFailedAlert = false
						}
					}
				}
			}

		} label: {
			Label {
				Text("Exchange Positions")
			} icon: {
				Image(systemName: "arrow.triangle.2.circlepath")
					.symbolRenderingMode(.hierarchical)
			}
		}.alert(
			"Position Sent",
			isPresented: $isPresentingPositionSentAlert
		) {
			Button("OK") {	}.keyboardShortcut(.defaultAction)
		} message: {
			Text("Your position has been sent with a request for a response with their position. You will receive a notification when a position is returned.")
		}.alert(
			"Position Exchange Failed",
			isPresented: $isPresentingPositionFailedAlert
		) {
			Button("OK") {	}.keyboardShortcut(.defaultAction)
		} message: {
			Text("Failed to get a valid position to exchange.")
		}
    }
}
