import SwiftUI

struct TraceRouteButton: View {
	var bleManager: BLEManager
	var node: NodeInfoEntity

	@State
	private var isPresentingTraceRouteSentAlert = false

    var body: some View {
		Button {
			isPresentingTraceRouteSentAlert = bleManager.sendTraceRouteRequest(
				destNum: node.user?.num ?? 0,
				wantResponse: true
			)
		} label: {
			Label {
				Text("Request Trace Route")
			} icon: {
				Image(systemName: "signpost.right.and.left")
					.symbolRenderingMode(.monochrome)
					.foregroundColor(.accentColor)
			}
		}.alert(
			"Trace Route Sent",
			isPresented: $isPresentingTraceRouteSentAlert
		) {
			Button("OK") {	}
				.keyboardShortcut(.defaultAction)
		} message: {
			Text("This could take a while. The response will appear in the trace route log for the node it was sent to.")
		}
    }
}
