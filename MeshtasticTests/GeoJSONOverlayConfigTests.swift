// GeoJSONOverlayConfigTests.swift
// MeshtasticTests

import Testing
import Foundation
import CoreLocation
import MapKit
@testable import Meshtastic

// MARK: - AnyCodableValue Tests

@Suite("AnyCodableValue Codable")
struct AnyCodableValueCodableTests {

	@Test func encodeDecodeString() throws {
		let value = AnyCodableValue.string("hello")
		let data = try JSONEncoder().encode(value)
		let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
		if case .string(let str) = decoded {
			#expect(str == "hello")
		} else {
			Issue.record("Expected .string")
		}
	}

	@Test func encodeDecodeInt() throws {
		let value = AnyCodableValue.int(42)
		let data = try JSONEncoder().encode(value)
		let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
		if case .int(let n) = decoded {
			#expect(n == 42)
		} else {
			Issue.record("Expected .int")
		}
	}

	@Test func encodeDecodeDouble() throws {
		let value = AnyCodableValue.double(3.14)
		let data = try JSONEncoder().encode(value)
		let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
		if case .double(let d) = decoded {
			#expect(abs(d - 3.14) < 0.001)
		} else {
			Issue.record("Expected .double")
		}
	}

	@Test func encodeDecodeBool() throws {
		let value = AnyCodableValue.bool(true)
		let data = try JSONEncoder().encode(value)
		let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
		if case .bool(let b) = decoded {
			#expect(b == true)
		} else {
			Issue.record("Expected .bool")
		}
	}

	@Test func encodeDecodeNull() throws {
		let value = AnyCodableValue.null
		let data = try JSONEncoder().encode(value)
		let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
		if case .null = decoded {} else {
			Issue.record("Expected .null")
		}
	}

	@Test func encodeDecodeArray() throws {
		let value = AnyCodableValue.array([.int(1), .string("two"), .bool(false)])
		let data = try JSONEncoder().encode(value)
		let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
		if case .array(let arr) = decoded {
			#expect(arr.count == 3)
		} else {
			Issue.record("Expected .array")
		}
	}

	@Test func encodeDecodeObject() throws {
		let value = AnyCodableValue.object(["key": .string("value"), "num": .int(5)])
		let data = try JSONEncoder().encode(value)
		let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
		if case .object(let dict) = decoded {
			#expect(dict.count == 2)
		} else {
			Issue.record("Expected .object")
		}
	}
}

// MARK: - RF Prediction GeoJSON Tests

@Suite("RF prediction GeoJSON overlays", .serialized)
struct RFGeoJSONOverlayTests {
	private static var contourFeatureCollectionData: Data {
		"""
		{
			"type": "FeatureCollection",
			"features": [
				{
					"type": "Feature",
					"properties": {
						"dbm": -118,
						"color": "rgb(125, 50, 168)"
					},
					"geometry": {
						"type": "MultiPolygon",
						"coordinates": [
							[
								[
									[-121.0, 37.0],
									[-121.0, 37.1],
									[-120.9, 37.1],
									[-120.9, 37.0],
									[-121.0, 37.0]
								]
							]
						]
					}
				}
			]
		}
		""".data(using: .utf8)!
	}

	@Test func multiPolygonCreatesRenderablePolygonOverlays() throws {
		let data = """
		{
			"type": "FeatureCollection",
			"features": [
				{
					"type": "Feature",
					"properties": {
						"dbm": -110,
						"color": "rgb(31, 119, 180)",
						"label": ">= -110 dBm"
					},
					"geometry": {
						"type": "MultiPolygon",
						"coordinates": [
							[
								[
									[-121.0, 37.0],
									[-121.0, 37.1],
									[-120.9, 37.1],
									[-120.9, 37.0],
									[-121.0, 37.0]
								]
							],
							[
								[
									[-120.8, 37.0],
									[-120.8, 37.1],
									[-120.7, 37.1],
									[-120.7, 37.0],
									[-120.8, 37.0]
								]
							]
						]
					}
				}
			]
		}
		""".data(using: .utf8)!

		let collection = try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: data)
		let feature = try #require(collection.features.first)
		let styledFeature = GeoJSONStyledFeature(feature: feature, overlayId: "rf")

		#expect(feature.geometry.type == "MultiPolygon")
		#expect(feature.rfPredictionColor == "rgb(31, 119, 180)")
		#expect(feature.dbm == -110)
		#expect(feature.effectiveFillOpacity > 0)
		#expect(styledFeature.createOverlays().count == 2)
		#expect(styledFeature.createOverlays().allSatisfy { $0.overlay is MKPolygon })
	}

	@Test func normalizesSitePlannerContourResponseWrapper() throws {
		let data = """
		{
			"contours": {
				"type": "FeatureCollection",
				"features": [
					{
						"type": "Feature",
						"properties": {
							"dbm": -118,
							"color": "rgb(125, 50, 168)",
							"label": ">= -118 dBm"
						},
						"geometry": {
							"type": "MultiPolygon",
							"coordinates": [
								[
									[
										[-121.0, 37.0],
										[-121.0, 37.1],
										[-120.9, 37.1],
										[-120.9, 37.0],
										[-121.0, 37.0]
									]
								]
							]
						}
					}
				]
			}
		}
		""".data(using: .utf8)!

		let normalizedData = try SitePlannerCoverageClient.normalizedFeatureCollectionData(from: data)
		let collection = try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: normalizedData)
		let feature = try #require(collection.features.first)

		#expect(collection.type == "FeatureCollection")
		#expect(collection.features.count == 1)
		#expect(feature.geometry.type == "MultiPolygon")
		#expect(feature.rfPredictionColor == "rgb(125, 50, 168)")
		#expect(feature.dbm == -118)
	}

	@Test func sitePlannerClientAcceptsDirectGeoJSONResponse() async throws {
		let endpoint = try #require(URL(string: "https://coverage.example.test/api"))
		let configuration = URLSessionConfiguration.ephemeral
		configuration.protocolClasses = [SitePlannerCoverageURLProtocol.self]
		SitePlannerCoverageURLProtocol.prepare(responses: [
			.init(contentType: "application/geo+json", data: Self.contourFeatureCollectionData)
		])

		let request = SitePlannerCoverageRequest(
			lat: 37.3349,
			lon: -122.0090,
			txPower: 22.0,
			frequencyMHz: 915.0
		)
		let data = try await SitePlannerCoverageClient(session: URLSession(configuration: configuration))
			.generateContours(from: endpoint, request: request)
		let observedRequest = try #require(SitePlannerCoverageURLProtocol.observedRequests().first)
		let object = try JSONSerialization.jsonObject(with: observedRequest.body) as? [String: Any]
		let collection = try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: data)

		#expect(observedRequest.url == URL(string: "https://coverage.example.test/api/predict"))
		#expect(observedRequest.method == "POST")
		#expect(observedRequest.headers["Content-Type"] == "application/json")
		#expect(observedRequest.headers["Accept"] == "application/geo+json, application/json, image/tiff")
		#expect(object?["lat"] as? Double == 37.3349)
		#expect(object?["lon"] as? Double == -122.0090)
		#expect(object?["tx_power"] as? Double == 22.0)
		#expect(collection.features.count == 1)
	}

	@Test func sitePlannerClientRunsPredictStatusResultFlowEndToEnd() async throws {
		let endpoint = try #require(URL(string: "https://site.meshtastic.org"))
		let configuration = URLSessionConfiguration.ephemeral
		configuration.protocolClasses = [SitePlannerCoverageURLProtocol.self]
		SitePlannerCoverageURLProtocol.prepare(responses: [
			.init(json: #"{"task_id":"site-planner-task"}"#),
			.init(json: #"{"task_id":"site-planner-task","status":"processing"}"#),
			.init(json: #"{"task_id":"site-planner-task","status":"completed"}"#),
			.init(contentType: "application/geo+json", data: Self.contourFeatureCollectionData)
		])

		let payload = SitePlannerCoverageRequest(
			lat: 37.3349,
			lon: -122.0090,
			txPower: 20.0,
			frequencyMHz: 907.0
		)
		let data = try await SitePlannerCoverageClient(
			session: URLSession(configuration: configuration),
			pollIntervalNanoseconds: 0,
			timeoutInterval: 10
		)
			.generateContours(from: endpoint, request: payload)
		let requests = SitePlannerCoverageURLProtocol.observedRequests()
		let predictRequest = try #require(requests.first)
		let bodyObject = try JSONSerialization.jsonObject(with: predictRequest.body) as? [String: Any]
		let collection = try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: data)

		#expect(requests.map(\.url.path) == ["/predict", "/status/site-planner-task", "/status/site-planner-task", "/result/site-planner-task"])
		#expect(predictRequest.method == "POST")
		#expect(predictRequest.headers["Content-Type"] == "application/json")
		#expect(predictRequest.headers["Accept"] == "application/geo+json, application/json, image/tiff")
		#expect(bodyObject?["lat"] as? Double == 37.3349)
		#expect(bodyObject?["lon"] as? Double == -122.0090)
		#expect(bodyObject?["tx_power"] as? Double == 20.0)
		#expect(bodyObject?["frequency_mhz"] as? Double == 907.0)
		#expect(bodyObject?["rx_gain"] as? Double == 2.0)
		#expect(bodyObject?["signal_threshold"] as? Double == -130.0)
		#expect(bodyObject?["colormap"] as? String == "plasma")
		#expect(bodyObject?["min_dbm"] as? Double == -130.0)
		#expect(bodyObject?["max_dbm"] as? Double == -80.0)
		#expect(collection.features.count == 1)

		MapDataManager.shared.initialize()
		let metadata = try await MapDataManager.shared.processGeoJSONData(
			data,
			originalName: "E2E Coverage Test",
			makeActive: false
		)
		#expect(metadata.overlayCount == 1)
		try await MapDataManager.shared.deleteFile(metadata)
	}

	@Test func sitePlannerClientReportsGeoTIFFResultsClearly() async throws {
		let endpoint = try #require(URL(string: "https://site.meshtastic.org"))
		let configuration = URLSessionConfiguration.ephemeral
		configuration.protocolClasses = [SitePlannerCoverageURLProtocol.self]
		SitePlannerCoverageURLProtocol.prepare(responses: [
			.init(json: #"{"task_id":"site-planner-task"}"#),
			.init(json: #"{"task_id":"site-planner-task","status":"completed"}"#),
			.init(contentType: "image/tiff", data: Data([0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00]))
		])

		do {
			_ = try await SitePlannerCoverageClient(
				session: URLSession(configuration: configuration),
				pollIntervalNanoseconds: 0,
				timeoutInterval: 10
			)
				.generateContours(from: endpoint, request: SitePlannerCoverageRequest(lat: 37.3349, lon: -122.0090))
			Issue.record("Expected GeoTIFF result to fail until raster import is supported.")
		} catch {
			#expect(error.localizedDescription.contains("GeoTIFF"))
			#expect(error.localizedDescription.contains("GeoJSON"))
		}
	}

	@Test func encodesSitePlannerCoverageRequestShape() throws {
		let request = SitePlannerCoverageRequest(
			lat: 37.3349,
			lon: -122.0090,
			txPower: 22.0,
			frequencyMHz: 915.0
		)

		let data = try JSONEncoder().encode(request)
		let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]

		#expect(object?["lat"] as? Double == 37.3349)
		#expect(object?["lon"] as? Double == -122.0090)
		#expect(object?["tx_height"] as? Double == 2.0)
		#expect(object?["tx_power"] as? Double == 22.0)
		#expect(object?["tx_gain"] as? Double == 2.0)
		#expect(object?["system_loss"] as? Double == 2.0)
		#expect(object?["frequency_mhz"] as? Double == 915.0)
		#expect(object?["rx_height"] as? Double == 1.0)
		#expect(object?["rx_gain"] as? Double == 2.0)
		#expect(object?["signal_threshold"] as? Double == -130.0)
		#expect(object?["clutter_height"] as? Double == 1.0)
		#expect(object?["ground_dielectric"] as? Double == 15.0)
		#expect(object?["ground_conductivity"] as? Double == 0.005)
		#expect(object?["atmosphere_bending"] as? Double == 301.0)
		#expect(object?["radio_climate"] as? String == "continental_temperate")
		#expect(object?["polarization"] as? String == "vertical")
		#expect(object?["radius"] as? Double == 30_000.0)
		#expect(object?["situation_fraction"] as? Double == 95.0)
		#expect(object?["time_fraction"] as? Double == 95.0)
		#expect(object?["high_resolution"] as? Bool == false)
		#expect(object?["colormap"] as? String == "plasma")
		#expect(object?["min_dbm"] as? Double == -130.0)
		#expect(object?["max_dbm"] as? Double == -80.0)
	}

	@Test func nativeSitePlannerEngineGeneratesGeoJSONWithoutNetwork() async throws {
		let payload = SitePlannerCoverageRequest(
			lat: 37.5,
			lon: -122.5,
			txHeight: 2.0,
			txPower: 20.0,
			frequencyMHz: 915.0,
			radius: 750.0
		)
		let data = try await NativeSitePlannerCoverageClient(
			terrainProvider: .seaLevel,
			contourMaxDimension: 40,
			runChunkSize: 1024
		)
		.generateContours(request: payload)
		let collection = try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: data)
		let feature = try #require(collection.features.first)

		#expect(collection.type == "FeatureCollection")
		#expect(collection.features.count > 0)
		#expect(feature.geometry.type == "MultiPolygon")
		#expect(feature.rfPredictionColor?.hasPrefix("rgb(") == true)
		#expect(feature.effectiveFillOpacity > 0)
		#expect(data.count < 10 * 1024 * 1024)
	}

	@Test func nativeSitePlannerTerrainNamingMatchesSitePlanner() {
		#expect(NativeSitePlannerTerrainService.tileName(for: NativeSitePlannerPageRef(minNorth: 51, minWest: 114)) == "N51W115")
		#expect(NativeSitePlannerTerrainService.tileName(for: NativeSitePlannerPageRef(minNorth: -34, minWest: 342)) == "S34E017")
		#expect(NativeSitePlannerTerrainService.tileURLs(for: "N51W115").map(\.absoluteString) == [
			"https://elevation-tiles-prod.s3.amazonaws.com/v2/skadi/N51/N51W115.hgt.gz",
			"https://elevation-tiles-prod.s3.amazonaws.com/skadi/N51/N51W115.hgt.gz"
		])
	}

	@Test func sitePlannerEndpointErrorsAreActionable() {
		let missingEndpoint = SitePlannerCoverageError.missingEndpoint.localizedDescription
		let publicSiteError = SitePlannerCoverageError.publicSiteAPIUnavailable.localizedDescription
		let httpError = SitePlannerCoverageError.httpStatus(405, "405 Not Allowed").localizedDescription
		let tiffError = SitePlannerCoverageError.unsupportedGeoTIFFResult.localizedDescription

		#expect(missingEndpoint.contains("/predict"))
		#expect(missingEndpoint.contains("/status/{task_id}"))
		#expect(missingEndpoint.contains("/result/{task_id}"))
		#expect(publicSiteError.contains("does not expose"))
		#expect(publicSiteError.contains("/predict"))
		#expect(publicSiteError.contains("/result/{task_id}"))
		#expect(httpError.contains("HTTP 405"))
		#expect(httpError.contains("405 Not Allowed"))
		#expect(tiffError.contains("GeoTIFF"))
		#expect(tiffError.contains("GeoJSON"))
		#expect(SitePlannerCoverageClient.usesPublicSitePlanner(for: URL(string: "https://site.meshtastic.org")!))
	}
}

private final class SitePlannerCoverageURLProtocol: URLProtocol {
	struct StubResponse {
		var statusCode: Int
		var headers: [String: String]
		var data: Data

		init(statusCode: Int = 200, contentType: String = "application/json", data: Data) {
			self.statusCode = statusCode
			self.headers = ["Content-Type": contentType]
			self.data = data
		}

		init(statusCode: Int = 200, json: String) {
			self.init(statusCode: statusCode, contentType: "application/json", data: Data(json.utf8))
		}
	}

	private static let lock = NSLock()
	nonisolated(unsafe) private static var responses: [StubResponse] = []
	nonisolated(unsafe) private static var requests: [RecordedRequest] = []

	override class func canInit(with request: URLRequest) -> Bool {
		true
	}

	override class func canonicalRequest(for request: URLRequest) -> URLRequest {
		request
	}

	override func startLoading() {
		let body = Self.bodyData(from: request) ?? Data()
		let responseStub = Self.record(request: request, body: body)
		guard let response = HTTPURLResponse(
			url: request.url!,
			statusCode: responseStub.statusCode,
			httpVersion: nil,
			headerFields: responseStub.headers
		) else {
			return
		}
		client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
		client?.urlProtocol(self, didLoad: responseStub.data)
		client?.urlProtocolDidFinishLoading(self)
	}

	override func stopLoading() {}

	static func prepare(responses: [StubResponse]) {
		lock.lock()
		Self.responses = responses
		Self.requests = []
		lock.unlock()
	}

	static func observedRequests() -> [RecordedRequest] {
		lock.lock()
		defer { lock.unlock() }
		return requests
	}

	private static func record(request: URLRequest, body: Data) -> StubResponse {
		lock.lock()
		defer { lock.unlock() }

		requests.append(
			RecordedRequest(
				url: request.url!,
				method: request.httpMethod ?? "",
				headers: request.allHTTPHeaderFields ?? [:],
				body: body
			)
		)

		if responses.isEmpty {
			return StubResponse(statusCode: 500, json: #"{"error":"missing test response"}"#)
		}
		return responses.removeFirst()
	}

	private static func bodyData(from request: URLRequest) -> Data? {
		if let httpBody = request.httpBody {
			return httpBody
		}

		guard let stream = request.httpBodyStream else {
			return nil
		}

		stream.open()
		defer { stream.close() }

		var data = Data()
		var buffer = [UInt8](repeating: 0, count: 4096)
		while stream.hasBytesAvailable {
			let count = stream.read(&buffer, maxLength: buffer.count)
			if count > 0 {
				data.append(buffer, count: count)
			} else {
				break
			}
		}
		return data
	}
}

private struct RecordedRequest {
	let url: URL
	let method: String
	let headers: [String: String]
	let body: Data
}

// MARK: - AnyCodableValue toAnyObject Tests

@Suite("AnyCodableValue toAnyObject Extended")
struct AnyCodableValueToAnyObjectExtendedTests {

	@Test func stringToAnyObject() {
		let value = AnyCodableValue.string("test")
		let obj = value.toAnyObject()
		#expect(obj as? String == "test")
	}

	@Test func intToAnyObject() {
		let value = AnyCodableValue.int(99)
		let obj = value.toAnyObject()
		#expect(obj as? Int == 99)
	}

	@Test func doubleToAnyObject() {
		let value = AnyCodableValue.double(1.5)
		let obj = value.toAnyObject()
		#expect(obj as? Double == 1.5)
	}

	@Test func boolToAnyObject() {
		let value = AnyCodableValue.bool(false)
		let obj = value.toAnyObject()
		#expect(obj as? Bool == false)
	}

	@Test func nullToAnyObject() {
		let value = AnyCodableValue.null
		let obj = value.toAnyObject()
		#expect(obj is NSNull)
	}

	@Test func arrayToAnyObject() {
		let value = AnyCodableValue.array([.int(1), .int(2)])
		let obj = value.toAnyObject()
		#expect((obj as? [Any])?.count == 2)
	}

	@Test func objectToAnyObject() {
		let value = AnyCodableValue.object(["a": .string("b")])
		let obj = value.toAnyObject()
		let dict = obj as? [String: Any]
		#expect(dict?["a"] as? String == "b")
	}
}

// MARK: - AnyCodableValue toCoordinate Tests

@Suite("AnyCodableValue toCoordinate Extended")
struct AnyCodableValueToCoordinateExtendedTests {

	@Test func validDoubleCoordinate() {
		let value = AnyCodableValue.array([.double(-122.4194), .double(37.7749)])
		let coord = value.toCoordinate()
		#expect(coord != nil)
		#expect(abs(coord!.latitude - 37.7749) < 0.0001)
		#expect(abs(coord!.longitude - (-122.4194)) < 0.0001)
	}

	@Test func validIntCoordinate() {
		let value = AnyCodableValue.array([.int(-122), .int(37)])
		let coord = value.toCoordinate()
		#expect(coord != nil)
		#expect(abs(coord!.latitude - 37.0) < 0.0001)
		#expect(abs(coord!.longitude - (-122.0)) < 0.0001)
	}

	@Test func tooFewElements() {
		let value = AnyCodableValue.array([.double(1.0)])
		#expect(value.toCoordinate() == nil)
	}

	@Test func notAnArray() {
		let value = AnyCodableValue.string("not coords")
		#expect(value.toCoordinate() == nil)
	}

	@Test func wrongElementTypes() {
		let value = AnyCodableValue.array([.string("a"), .string("b")])
		#expect(value.toCoordinate() == nil)
	}

	@Test func threeElements_usesFirstTwo() {
		let value = AnyCodableValue.array([.double(10.0), .double(20.0), .double(100.0)])
		let coord = value.toCoordinate()
		#expect(coord != nil)
		#expect(abs(coord!.longitude - 10.0) < 0.0001)
		#expect(abs(coord!.latitude - 20.0) < 0.0001)
	}
}

// MARK: - GeoJSONFeature Property Tests

@Suite("GeoJSONFeature Properties")
struct GeoJSONFeaturePropertyTests {

	private func makeFeature(properties: [String: AnyCodableValue]?) -> GeoJSONFeature {
		GeoJSONFeature(
			type: "Feature",
			id: nil,
			geometry: GeoJSONGeometry(type: "Point", coordinates: .array([.double(0), .double(0)])),
			properties: properties
		)
	}

	@Test func name_fromNAME() {
		let feature = makeFeature(properties: ["NAME": .string("Test Area")])
		#expect(feature.name == "Test Area")
	}

	@Test func name_fromLowercaseName() {
		let feature = makeFeature(properties: ["name": .string("Lower")])
		#expect(feature.name == "Lower")
	}

	@Test func name_defaultsToEmpty() {
		let feature = makeFeature(properties: nil)
		#expect(feature.name == "")
	}

	@Test func strokeWidth_fromDouble() {
		let feature = makeFeature(properties: ["stroke-width": .double(3.5)])
		#expect(feature.strokeWidth == 3.5)
	}

	@Test func strokeWidth_fromInt() {
		let feature = makeFeature(properties: ["stroke-width": .int(2)])
		#expect(feature.strokeWidth == 2.0)
	}

	@Test func strokeWidth_default() {
		let feature = makeFeature(properties: nil)
		#expect(feature.strokeWidth == 1.0)
	}

	@Test func fillOpacity_fromDouble() {
		let feature = makeFeature(properties: ["fill-opacity": .double(0.5)])
		#expect(feature.fillOpacity == 0.5)
	}

	@Test func fillOpacity_default() {
		let feature = makeFeature(properties: nil)
		#expect(feature.fillOpacity == 0.0)
	}

	@Test func strokeOpacity_default() {
		let feature = makeFeature(properties: nil)
		#expect(feature.strokeOpacity == 1.0)
	}

	@Test func effectiveStrokeColor_usesStroke() {
		let feature = makeFeature(properties: ["stroke": .string("#FF0000")])
		#expect(feature.effectiveStrokeColor == "#FF0000")
	}

	@Test func effectiveStrokeColor_fallsBackToMarkerColor() {
		let feature = makeFeature(properties: ["marker-color": .string("#00FF00")])
		#expect(feature.effectiveStrokeColor == "#00FF00")
	}

	@Test func effectiveStrokeColor_defaultBlack() {
		let feature = makeFeature(properties: nil)
		#expect(feature.effectiveStrokeColor == "#000000")
	}

	@Test func effectiveFillColor_withOpacity() {
		let feature = makeFeature(properties: [
			"fill": .string("#0000FF"),
			"fill-opacity": .double(0.5)
		])
		#expect(feature.effectiveFillColor == "#0000FF")
	}

	@Test func effectiveFillColor_noOpacity_returnsBlack() {
		let feature = makeFeature(properties: ["fill": .string("#0000FF")])
		#expect(feature.effectiveFillColor == "#000000")
	}

	@Test func markerRadius_small() {
		let feature = makeFeature(properties: ["marker-size": .string("small")])
		#expect(feature.markerRadius == 4.0)
	}

	@Test func markerRadius_medium() {
		let feature = makeFeature(properties: ["marker-size": .string("medium")])
		#expect(feature.markerRadius == 8.0)
	}

	@Test func markerRadius_large() {
		let feature = makeFeature(properties: ["marker-size": .string("large")])
		#expect(feature.markerRadius == 12.0)
	}

	@Test func markerRadius_default() {
		let feature = makeFeature(properties: nil)
		#expect(feature.markerRadius == 8.0)
	}

	@Test func isVisible_defaultTrue() {
		let feature = makeFeature(properties: nil)
		#expect(feature.isVisible == true)
	}

	@Test func isVisible_false() {
		let feature = makeFeature(properties: ["visible": .bool(false)])
		#expect(feature.isVisible == false)
	}

	@Test func layerId() {
		let feature = makeFeature(properties: ["layer_id": .string("layer1")])
		#expect(feature.layerId == "layer1")
	}

	@Test func layerName() {
		let feature = makeFeature(properties: ["layer_name": .string("My Layer")])
		#expect(feature.layerName == "My Layer")
	}

	@Test func layerDescription() {
		let feature = makeFeature(properties: ["description": .string("A description")])
		#expect(feature.layerDescription == "A description")
	}

	@Test func markerSymbol() {
		let feature = makeFeature(properties: ["marker-symbol": .string("circle")])
		#expect(feature.markerSymbol == "circle")
	}

	@Test func lineDashArray() {
		let feature = makeFeature(properties: ["line-dasharray": .array([.double(5.0), .double(3.0)])])
		#expect(feature.lineDashArray == [5.0, 3.0])
	}

	@Test func lineDashArray_nil() {
		let feature = makeFeature(properties: nil)
		#expect(feature.lineDashArray == nil)
	}
}

// MARK: - GeoJSONFeatureCollection Codable Tests

@Suite("GeoJSONFeatureCollection Codable")
struct GeoJSONFeatureCollectionCodableTests {

	@Test func decodeSimpleCollection() throws {
		let json = """
		{
			"type": "FeatureCollection",
			"features": [
				{
					"type": "Feature",
					"geometry": {
						"type": "Point",
						"coordinates": [-122.4194, 37.7749]
					},
					"properties": {
						"name": "San Francisco"
					}
				}
			]
		}
		"""
		let data = json.data(using: .utf8)!
		let collection = try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: data)
		#expect(collection.type == "FeatureCollection")
		#expect(collection.features.count == 1)
		#expect(collection.features[0].name == "San Francisco")
	}

	@Test func decodeEmptyCollection() throws {
		let json = """
		{
			"type": "FeatureCollection",
			"features": []
		}
		"""
		let data = json.data(using: .utf8)!
		let collection = try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: data)
		#expect(collection.features.isEmpty)
	}

	@Test func roundTrip() throws {
		let feature = GeoJSONFeature(
			type: "Feature",
			id: 1,
			geometry: GeoJSONGeometry(type: "Point", coordinates: .array([.double(10), .double(20)])),
			properties: ["name": .string("Test"), "value": .int(42)]
		)
		let collection = GeoJSONFeatureCollection(type: "FeatureCollection", features: [feature])

		let data = try JSONEncoder().encode(collection)
		let decoded = try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: data)
		#expect(decoded.features.count == 1)
		#expect(decoded.features[0].name == "Test")
		#expect(decoded.features[0].id == 1)
	}

	@Test func decodeWithPolygon() throws {
		let json = """
		{
			"type": "FeatureCollection",
			"features": [
				{
					"type": "Feature",
					"geometry": {
						"type": "Polygon",
						"coordinates": [[[0, 0], [1, 0], [1, 1], [0, 1], [0, 0]]]
					},
					"properties": {
						"fill": "#FF0000",
						"fill-opacity": 0.5,
						"stroke": "#000000",
						"stroke-width": 2
					}
				}
			]
		}
		"""
		let data = json.data(using: .utf8)!
		let collection = try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: data)
		let feature = collection.features[0]
		#expect(feature.fillColor == "#FF0000")
		#expect(feature.fillOpacity == 0.5)
		#expect(feature.strokeColor == "#000000")
		#expect(feature.strokeWidth == 2.0)
	}
}
