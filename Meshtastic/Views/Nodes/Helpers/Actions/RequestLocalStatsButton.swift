import SwiftUI
import OSLog

struct RequestLocalStatsButton: View {
	@EnvironmentObject var accessoryManager: AccessoryManager

	var node: NodeInfoEntity

	@State
	private var isPresentingLocalStatsSentAlert: Bool = false

    var body: some View {
		RateLimitedButton(key: "localstats", rateLimit: 30.0) {
			Task {
				do {
					try await accessoryManager.sendLocalStatsRequest(
						destNum: node.user?.num ?? 0,
						wantResponse: true
					)
					Task {
						isPresentingLocalStatsSentAlert = true
					}
				} catch {
					Logger.mesh.warning("Failed to send local stats request: \(error)")
				}
			}
		} label: { completion in
			if let completion, completion.percentComplete > 0.0 {
				Label {
					Text("Local Stats (in \(Int(completion.secondsRemaining))s)")
						.foregroundStyle(.secondary)
				} icon: {
					Image("progress.ring.dashed", variableValue: completion.percentComplete)
						.foregroundStyle(.secondary)
				}.disabled(true)
			} else {
				Label {
					Text("Request Local Stats")
				} icon: {
				    Image(systemName: "chart.bar")
					   .symbolRenderingMode(.hierarchical)
			    }
		   }
		}
		.alert("Local Stats Requested", isPresented: $isPresentingLocalStatsSentAlert) {
			Button("OK", role: .cancel) { }
		} message: {
			Text("A local stats request has been sent to \(node.user?.longName ?? "this node"). Responses can some time.")
		}
    }
}
