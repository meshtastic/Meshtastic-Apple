//
//  CoverageEstimateRunner.swift
//  Meshtastic
//
//  Drives the hosted Meshtastic Site Planner headlessly to compute a coverage
//  estimate and hand the styled GeoJSON straight back to the app — no visible
//  browser hop or manual share-sheet tap.
//
//  There is no headless params→GeoJSON HTTP API; the planner is a client-side
//  WASM SPLAT!/ITM simulator, so coverage is only ever computed in a WebView.
//  We load the planner with `run=1&bridge=1`, inject a tiny `__meshtasticNative`
//  shim (the object-injection contract the planner expects, since WKWebView has
//  no `addJavascriptInterface`), and receive the result via a script message.
//
//  See meshtastic/Meshtastic-Apple#2058.
//

import Foundation
import CoreLocation
import WebKit
import OSLog

/// Progress of a single headless coverage run.
enum CoverageEstimateState: Equatable {
	case idle
	case running
	case imported
	case failed(String)
}

/// Geographic bounding box (degrees) of an imported coverage overlay, used to frame the map on it.
struct CoverageBounds {
	let minLatitude: Double
	let maxLatitude: Double
	let minLongitude: Double
	let maxLongitude: Double
}

/// The result of a successful run: the imported overlay's metadata, the transmitter coordinate, and
/// the coverage geometry's bounding box (to frame the map on it). `Equatable` (by a per-result
/// token) so it can drive a SwiftUI `onChange`.
struct CoverageEstimateResult: Equatable {
	let token = UUID()
	let metadata: MapDataMetadata
	let coordinate: CLLocationCoordinate2D
	/// Bounding box of the imported coverage geometry, when derivable from the GeoJSON.
	let boundingBox: CoverageBounds?

	static func == (lhs: CoverageEstimateResult, rhs: CoverageEstimateResult) -> Bool {
		lhs.token == rhs.token
	}
}

@MainActor
final class CoverageEstimateRunner: NSObject, ObservableObject {

	/// The message-handler name the injected shim forwards coverage GeoJSON to.
	private static let bridgeName = "coverageBridge"
	/// Matches the Android reference timeout for a headless run.
	private static let timeout: TimeInterval = 45

	/// JS injected at `.atDocumentStart` so `__meshtasticNative` exists before the
	/// planner's success handler (`postCoverageToBridge`) runs. It defines the
	/// object-shaped contract the planner checks for and forwards to the WKWebView
	/// message handler.
	private static let shimJS = """
	window.__meshtasticNative = {
	  onCoverage: function (geojson) {
	    window.webkit.messageHandlers.\(bridgeName).postMessage(geojson);
	  }
	};
	"""

	@Published private(set) var state: CoverageEstimateState = .idle

	/// The most recent successful import (overlay metadata + transmitter coordinate).
	/// Observe via `onChange` to recenter the map and enable the overlay.
	@Published private(set) var importedResult: CoverageEstimateResult?

	private var webView: WKWebView?
	private var timeoutTask: Task<Void, Never>?
	private var params: SitePlannerParameters?
	private var didFinish = false

	/// Whether a run is currently in flight.
	var isRunning: Bool { state == .running }

	/// Kick off a headless coverage run for `params`. Requires a valid coordinate.
	func start(params: SitePlannerParameters) {
		cancel() // tear down any prior run first
		guard params.isValid, let url = params.queryURL(autorun: true, bridge: true) else {
			state = .failed(String(localized: "Invalid coverage parameters."))
			return
		}
		guard let hostWindow = Self.keyWindow() else {
			state = .failed(String(localized: "Could not start the coverage estimate."))
			return
		}

		self.params = params
		self.didFinish = false
		state = .running

		let config = WKWebViewConfiguration()
		let controller = WKUserContentController()
		controller.add(self, name: Self.bridgeName)
		controller.addUserScript(WKUserScript(source: Self.shimJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
		config.userContentController = controller

		// The WebView must be attached to a window and non-zero size, or WebGL/WASM
		// never gets a GL context and the planner's autorun stalls on map-load. Keep
		// it full-size but invisible and non-interactive behind the progress UI.
		let webView = WKWebView(frame: hostWindow.bounds, configuration: config)
		webView.navigationDelegate = self
		webView.isUserInteractionEnabled = false
		webView.alpha = 0
		webView.isHidden = false
		hostWindow.addSubview(webView)
		self.webView = webView

		Logger.services.info("🗺️ [SitePlanner] Starting headless coverage run: \(url.absoluteString, privacy: .public)")
		webView.load(URLRequest(url: url))

		timeoutTask = Task { [weak self] in
			try? await Task.sleep(nanoseconds: UInt64(Self.timeout * 1_000_000_000))
			guard !Task.isCancelled else { return }
			await self?.fail(String(localized: "Coverage estimate timed out."))
		}
	}

	/// Cancel any in-flight run and tear down the WebView.
	func cancel() {
		didFinish = true
		timeoutTask?.cancel()
		timeoutTask = nil
		teardownWebView()
		if state == .running { state = .idle }
	}

	/// Reset back to idle (e.g. when the form is dismissed after success/failure).
	func reset() {
		cancel()
		state = .idle
	}

	// MARK: - Private

	private func teardownWebView() {
		if let webView {
			webView.stopLoading()
			webView.navigationDelegate = nil
			webView.configuration.userContentController.removeAllUserScripts()
			webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.bridgeName)
			webView.removeFromSuperview()
		}
		webView = nil
	}

	private func fail(_ message: String) {
		guard !didFinish else { return }
		didFinish = true
		Logger.services.error("🗺️ [SitePlanner] Coverage run failed: \(message, privacy: .public)")
		teardownWebView()
		timeoutTask?.cancel()
		timeoutTask = nil
		state = .failed(message)
	}

	private func handleCoverage(_ geoJSON: String) {
		guard !didFinish, let params else { return }
		didFinish = true
		timeoutTask?.cancel()
		timeoutTask = nil
		teardownWebView()

		let coordinate = CLLocationCoordinate2D(latitude: params.latitude, longitude: params.longitude)
		let layerName = params.name.trimmingCharacters(in: .whitespacesAndNewlines)
		let importName = layerName.isEmpty ? "Coverage" : layerName
		let boundingBox = Self.boundingBox(fromGeoJSON: geoJSON)

		// This method is `@MainActor`, so the Task inherits MainActor isolation — after each
		// `await` we're back on the main actor and can assign published state directly.
		Task { [weak self] in
			do {
				let metadata = try await MapDataManager.shared.importFromString(geoJSON, name: importName)
				guard let self else { return }
				self.importedResult = CoverageEstimateResult(metadata: metadata, coordinate: coordinate, boundingBox: boundingBox)
				self.state = .imported
			} catch {
				self?.state = .failed(error.localizedDescription)
			}
		}
	}

	/// Compute the bounding box of every position in a GeoJSON string. Walks the parsed JSON
	/// generically: any array whose first element is a number is a `[lon, lat, …]` position, and
	/// everything else is a container to recurse into — so it works for Point / LineString / Polygon /
	/// MultiPolygon without a schema. Returns nil when no positions are found.
	static func boundingBox(fromGeoJSON geoJSON: String) -> CoverageBounds? {
		guard let data = geoJSON.data(using: .utf8),
			  let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
		var minLat = Double.infinity, maxLat = -Double.infinity
		var minLon = Double.infinity, maxLon = -Double.infinity
		func walk(_ node: Any) {
			if let array = node as? [Any] {
				if let lon = array.first as? Double, array.count >= 2, let lat = array[1] as? Double {
					minLat = min(minLat, lat); maxLat = max(maxLat, lat)
					minLon = min(minLon, lon); maxLon = max(maxLon, lon)
				} else {
					array.forEach(walk)
				}
			} else if let dict = node as? [String: Any] {
				dict.values.forEach(walk)
			}
		}
		walk(root)
		guard minLat <= maxLat, minLon <= maxLon else { return nil }
		return CoverageBounds(minLatitude: minLat, maxLatitude: maxLat, minLongitude: minLon, maxLongitude: maxLon)
	}

	/// The foreground key window to host the headless WebView.
	private static func keyWindow() -> UIWindow? {
		UIApplication.shared.connectedScenes
			.compactMap { $0 as? UIWindowScene }
			.filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
			.flatMap { $0.windows }
			.first { $0.isKeyWindow } ??
		UIApplication.shared.connectedScenes
			.compactMap { $0 as? UIWindowScene }
			.flatMap { $0.windows }
			.first
	}
}

// MARK: - WKScriptMessageHandler

extension CoverageEstimateRunner: WKScriptMessageHandler {
	nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
		guard message.name == Self.bridgeName, let body = message.body as? String else { return }
		Task { @MainActor [weak self] in
			self?.handleCoverage(body)
		}
	}
}

// MARK: - WKNavigationDelegate

extension CoverageEstimateRunner: WKNavigationDelegate {
	nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
		Task { @MainActor [weak self] in
			self?.fail(error.localizedDescription)
		}
	}

	nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
		Task { @MainActor [weak self] in
			self?.fail(error.localizedDescription)
		}
	}
}
