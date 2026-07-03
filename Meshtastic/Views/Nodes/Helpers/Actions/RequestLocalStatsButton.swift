import SwiftUI
import OSLog

struct RequestLocalStatsButton: View {
	@EnvironmentObject var accessoryManager: AccessoryManager

	var node: NodeInfoEntity
	var title = "Request Local Stats"
	var cooldownTitle = "Local Stats"
	var systemImage = "chart.bar"

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
					Task { @MainActor in
						isPresentingLocalStatsSentAlert = true
					}
				} catch {
					Logger.mesh.warning("Failed to send local stats request: \(error)")
				}
			}
		} label: { completion in
			if let completion, completion.percentComplete > 0.0 {
				Label {
					Text("\(cooldownTitle) \(Int(completion.secondsRemaining))s")
						.foregroundStyle(.secondary)
						.lineLimit(1)
				} icon: {
					Image("progress.ring.dashed", variableValue: completion.percentComplete)
						.foregroundStyle(.secondary)
				}.disabled(true)
			} else {
				Label {
					Text(title)
						.lineLimit(1)
				} icon: {
					Image(systemName: systemImage)
						.symbolRenderingMode(.hierarchical)
				}
			}
		}
		.alert("Local Stats Requested", isPresented: $isPresentingLocalStatsSentAlert) {
			Button("OK", role: .cancel) { }
		} message: {
			Text("A local stats request has been sent to \(node.user?.longName ?? "this node"). Responses can take some time.")
		}
	}
}
