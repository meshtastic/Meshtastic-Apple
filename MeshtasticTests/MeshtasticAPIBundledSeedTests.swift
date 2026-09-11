import Foundation
import SwiftData
import Testing

@testable import Meshtastic

/// Records every request the URL loading system is asked to perform, and fails them
/// immediately so a test can never depend on real network reachability.
///
/// Scope caveat: `URLProtocol.registerClass` only intercepts `URLSession.shared` and sessions
/// built from a default configuration. That covers the code under test — `URL.dataWithETag()`
/// uses `URLSession.shared` — but a future regression that reaches the network through a
/// custom-configured session would slip past this recorder.
///
/// Registration is process-global, so a suite using this must not run alongside another suite
/// that does its own networking. No other suite in this target does today; `.serialized` on the
/// suite below covers ordering within it.
///
/// Not `final`: the URLProtocol hooks below are class-method overrides, which SwiftLint's
/// `static_over_final_class` rule would otherwise flag.
class RequestRecordingURLProtocol: URLProtocol {
	private static let lock = NSLock()
	nonisolated(unsafe) private static var recorded: [URLRequest] = []

	nonisolated(unsafe) private static var stubs: [String: Data] = [:]
	nonisolated(unsafe) private static var stubStatusCodes: [String: Int] = [:]
	nonisolated(unsafe) private static var suspendedStubKeys: Set<String> = []

	/// Applied to every stubbed response when set, so the ETag-skip path is testable.
	nonisolated(unsafe) private static var stubETag: String?

	/// Resets the recorder. Any request whose URL contains one of the `stubs` keys is answered
	/// with that body and its configured status code; everything else fails immediately.
	static func reset(
		stubs: [String: Data] = [:],
		eTag: String? = nil,
		statusCodes: [String: Int] = [:],
		suspendedStubKeys: Set<String> = []
	) {
		lock.lock()
		recorded = []
		Self.stubs = stubs
		Self.stubETag = eTag
		Self.stubStatusCodes = statusCodes
		Self.suspendedStubKeys = suspendedStubKeys
		lock.unlock()
	}

	static var recordedRequests: [URLRequest] {
		lock.lock()
		defer { lock.unlock() }
		return recorded
	}

	static var recordedURLs: [URL] {
		recordedRequests.compactMap(\.url)
	}

	// Recording happens in startLoading(), not here: the URL loading system may call canInit
	// several times while deciding who handles a request, which would inflate the counts.
	override class func canInit(with request: URLRequest) -> Bool { true }

	override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

	override func startLoading() {
		let absolute = request.url?.absoluteString ?? ""
		Self.lock.lock()
		Self.recorded.append(request)
		Self.lock.unlock()
		Self.lock.lock()
		let stubbed = Self.stubs.first { absolute.contains($0.key) }?.value
		let statusCode = Self.stubStatusCodes.first { absolute.contains($0.key) }?.value ?? 200
		let isSuspended = Self.suspendedStubKeys.contains { absolute.contains($0) }
		let eTag = Self.stubETag
		Self.lock.unlock()

		if isSuspended { return }

		var headers = ["Content-Type": "application/json"]
		if let eTag { headers["ETag"] = eTag }
		guard let body = stubbed, let url = request.url, let response = HTTPURLResponse(
			url: url,
			statusCode: statusCode,
			httpVersion: "HTTP/1.1",
			headerFields: headers
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

	/// Stub key for the device catalog, taken from the endpoint the app actually calls rather
	/// than written out here. A hardcoded host stops matching the moment the endpoint moves,
	/// and the request then escapes to the real network — which is how these tests started
	/// failing on a CI runner with no internet.
	private var deviceHardwareStubKey: String {
		let endpoint = MeshtasticAPI.deviceURLEndpoint
		return (endpoint.host ?? "") + endpoint.path
	}

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

		let imageNetworkRequests = RequestRecordingURLProtocol.recordedRequests.filter {
			$0.url?.absoluteString.contains("/img/devices/") == true
		}
		let images = imageRequests(from: imageNetworkRequests.compactMap(\.url))
		#expect(!images.isEmpty, "the bundled catalog should yield image requests")
		#expect(
			imageNetworkRequests.allSatisfy { ($0.httpMethod ?? "GET") == "GET" },
			"device images should use one cache-aware GET rather than a separate HEAD"
		)
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
	///
	/// Settles on the count of ALL recorded requests, not just images: the cascade's tail —
	/// orphan cleanup, then the msh.to link import — runs after the last image fetch, and a
	/// settle that only watched images could return while that tail was still in flight. On a
	/// slow runner the straggling link fetch then landed inside the NEXT test's recording
	/// window, which counted it as a duplicate. CI caught that; local machines never did.
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
			let all = RequestRecordingURLProtocol.recordedURLs
			// The link import is the cascade's last network call, so the record is only
			// complete once it is present — a quiet stretch between the images and the
			// link fetch must not count as settled.
			let tailArrived = all.contains { $0.absoluteString.contains("msh.to/api/urls") }
			if all.count == lastCount && tailArrived && !imageRequests(from: all).isEmpty {
				stablePolls += 1
				if stablePolls >= quietPolls { return imageRequests(from: all) }
			} else {
				stablePolls = 0
				lastCount = all.count
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
			deviceHardwareStubKey: try bundledCatalogData()
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
		// The regression this suite caught on CI: the cascade's trailing link import must be in
		// the record before the helper returns, or it lands in the next test's window instead.
		let linkImports = RequestRecordingURLProtocol.recordedURLs.filter { $0.absoluteString.contains("msh.to/api/urls") }
		#expect(linkImports.count == 1, "the cascade imports the link catalog exactly once, inside this test's window")
	}

	/// The API-driven pass must cover hardware that exists only in the live API list (which the
	/// bundled snapshot can lag behind) while still not re-requesting the bundled images, and must
	/// import the msh.to link catalog exactly once.
	/// The caching this PR adds: an unchanged ETag skips the decode and the upsert, a new ETag
	/// does not, and a server that sends no ETag (api.meshtastic.org until its DNS moves to the
	/// cached deployment) behaves exactly as before.
	@Test @MainActor func matchingETagSkipsTheUpsert() async throws {
		func catalog(name: String) -> Data {
			Data("""
			[{
			  "hwModel": 99002,
			  "hwModelSlug": "ETAG_TEST",
			  "platformioTarget": "etag_test",
			  "architecture": "esp32",
			  "activelySupported": true,
			  "displayName": "\(name)",
			  "images": []
			}]
			""".utf8)
		}
		let eTagKey = "api.etag.\(MeshtasticAPI.deviceCatalogETagKey)"
		UserDefaults.standard.removeObject(forKey: eTagKey)
		defer { UserDefaults.standard.removeObject(forKey: eTagKey) }
		URLProtocol.registerClass(RequestRecordingURLProtocol.self)
		defer { URLProtocol.unregisterClass(RequestRecordingURLProtocol.self) }

		let container = try makeContainer()
		let api = MeshtasticAPI(container: container, startupRefresh: false)
		let context = container.mainContext
		func displayName() throws -> String? {
			let hwModel: Int64 = 99002
			return try context.fetch(FetchDescriptor<DeviceHardwareEntity>(
				predicate: #Predicate { $0.hwModel == hwModel })).first?.displayName
		}

		// First fetch stores the payload and its ETag.
		RequestRecordingURLProtocol.reset(
			stubs: ["api.meshtastic.org/resource/deviceHardware": catalog(name: "First")], eTag: "v1")
		try await api.refreshDevicesAPIData(includeImages: false)
		#expect(try displayName() == "First")
		#expect(MeshtasticAPI.lastETag(for: MeshtasticAPI.deviceCatalogETagKey) == "v1")

		// Same ETag, different body: the skip means the body is never applied — that is the
		// database pass this cache exists to avoid.
		RequestRecordingURLProtocol.reset(
			stubs: ["api.meshtastic.org/resource/deviceHardware": catalog(name: "Skipped")], eTag: "v1")
		try await api.refreshDevicesAPIData(includeImages: false)
		#expect(try displayName() == "First", "an unchanged ETag must skip the upsert")

		// New ETag: the pass runs and the change lands.
		RequestRecordingURLProtocol.reset(
			stubs: ["api.meshtastic.org/resource/deviceHardware": catalog(name: "Second")], eTag: "v2")
		try await api.refreshDevicesAPIData(includeImages: false)
		#expect(try displayName() == "Second", "a new ETag must not be skipped")
		#expect(MeshtasticAPI.lastETag(for: MeshtasticAPI.deviceCatalogETagKey) == "v2")

		// No ETag at all — today's api.meshtastic.org — upserts every time, as before.
		RequestRecordingURLProtocol.reset(
			stubs: ["api.meshtastic.org/resource/deviceHardware": catalog(name: "Third")])
		try await api.refreshDevicesAPIData(includeImages: false)
		#expect(try displayName() == "Third", "no ETag means no skip")
	}
}

extension MeshtasticAPIBundledSeedTests {
	@Test @MainActor func matchingCatalogETagStillRunsImageRefresh() async throws {
		func catalog(displayName: String) -> Data {
			Data("""
			[{
			  "hwModel": 99004,
			  "hwModelSlug": "ETAG_IMAGE_TEST",
			  "platformioTarget": "etag_image_test",
			  "architecture": "esp32",
			  "activelySupported": true,
			  "displayName": "\(displayName)",
			  "images": ["etag-image-test.svg"]
			}]
			""".utf8)
		}
		let imageData = Data("<svg>etag image</svg>".utf8)
		let eTagKey = "api.etag.\(MeshtasticAPI.deviceCatalogETagKey)"
		UserDefaults.standard.removeObject(forKey: eTagKey)
		defer { UserDefaults.standard.removeObject(forKey: eTagKey) }
		URLProtocol.registerClass(RequestRecordingURLProtocol.self)
		defer { URLProtocol.unregisterClass(RequestRecordingURLProtocol.self) }

		let container = try makeContainer()
		let api = MeshtasticAPI(container: container, startupRefresh: false)
		RequestRecordingURLProtocol.reset(
			stubs: [deviceHardwareStubKey: catalog(displayName: "Original")],
			eTag: "catalog-v1"
		)
		try await api.refreshDevicesAPIData(includeImages: false)

		RequestRecordingURLProtocol.reset(
			stubs: [
				deviceHardwareStubKey: catalog(displayName: "Must not be applied"),
				"etag-image-test.svg": imageData
			],
			eTag: "catalog-v1"
		)
		try await api.refreshDevicesAPIData()

		let images = imageRequests(from: RequestRecordingURLProtocol.recordedURLs)
		#expect(
			images.filter { $0.hasSuffix("etag-image-test.svg") }.count == 1,
			"a matching catalog ETag must skip only the metadata upsert, not the image refresh"
		)
		let devices = try container.mainContext.fetch(FetchDescriptor<DeviceHardwareEntity>())
		let device = try #require(devices.first { $0.platformioTarget == "etag_image_test" })
		#expect(device.displayName == "Original", "a matching ETag must still skip the metadata upsert")
	}

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
		let apiOnlyImage = Data("<svg>api-only</svg>".utf8)
		URLProtocol.registerClass(RequestRecordingURLProtocol.self)
		RequestRecordingURLProtocol.reset(stubs: [
			deviceHardwareStubKey: Data(apiOnly.utf8),
			"api-only-test.svg": apiOnlyImage
		])
		defer { URLProtocol.unregisterClass(RequestRecordingURLProtocol.self) }

		let container = try makeContainer()
		let api = MeshtasticAPI(container: container, startupRefresh: false)
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

		let devices = try container.mainContext.fetch(FetchDescriptor<DeviceHardwareEntity>())
		let apiOnlyDevice = try #require(devices.first { $0.platformioTarget == "api_only_test" })
		let storedImage = try #require(apiOnlyDevice.images.first { $0.fileName == "api-only-test.svg" })
		#expect(storedImage.svgData == apiOnlyImage, "a valid image response should not require an ETag")
		#expect(storedImage.eTag == nil)

		#expect(
			recorded.filter { $0.contains("msh.to/api/urls") }.count == 1,
			"the msh.to link catalog should be imported exactly once per pass"
		)
	}

	@Test @MainActor func failedOrEmptyImageResponsePreservesStoredImage() async throws {
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
		let catalogData = Data(apiOnly.utf8)
		let originalImage = Data("<svg>original</svg>".utf8)
		URLProtocol.registerClass(RequestRecordingURLProtocol.self)
		defer { URLProtocol.unregisterClass(RequestRecordingURLProtocol.self) }

		RequestRecordingURLProtocol.reset(stubs: [
			deviceHardwareStubKey: catalogData,
			"api-only-test.svg": originalImage
		])
		let container = try makeContainer()
		let api = MeshtasticAPI(container: container, startupRefresh: false)
		try await api.refreshDevicesAPIData()

		let failures = [
			(body: Data("server error".utf8), statusCode: 500, name: "HTTP error"),
			(body: Data(), statusCode: 200, name: "empty response")
		]
		for failure in failures {
			UserDefaults.lastDeviceImageAndLinkUpdate = .distantPast
			RequestRecordingURLProtocol.reset(
				stubs: [
					deviceHardwareStubKey: catalogData,
					"api-only-test.svg": failure.body
				],
				statusCodes: ["api-only-test.svg": failure.statusCode]
			)
			try await api.refreshDevicesAPIData()

			let devices = try container.mainContext.fetch(FetchDescriptor<DeviceHardwareEntity>())
			let apiOnlyDevice = try #require(devices.first { $0.platformioTarget == "api_only_test" })
			let storedImage = try #require(apiOnlyDevice.images.first { $0.fileName == "api-only-test.svg" })
			#expect(
				storedImage.svgData == originalImage,
				"a \(failure.name) must not replace a stored image"
			)
		}
	}

	@Test @MainActor func bundleFallbackFillsMissingSharedCopyWithoutReplacingExistingImage() async throws {
		let sharedImageName = "rak4631.svg"
		let apiCatalog = """
		[
		  {
		    "hwModel": 99001,
		    "hwModelSlug": "SHARED_IMAGE_ONE",
		    "platformioTarget": "shared_image_one",
		    "architecture": "esp32",
		    "activelySupported": true,
		    "displayName": "Shared Image One",
		    "images": ["\(sharedImageName)"]
		  },
		  {
		    "hwModel": 99002,
		    "hwModelSlug": "SHARED_IMAGE_TWO",
		    "platformioTarget": "shared_image_two",
		    "architecture": "esp32",
		    "activelySupported": true,
		    "displayName": "Shared Image Two",
		    "images": ["\(sharedImageName)"]
		  }
		]
		"""
		let catalogData = Data(apiCatalog.utf8)
		let networkImage = Data("<svg>newer network image</svg>".utf8)
		URLProtocol.registerClass(RequestRecordingURLProtocol.self)
		defer { URLProtocol.unregisterClass(RequestRecordingURLProtocol.self) }

		RequestRecordingURLProtocol.reset(stubs: [
			deviceHardwareStubKey: catalogData,
			sharedImageName: networkImage
		])
		let container = try makeContainer()
		let api = MeshtasticAPI(container: container, startupRefresh: false)
		try await api.refreshDevicesAPIData()

		var devices = try container.mainContext.fetch(FetchDescriptor<DeviceHardwareEntity>())
		let secondDevice = try #require(devices.first { $0.platformioTarget == "shared_image_two" })
		let secondImage = try #require(secondDevice.images.first { $0.fileName == sharedImageName })
		container.mainContext.delete(secondImage)
		try container.mainContext.save()

		UserDefaults.lastDeviceImageAndLinkUpdate = .distantPast
		RequestRecordingURLProtocol.reset(
			stubs: [
				deviceHardwareStubKey: catalogData,
				sharedImageName: Data("server error".utf8)
			],
			statusCodes: [sharedImageName: 500]
		)
		try await api.refreshDevicesAPIData()

		devices = try container.mainContext.fetch(FetchDescriptor<DeviceHardwareEntity>())
		let firstDevice = try #require(devices.first { $0.platformioTarget == "shared_image_one" })
		let refreshedSecondDevice = try #require(devices.first { $0.platformioTarget == "shared_image_two" })
		let firstImage = try #require(firstDevice.images.first { $0.fileName == sharedImageName })
		let restoredSecondImage = try #require(
			refreshedSecondDevice.images.first { $0.fileName == sharedImageName }
		)
		#expect(firstImage.svgData == networkImage, "bundle fallback must preserve an existing shared copy")
		#expect(restoredSecondImage.svgData?.isEmpty == false, "bundle fallback should fill the missing copy")
		#expect(restoredSecondImage.eTag == "bundled")
	}

	/// The image/link pass is throttled to once per `staleDeviceImageLinkInterval` (48h). Step 3b
	/// fires it on every reconnect, so without the throttle each reconnect revalidates every image.
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

	@Test @MainActor func cancellationDuringImageRequestDoesNotWriteBundleFallback() async throws {
		let sharedImageName = "rak4631.svg"
		let apiCatalog = """
		[{
		  "hwModel": 99003,
		  "hwModelSlug": "CANCEL_IMAGE_TEST",
		  "platformioTarget": "cancel_image_test",
		  "architecture": "esp32",
		  "activelySupported": true,
		  "displayName": "Cancel Image Test",
		  "images": ["\(sharedImageName)"]
		}]
		"""
		URLProtocol.registerClass(RequestRecordingURLProtocol.self)
		RequestRecordingURLProtocol.reset(
			stubs: [deviceHardwareStubKey: Data(apiCatalog.utf8)],
			suspendedStubKeys: [sharedImageName]
		)
		defer { URLProtocol.unregisterClass(RequestRecordingURLProtocol.self) }

		let container = try makeContainer()
		let api = MeshtasticAPI(container: container, startupRefresh: false)
		let refreshTask = Task { try? await api.refreshDevicesAPIData() }
		let deadline = ContinuousClock.now.advanced(by: .seconds(5))
		while ContinuousClock.now < deadline,
			  !RequestRecordingURLProtocol.recordedURLs.contains(where: { $0.lastPathComponent == sharedImageName }) {
			try await Task.sleep(for: .milliseconds(10))
		}
		let requestStarted = RequestRecordingURLProtocol.recordedURLs.contains {
			$0.lastPathComponent == sharedImageName
		}
		refreshTask.cancel()
		await refreshTask.value
		#expect(requestStarted, "the test must cancel while the image request is in flight")

		let devices = try container.mainContext.fetch(FetchDescriptor<DeviceHardwareEntity>())
		let device = try #require(devices.first { $0.platformioTarget == "cancel_image_test" })
		#expect(
			device.images.contains { $0.fileName == sharedImageName } == false,
			"cancellation must not write the bundled image"
		)
		#expect(UserDefaults.lastDeviceImageAndLinkUpdate == .distantPast)
	}

	@Test @MainActor func cancellationDuringLinkRequestDoesNotImportBundleOrArmThrottle() async throws {
		let linkURL = "msh.to/api/urls"
		URLProtocol.registerClass(RequestRecordingURLProtocol.self)
		RequestRecordingURLProtocol.reset(suspendedStubKeys: [linkURL])
		defer { URLProtocol.unregisterClass(RequestRecordingURLProtocol.self) }

		let container = try makeContainer()
		let api = MeshtasticAPI(container: container, startupRefresh: false)
		let refreshTask = Task { await api.refreshDeviceImagesAndLinks() }
		let deadline = ContinuousClock.now.advanced(by: .seconds(5))
		while ContinuousClock.now < deadline,
			  !RequestRecordingURLProtocol.recordedURLs.contains(where: { $0.absoluteString.contains(linkURL) }) {
			try await Task.sleep(for: .milliseconds(10))
		}
		let requestStarted = RequestRecordingURLProtocol.recordedURLs.contains {
			$0.absoluteString.contains(linkURL)
		}
		refreshTask.cancel()
		await refreshTask.value
		#expect(requestStarted, "the test must cancel while the link request is in flight")

		let linkCount = try container.mainContext.fetchCount(FetchDescriptor<DeviceLinkEntity>())
		#expect(linkCount == 0, "cancellation must not import bundled links")
		#expect(UserDefaults.lastDeviceImageAndLinkUpdate == .distantPast)
	}

	/// A disconnect cancels the Step 3b task running the pass (`closeConnection`). A cancelled pass
	/// must issue no image requests and leave the throttle un-armed so the next connect runs a real
	/// restore. Self-cancelling *before* the pass starts trips the worker's early guard
	/// deterministically — no scheduling race on when `.cancel()` lands.
	@Test @MainActor func cancelledPassIssuesNoRequestsAndLeavesThrottleUnarmed() async throws {
		URLProtocol.registerClass(RequestRecordingURLProtocol.self)
		RequestRecordingURLProtocol.reset()
		defer { URLProtocol.unregisterClass(RequestRecordingURLProtocol.self) }

		let api = MeshtasticAPI(container: try makeContainer(), startupRefresh: false)
		let task = Task {
			withUnsafeCurrentTask { $0?.cancel() }   // cancel before the pass does any work
			await api.refreshDeviceImagesAndLinks()
		}
		await task.value

		#expect(imageRequests(from: RequestRecordingURLProtocol.recordedURLs).isEmpty,
				"a pass cancelled before it starts must issue no image requests")
		#expect(UserDefaults.lastDeviceImageAndLinkUpdate == .distantPast,
				"a cancelled pass must not arm the throttle — the restore is left for the next connect")
	}
}
