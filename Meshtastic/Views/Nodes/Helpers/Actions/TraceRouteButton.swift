import SwiftUI
import OSLog
struct TraceRouteButton: View {
	@EnvironmentObject var accessoryManager: AccessoryManager

	var node: NodeInfoEntity

	@State
	private var isPresentingTraceRouteSentAlert: Bool = false

    var body: some View {
		RateLimitedButton(key: "traceroute", rateLimit: 30.0) {
			Task {
				do {
					try await accessoryManager.sendTraceRouteRequest(
						destNum: node.user?.num ?? 0,
						wantResponse: true
					)
					Task {
						isPresentingTraceRouteSentAlert = true
					}
				} catch {
					Logger.mesh.warning("Failed to send traceroute request: \(error)")
				}
			}
		} label: { completion in
			if let completion, completion.percentComplete > 0.0 {
				Label {
					Text("Trace Route (in \(completion.secondsRemaining.formatted(.number.precision(.fractionLength(0))))s)")
						.foregroundStyle(.secondary)
				} icon: {
					if #available(iOS 16.0, *) {
					    Image("progress.ring.dashed", variableValue: completion.percentComplete)
    						.foregroundStyle(.secondary)
					} else {
					   	Image("progress.ring.dashed")
    						.foregroundStyle(.secondary)
					}
				}.disabled(true)
			} else {
				Label {
					Text("Trace Route")
				} icon: {
				   Image(systemName: "signpost.right.and.left")
					   .symbolRenderingMode(.hierarchical)
				}
		   }
		}
    }
}
