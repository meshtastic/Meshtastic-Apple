import SwiftUI
import OSLog
struct TraceRouteButton: View {
	@EnvironmentObject var accessoryManager: AccessoryManager

	var node: NodeInfoEntity
	/// An icon over a short title, for a row of equal action tiles.
	var compact = false

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
			if compact {
				if let completion, completion.percentComplete > 0.0 {
					TraceRouteActionLabel(
						title: "\(completion.secondsRemaining.formatted(.number.precision(.fractionLength(0))))s",
						systemImage: "signpost.right.and.left"
					)
					.foregroundStyle(.secondary)
				} else {
					TraceRouteActionLabel(title: String(localized: "Trace Route"), systemImage: "signpost.right.and.left")
				}
			} else if let completion, completion.percentComplete > 0.0 {
				Label {
					Text("Trace Route (in \(completion.secondsRemaining.formatted(.number.precision(.fractionLength(0))))s)")
						.foregroundStyle(.secondary)
				} icon: {
					Image("progress.ring.dashed", variableValue: completion.percentComplete)
						.foregroundStyle(.secondary)
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

// TODO: Fix preview for SwiftData
/*
#Preview {
	let node = NodeInfoEntity()
	node.num = 123456789
	let user = UserEntity()
	user.longName = "Test Node"
	user.shortName = "TN"
	node.user = user
	TraceRouteButton(node: node)
		.environmentObject(AccessoryManager.shared)
}
*/
