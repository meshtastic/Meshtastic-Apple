import Foundation
import SwiftData
import Testing

@testable import Meshtastic

/// Records every request the URL loading system is asked to perform, and fails them
/// immediately so a test can never depend on real network reachability.
///
/// Scope caveat: `URLProtocol.registerClass` only intercepts `URLSession.shared` and sessions
/// built from a default configuration. That covers the code under test — `URL.eTag()` and
/// `URL.data(timeout:)` both use `URLSession.shared` — but a future regression that reaches the
/// network through a custom-configured session would slip past this recorder.
///
/// Registration is process-global, so a suite using this must not run alongside another suite
/// that does its own networking. No other suite in this target does today; `.serialized` on the
/// suite below covers ordering within it.
///
/// Not `final`: the URLProtocol hooks below are class-method overrides, which SwiftLint's
/// `static_over_final_class` rule would otherwise flag.
class RequestRecordingURLProtocol: URLProtocol {
	private static let lock = NSLock()
	nonisolated(unsafe) private static var recorded: [URL] = []

	nonisolated(unsafe) private static var stubs: [String: Data] = [:]

	/// Resets the recorder. Any request whose URL contains one of the `stubs` keys is answered
	/// with a 200 and that body; everything else fails immediately.
	static func reset(stubs: [String: Data] = [:]) {
		lock.lock()
		recorded = []
		Self.stubs = stubs
		lock.unlock()
	}

	static var recordedURLs: [URL] {
		lock.lock()
		defer { lock.unlock() }
		return recorded
	}

	// Recording happens in startLoading(), not here: the URL loading system may call canInit
	// several times while deciding who handles a request, which would inflate the counts.
	override class func canInit(with request: URLRequest) -> Bool { true }

	override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

	override func startLoading() {
		let absolute = request.url?.absoluteString ?? ""
		if let url = request.url {
			Self.lock.lock()
			Self.recorded.append(url)
			Self.lock.unlock()
		}
		Self.lock.lock()
		let stubbed = Self.stubs.first { absolute.contains($0.key) }?.value
		Self.lock.unlock()

		guard let body = stubbed, let url = request.url, let response = HTTPURLResponse(
			url: url,
			statusCode: 200,
			httpVersion: "HTTP/1.1",
			headerFields: ["Content-Type": "application/json"]
		) else {
			client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
			return
		}
		client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
		client?.urlProtocol(self, didLoad: body)
		client?.urlProtocolDidFinishLoading(self)
	}

	override func stopLoading() {}
}

@Suite("MeshtasticAPI bundled device seed", .serialized)
final class MeshtasticAPIBundledSeedTests {

	/// The throttle timestamp as it was before this test ran, restored in `deinit`.
	private let priorImageAndLinkUpdate: Date

	/// Start every test from an un-throttled state. The device image/link pass is gated on
	/// `UserDefaults.lastDeviceImageAndLinkUpdate` (a 48h window), and that store is process-global,
	/// so without this a prior test that ran the pass would make the next one skip and record zero
	/// requests. Tests that specifically exercise the throttle set the timestamp themselves.
	init() {
		priorImageAndLinkUpdate = UserDefaults.lastDeviceImageAndLinkUpdate
		UserDefaults.lastDeviceImageAndLinkUpdate = .distantPast
	}

	/// Hand the process-global throttle back exactly as we found it.
	///
	/// The tests below deliberately leave a recent `Date` in `lastDeviceImageAndLinkUpdate` — that
	/// is what a completed pass writes. Without this restore, any suite that runs after this one
	/// inherits an armed throttle and its image/link passes silently skip until the 48h window
	/// expires, which reads as an unrelated test recording zero network requests. This is a `class`
	/// suite rather than a `struct` purely so there is a `deinit` to restore from.
	deinit {
		UserDefaults.lastDeviceImageAndLinkUpdate = priorImageAndLinkUpdate
	}

	/// A fresh, private in-memory container per test.
	///
	/// Deliberately not `SharedTestContainer.sharedModelContainer`: these tests need a virgin
	/// catalog and they write into it, so they must not see or disturb rows another suite seeded.
	/// The configuration name is unique per call because SwiftData treats two containers sharing a
	/// name and schema as the same store, which is the "multiple containers cause context resets"
	/// hazard `SharedTestContainer` warns about.
	private func makeContainer() throws -> ModelContainer {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let config = ModelConfiguration(
			"BundledSeedTest-\(UUID().uuidString)",
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

		// Snapshot once: `recordedURLs` takes the lock per read, so asserting on one read and
		// interpolating a second would let the failure message describe a different set than the
		// one that actually failed.
		let recorded = RequestRecordingURLProtocol.recordedURLs
		#expect(
			recorded.isEmpty,
			"""
			refreshBundledDevicesData() must not touch the network — it runs inside BLE connect \
			Step 3. Requested: \(recorded.map(\.absoluteString))
			"""
		)
	}

	/// The seed still has to populate the catalog, otherwise moving the network work out would
	/// regress the "hardware info present after a database clear" behaviour connect Step 3 and
	/// the Reset Database action both rely on.
	@Test @MainActor func bundledSeedPopulatesDeviceCatalog() async throws {
		// Register the recorder here too. The property under test is that this call is local, so if
		// the eTag fan-out is ever reintroduced this test must not start issuing real HEAD requests
		// from CI (or hang behind the very captive portal #2196 is about).
		URLProtocol.registerClass(RequestRecordingURLProtocol.self)
		RequestRecordingURLProtocol.reset()
		defer { URLProtocol.unregisterClass(RequestRecordingURLProtocol.self) }

		let container = try makeContainer()
		let api = MeshtasticAPI(container: container, startupRefresh: false)

		try await api.refreshBundledDevicesData()

		// Exact count, derived from the catalog rather than hardcoded: the seed upserts keyed on
		// platformioTarget, so it is one row per *distinct* target (the catalog lists `native`
		// twice). `!devices.isEmpty` would pass with a single garbage row.
		let expectedTargets = Set(try bundledCatalog().map(\.platformioTarget))
		let devices = try container.mainContext.fetch(FetchDescriptor<DeviceHardwareEntity>())
		#expect(
			devices.count == expectedTargets.count,
			"expected one row per distinct platformioTarget (\(expectedTargets.count)), got \(devices.count)"
		)
		#expect(Set(devices.compactMap(\.platformioTarget)) == expectedTargets)

		// The DB-side statement of the split: the seed populates metadata and nothing else. Images
		// and msh.to links are network-backed and now belong to refreshDeviceImagesAndLinks(), so
		// their tables must still be empty here. This is what fails if the network tail is merged
		// back into the seed.
		let images = try container.mainContext.fetch(FetchDescriptor<DeviceHardwareImageEntity>())
		#expect(images.isEmpty, "the bundled seed must not create image rows — that is the network pass's job")
		let links = try container.mainContext.fetch(FetchDescriptor<DeviceLinkEntity>())
		#expect(links.isEmpty, "the bundled seed must not import msh.to links — that is the network pass's job")
	}

	private func imageRequests(from urls: [URL]) -> [String] {
		urls.map(\.absoluteString).filter { $0.contains("/img/devices/") }
	}

	private func duplicates(in values: [String]) -> [String] {
		Dictionary(grouping: values, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
	}

	/// Raised in review on #2208: the bundled seed and the API refresh each ran their own image
	/// and link pass, so every online startup fetched all 82 ETags twice. One pass, one request
	/// per image.
	@Test @MainActor func offlineImageRefreshRequestsEachImageOnce() async throws {
		URLProtocol.registerClass(RequestRecordingURLProtocol.self)
		RequestRecordingURLProtocol.reset()
		defer { URLProtocol.unregisterClass(RequestRecordingURLProtocol.self) }

		let api = MeshtasticAPI(container: try makeContainer(), startupRefresh: false)
		await api.refreshDeviceImagesAndLinks()

		let images = imageRequests(from: RequestRecordingURLProtocol.recordedURLs)
		#expect(!images.isEmpty, "the bundled catalog should yield image requests")
		#expect(duplicates(in: images).isEmpty, "image requested more than once: \(duplicates(in: images))")

		// Pin the count to the catalog rather than hardcoding it: one request per *unique* image
		// file name. The catalog currently holds more entries than names because several platforms
		// share an image, and the request URL derives from the file name alone.
		let uniqueBundledImageNames = try bundledImageNames()
		#expect(
			images.count == uniqueBundledImageNames.count,
			"expected one request per unique image name (\(uniqueBundledImageNames.count)), got \(images.count)"
		)
	}

	// Mirrors only the two fields these assertions need. It has to be a local shape because
	// production's `DeviceHardware` is `private` to MeshtasticAPI.swift and so is not reachable
	// even under `@testable`. Worth promoting to a shared internal helper if the mirror grows.
	private struct CatalogEntry: Decodable {
		let platformioTarget: String
		let images: [String]?
	}

	/// The app's bundled `DeviceHardware.json`, decoded.
	private func bundledCatalog() throws -> [CatalogEntry] {
		let url = try #require(Bundle.main.url(forResource: "DeviceHardware.json", withExtension: nil))
		return try JSONDecoder().decode([CatalogEntry].self, from: Data(contentsOf: url))
	}

	/// The unique image file names in the app's bundled `DeviceHardware.json`.
	private func bundledImageNames() throws -> Set<String> {
		Set(try bundledCatalog().flatMap { $0.images ?? [] })
	}

	/// Raw bytes of the app's bundled `DeviceHardware.json`, for use as a stubbed API payload.
	private func bundledCatalogData() throws -> Data {
		let url = try #require(Bundle.main.url(forResource: "DeviceHardware.json", withExtension: nil))
		return try Data(contentsOf: url)
	}

	/// Polls until the detached startup cascade stops issuing image requests, then returns them.
	/// The cascade is unstructured `Task.detached` work with no completion handle to await.
	private func settledImageRequests(
		timeout: Duration = .seconds(30),
		quietPolls: Int = 5,
		pollInterval: Duration = .milliseconds(100)
	) async throws -> [String] {
		var lastCount = -1
		var stablePolls = 0
		let deadline = ContinuousClock.now.advanced(by: timeout)
		while ContinuousClock.now < deadline {
			try await Task.sleep(for: pollInterval)
			let current = imageRequests(from: RequestRecordingURLProtocol.recordedURLs)
			if current.count == lastCount && !current.isEmpty {
				stablePolls += 1
				if stablePolls >= quietPolls { return current }
			} else {
				stablePolls = 0
				lastCount = current.count
			}
		}
		return imageRequests(from: RequestRecordingURLProtocol.recordedURLs)
	}

	/// The regression raised in review on #2208: the bundled seed and the API refresh each ran
	/// their own image/link pass, so *every startup* fetched every ETag twice. This drives the real
	/// launch cascade rather than a single function, because "every startup" was the claim.
	///
	/// The API endpoint is stubbed with the bundled catalog itself, so the union of the two lists
	/// is exactly the bundled set: one pass is N requests, the old double pass would be 2N.
	@Test @MainActor func startupCascadeRunsOneImagePass() async throws {
		URLProtocol.registerClass(RequestRecordingURLProtocol.self)
		RequestRecordingURLProtocol.reset(stubs: [
			"api.meshtastic.org/resource/deviceHardware": try bundledCatalogData()
		])
		defer { URLProtocol.unregisterClass(RequestRecordingURLProtocol.self) }

		// Retained for the lifetime of the test: the cascade is detached and captures self.
		let api = MeshtasticAPI(container: try makeContainer(), startupRefresh: true)
		defer { _ = api }

		let images = try await settledImageRequests()
		let expected = try bundledImageNames()

		#expect(duplicates(in: images).isEmpty, "image requested more than once: \(duplicates(in: images))")
		#expect(
			images.count == expected.count,
			"startup should issue one request per unique image (\(expected.count)), got \(images.count)"
		)
	}

	/// The API-driven pass must cover hardware that exists only in the live API list (which the
	/// bundled snapshot can lag behind) while still not re-requesting the bundled images, and must
	/// import the msh.to link catalog exactly once.
	@Test @MainActor func apiRefreshCoversApiOnlyHardwareWithoutDuplicating() async throws {
		let apiOnly = """
		[{
		  "hwModel": 99001,
		  "hwModelSlug": "API_ONLY_TEST",
		  "platformioTarget": "api_only_test",
		  "architecture": "esp32",
		  "activelySupported": true,
		  "displayName": "API Only Test Device",
		  "images": ["api-only-test.svg"]
		}]
		"""
		URLProtocol.registerClass(RequestRecordingURLProtocol.self)
		RequestRecordingURLProtocol.reset(stubs: [
			"api.meshtastic.org/resource/deviceHardware": Data(apiOnly.utf8)
		])
		defer { URLProtocol.unregisterClass(RequestRecordingURLProtocol.self) }

		let api = MeshtasticAPI(container: try makeContainer(), startupRefresh: false)
		try await api.refreshDevicesAPIData()

		// One snapshot, two views of it — see the note in bundledSeedIssuesNoNetworkRequests.
		let recordedURLs = RequestRecordingURLProtocol.recordedURLs
		let recorded = recordedURLs.map(\.absoluteString)
		let images = imageRequests(from: recordedURLs)

		#expect(
			images.filter { $0.hasSuffix("api-only-test.svg") }.count == 1,
			"API-only hardware should have its image fetched exactly once"
		)
		// Assert the whole bundled set is covered, not one hand-picked device. `DeviceHardware.json`
		// is a regenerated file, so naming a single entry would fail on an unrelated catalog regen
		// while also missing any partial-union regression that happened to spare that entry.
		let requestedNames = Set(images.compactMap { URL(string: $0)?.lastPathComponent })
		let bundledNames = try bundledImageNames()
		#expect(
			bundledNames.isSubset(of: requestedNames),
			"""
			bundled hardware should still be covered by the API-driven pass; \
			missing: \(bundledNames.subtracting(requestedNames).sorted())
			"""
		)
		#expect(
			images.count == bundledNames.count + 1,
			"expected the bundled set plus the one API-only image (\(bundledNames.count + 1)), got \(images.count)"
		)
		#expect(duplicates(in: images).isEmpty, "image requested more than once: \(duplicates(in: images))")
		#expect(
			recorded.filter { $0.contains("msh.to/api/urls") }.count == 1,
			"the msh.to link catalog should be imported exactly once per pass"
		)
	}

	/// The image/link pass is throttled to once per `staleDeviceImageLinkInterval` (48h). Step 3b
	/// fires it on every reconnect, so without the throttle each reconnect re-issued ~78 ETag HEADs.
	/// The first pass hits the network; a second pass inside the window must issue nothing.
	@Test @MainActor func imageRefreshThrottledWithinWindow() async throws {
		URLProtocol.registerClass(RequestRecordingURLProtocol.self)
		RequestRecordingURLProtocol.reset()
		defer { URLProtocol.unregisterClass(RequestRecordingURLProtocol.self) }

		let api = MeshtasticAPI(container: try makeContainer(), startupRefresh: false)
		await api.refreshDeviceImagesAndLinks()
		#expect(!imageRequests(from: RequestRecordingURLProtocol.recordedURLs).isEmpty,
				"the first pass should hit the network")

		RequestRecordingURLProtocol.reset()
		await api.refreshDeviceImagesAndLinks()
		let secondPass = imageRequests(from: RequestRecordingURLProtocol.recordedURLs)
		#expect(secondPass.isEmpty,
				"a second pass inside the 48h window must issue no network requests, got \(secondPass.count)")
	}

	/// `clearDatabase` wipes `DeviceHardwareImageEntity`/`DeviceLinkEntity` and resets
	/// `lastDeviceImageAndLinkUpdate` so Step 3b restores them rather than skipping as "refreshed
	/// recently". Resetting the timestamp (what the clear does) must re-enable the pass in-window.
	@Test @MainActor func resetTimestampReenablesImageRefreshAfterClear() async throws {
		URLProtocol.registerClass(RequestRecordingURLProtocol.self)
		RequestRecordingURLProtocol.reset()
		defer { URLProtocol.unregisterClass(RequestRecordingURLProtocol.self) }

		let api = MeshtasticAPI(container: try makeContainer(), startupRefresh: false)
		await api.refreshDeviceImagesAndLinks()   // first pass arms the throttle
		#expect(!imageRequests(from: RequestRecordingURLProtocol.recordedURLs).isEmpty)

		// Exactly what clearDatabase does after wiping the image/link rows.
		DeviceImageLinkThrottle.invalidate()

		RequestRecordingURLProtocol.reset()
		await api.refreshDeviceImagesAndLinks()
		#expect(!imageRequests(from: RequestRecordingURLProtocol.recordedURLs).isEmpty,
				"resetting the throttle (as clearDatabase does) must let the pass run again in-window")
	}

	/// A refresh pass that a `clearDatabase` superseded must not re-arm the throttle.
	///
	/// Step 3b spawns the pass detached, so a clear can land while it is still downloading. The
	/// pass then finishes and records completion — against rows the clear already deleted. If that
	/// write lands, the throttle reads "refreshed recently" while the catalog is empty, and the
	/// restore the clear armed never runs for the rest of the 48h window.
	@Test func supersededPassDoesNotReArmThrottle() throws {
		let token = try #require(
			DeviceImageLinkThrottle.beginIfStale(interval: MeshtasticAPI.staleDeviceImageLinkInterval),
			"the suite starts un-throttled, so a pass must be claimable"
		)

		// The clear lands while the pass is still in flight.
		DeviceImageLinkThrottle.invalidate()

		// The in-flight pass now finishes and tries to record completion.
		DeviceImageLinkThrottle.complete(token: token)

		#expect(UserDefaults.lastDeviceImageAndLinkUpdate == .distantPast,
				"a pass superseded by a clear must leave the throttle invalidated so the restore runs")
		#expect(DeviceImageLinkThrottle.beginIfStale(
			interval: MeshtasticAPI.staleDeviceImageLinkInterval
		) != nil, "the next pass must still be claimable after the superseded completion")
	}

	/// The complement: an uncontended pass records completion and arms the throttle.
	@Test func uncontendedPassArmsThrottle() throws {
		let token = try #require(
			DeviceImageLinkThrottle.beginIfStale(interval: MeshtasticAPI.staleDeviceImageLinkInterval)
		)

		DeviceImageLinkThrottle.complete(token: token)

		#expect(UserDefaults.lastDeviceImageAndLinkUpdate != .distantPast,
				"a pass that completed uncontended should record its completion")
		#expect(DeviceImageLinkThrottle.beginIfStale(
			interval: MeshtasticAPI.staleDeviceImageLinkInterval
		) == nil, "a second pass inside the window must be refused")
	}
}
