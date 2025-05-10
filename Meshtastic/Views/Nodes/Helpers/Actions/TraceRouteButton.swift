import SwiftUI

struct TraceRouteButton: View {
	var bleManager: BLEManager

	var node: NodeInfoEntity

	@State
	private var isPresentingTraceRouteSentAlert: Bool = false

    var body: some View {
		RateLimitedButton(key: "traceroute", rateLimit: 30.0) {
			isPresentingTraceRouteSentAlert = bleManager.sendTraceRouteRequest(
				destNum: node.user?.num ?? 0,
				wantResponse: true
			)
		} label: { completion in
			if let completion, completion.percentComplete > 0.0 {
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
		}.alert(
			"Trace Route Sent",
			isPresented: $isPresentingTraceRouteSentAlert
		) {
			Button("OK") {	}.keyboardShortcut(.defaultAction)
		} message: {
			Text("This could take a while. The response will appear in the trace route log for the node it was sent to.")
		}
    }
}
