#if canImport(AppIntents)
import Foundation
import AppIntents

@available(iOS 16.0, *)
struct TracerouteIntent: AppIntent {
	static var title: LocalizedStringResource = "Send a Traceroute"

	static var description: IntentDescription = "Send a traceroute request to a certain Meshtastic node"

	@Parameter(title: "Node Number")
	var nodeNumber: Int

	static var parameterSummary: some ParameterSummary {
		Summary("Send traceroute to \(\.$nodeNumber)")
	}

	func perform() async throws -> some IntentResult {
		if !BLEManager.shared.isConnected {
			throw AppIntentErrors.AppIntentError.notConnected
		}

		if !BLEManager.shared.sendTraceRouteRequest(destNum: Int64(nodeNumber), wantResponse: true) {
			throw AppIntentErrors.AppIntentError.message("Failed to send traceroute request")
		}

		return .result()
	}
}

#endif