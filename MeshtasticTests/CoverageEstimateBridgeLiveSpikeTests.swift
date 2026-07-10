// MARK: CoverageEstimateBridgeLiveSpikeTests
//
//  SPIKE (tasks.md T012): a genuine integration test against the live
//  site.meshtastic.org — not a mock. This is the empirical go/no-go check for
//  whether a WKWebView attached-but-invisible to the key window reliably executes
//  JS and delivers WKScriptMessageHandler callbacks, specifically under Mac
//  Catalyst (research.md §5's open risk). Run explicitly on both destinations:
//
//    xcodebuild ... -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test \
//      -only-testing:MeshtasticTests/CoverageEstimateBridgeLiveSpikeTests
//    xcodebuild ... -destination 'platform=macOS,variant=Mac Catalyst' test \
//      -only-testing:MeshtasticTests/CoverageEstimateBridgeLiveSpikeTests
//
//  Deliberately small parameters (max_range=5km, no high_res) so the live
//  simulation itself is fast — this is testing the bridge mechanism, not the
//  RF engine. Requires real network access to site.meshtastic.org.
//

import Testing
import Foundation
@testable import Meshtastic

@Suite("CoverageEstimateBridge live spike (T012)")
@MainActor
struct CoverageEstimateBridgeLiveSpikeTests {

	@Test func bridgeReceivesRealCoverageResult() async throws {
		let params = CoverageEstimateParameters(
			name: "Bridge Spike Test",
			latitude: 47.6062,
			longitude: -122.3321,
			transmitPowerWatts: 0.1,
			transmitFrequencyMHz: 915
		)
		var fastParams = params
		fastParams.maxRangeKm = 5

		let bridge = CoverageEstimateBridge()
		let data = try await bridge.run(fastParams, timeout: .seconds(60))

		let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
		#expect(json?["type"] as? String == "FeatureCollection")
		let features = json?["features"] as? [[String: Any]]
		#expect((features?.count ?? 0) > 0)
	}
}
