import Foundation
import SwiftData
import Testing

@testable import Meshtastic

// Not `final`: the URLProtocol hooks below are class-method overrides, which SwiftLint's
// static_over_final_class rule would otherwise flag.

/// Records every request the URL loading system is asked to perform, and fails them
/// immediately so a test can never depend on real network reachability.
///
/// Scope caveat: `URLProtocol.registerClass` only intercepts `URLSession.shared` and sessions
/// built from a default configuration. That covers the code under test — `URL.eTag()` and
/// `URL.data(timeout:)` both use `URLSession.shared` — but a future regression that reaches the
/// network through a custom-configured session would slip past this recorder.
class RequestRecordingURLProtocol: URLProtocol {
	private static let lock = NSLock()
	nonisolated(unsafe) private static var recorded: [URL] = []

	static func reset() {
		lock.lock()
		recorded = []
		lock.unlock()
	}

	static var recordedURLs: [URL] {
		lock.lock()
		defer { lock.unlock() }
		return recorded
	}

	override class func canInit(with request: URLRequest) -> Bool {
		if let url = request.url {
			lock.lock()
			recorded.append(url)
			lock.unlock()
		}
		return true
	}

	override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

	override func startLoading() {
		client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
	}

	override func stopLoading() {}
}

@Suite("MeshtasticAPI bundled device seed", .serialized)
struct MeshtasticAPIBundledSeedTests {

	private func makeContainer() throws -> ModelContainer {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let config = ModelConfiguration(
			"BundledSeedTest",
			schema: schema,
			isStoredInMemoryOnly: true,
			allowsSave: true
		)
		return try ModelContainer(for: schema, configurations: config)
	}

	/// Regression test for #2196.
	///
	/// `refreshBundledDevicesData()` is awaited inline by BLE connect Step 3, which has a 30s
	/// budget and restarts the entire connect when it is exceeded. It previously fanned out one
	/// `URL.eTag()` HEAD per device image — 82 requests with no timeout — so a captive portal or
	/// zero-rated cellular link stalled the seed well past that budget and blocked BLE sync.
	/// The seed must therefore stay entirely local.
	@Test @MainActor func bundledSeedIssuesNoNetworkRequests() async throws {
		URLProtocol.registerClass(RequestRecordingURLProtocol.self)
		RequestRecordingURLProtocol.reset()
		defer { URLProtocol.unregisterClass(RequestRecordingURLProtocol.self) }

		// startupRefresh: false — the init cascade would otherwise fire detached firmware,
		// image, and device requests that race the recorder and make this assertion flaky.
		let api = MeshtasticAPI(container: try makeContainer(), startupRefresh: false)
		try await api.refreshBundledDevicesData()

		#expect(
			RequestRecordingURLProtocol.recordedURLs.isEmpty,
			"""
			refreshBundledDevicesData() must not touch the network — it runs inside BLE connect \
			Step 3. Requested: \(RequestRecordingURLProtocol.recordedURLs.map(\.absoluteString))
			"""
		)
	}

	/// The seed still has to populate the catalog, otherwise moving the network work out would
	/// regress the "hardware info present after a database clear" behaviour connect Step 3 and
	/// the Reset Database action both rely on.
	@Test @MainActor func bundledSeedPopulatesDeviceCatalog() async throws {
		let container = try makeContainer()
		let api = MeshtasticAPI(container: container, startupRefresh: false)

		try await api.refreshBundledDevicesData()

		let devices = try container.mainContext.fetch(FetchDescriptor<DeviceHardwareEntity>())
		#expect(!devices.isEmpty, "Bundled seed should populate DeviceHardwareEntity rows")
	}
}
