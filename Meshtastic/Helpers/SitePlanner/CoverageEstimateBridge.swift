//
//  CoverageEstimateBridge.swift
//  Meshtastic
//
//  Drives the Meshtastic Site Planner in a hidden WKWebView to compute a coverage
//  estimate without a browser or share sheet — see
//  specs/015-site-planner-outbound/contracts/native-bridge-contract.md.
//
//  The planner calls `window.__meshtasticNative.onCoverage(jsonString)` unconditionally
//  on every successful simulation (feature-detected, not gated by a query flag). Since
//  WKScriptMessageHandler is only reachable via `window.webkit.messageHandlers.<name>
//  .postMessage(...)`, a WKUserScript shim is injected before the planner's own JS runs
//  to bridge the two. The planner never acknowledges receipt and never calls back on
//  failure — a timeout is the only signal for "it never responded" (contracts doc's
//  "Timeout Policy" note).
//
//  The WKWebView is attached (alpha 0, 1x1) to the key window rather than left fully
//  detached: an unattached, view-hierarchy-less WKWebView has known inconsistent JS/
//  message-delivery behavior on some WebKit hosting configurations (research.md §5's
//  Mac Catalyst risk) — attaching it, even invisibly, is the safer default this
//  implementation commits to rather than the version T012 is meant to falsify.
//

import Foundation
import WebKit
import OSLog

#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class CoverageEstimateBridge: NSObject {

	enum BridgeError: LocalizedError {
		case timeout
		case navigationFailed(Error)
		case invalidResponse
		case noWindowToAttachTo

		var errorDescription: String? {
			switch self {
			case .timeout:
				return "The coverage estimate did not respond in time.".localized
			case .navigationFailed(let error):
				return String(format: "Could not reach the Site Planner: %@".localized, error.localizedDescription)
			case .invalidResponse:
				return "The Site Planner returned an unreadable result.".localized
			case .noWindowToAttachTo:
				return "Could not start the coverage estimate.".localized
			}
		}
	}

	private static let messageHandlerName = "meshtasticCoverageBridge"

	/// Defines `window.__meshtasticNative.onCoverage`, the exact shape
	/// `postCoverageToBridge` feature-detects and calls (native-bridge-contract.md).
	/// Injected at `.atDocumentStart`, before the planner's own script runs.
	private static let shimScript = """
	window.__meshtasticNative = {
		onCoverage: function(geojson) {
			window.webkit.messageHandlers.\(messageHandlerName).postMessage(geojson);
		}
	};
	"""

	private var webView: WKWebView?
	private var continuation: CheckedContinuation<Data, Error>?
	private var timeoutTask: Task<Void, Never>?

	/// Loads the Site Planner at the flat query URL for `params` and awaits the styled
	/// coverage `FeatureCollection` (as raw JSON `Data`) via the native bridge, or throws
	/// on timeout / navigation failure / an unreadable response. Only one run may be
	/// in-flight per instance — a new call cancels any still-pending one rather than
	/// leaking it, though the caller (`CoverageEstimateCoordinator`) is expected to
	/// enforce the app-wide one-at-a-time rule (FR-007) before ever reaching this far.
	func run(_ params: CoverageEstimateParameters, timeout: Duration = .seconds(90)) async throws -> Data {
		finish(.failure(CancellationError())) // clears any stale prior run defensively

		guard let window = Self.keyWindow else {
			throw BridgeError.noWindowToAttachTo
		}

		let configuration = WKWebViewConfiguration()
		let userScript = WKUserScript(source: Self.shimScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
		configuration.userContentController.addUserScript(userScript)
		configuration.userContentController.add(self, name: Self.messageHandlerName)

		let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: configuration)
		webView.navigationDelegate = self
		webView.alpha = 0
		webView.isUserInteractionEnabled = false
		self.webView = webView
		window.addSubview(webView)

		let url = CoverageQueryURLBuilder.url(for: params)
		Logger.services.info("🛰️ [SitePlanner] Starting coverage estimate")

		return try await withCheckedThrowingContinuation { continuation in
			self.continuation = continuation
			webView.load(URLRequest(url: url))
			timeoutTask = Task { [weak self] in
				try? await Task.sleep(for: timeout)
				guard !Task.isCancelled else { return }
				self?.finish(.failure(BridgeError.timeout))
			}
		}
	}

	/// Cancels an in-flight run, if any (FR-008).
	func cancel() {
		finish(.failure(CancellationError()))
	}

	private func finish(_ result: Result<Data, Error>) {
		timeoutTask?.cancel()
		timeoutTask = nil
		webView?.configuration.userContentController.removeScriptMessageHandler(forName: Self.messageHandlerName)
		webView?.navigationDelegate = nil
		webView?.removeFromSuperview()
		webView = nil

		guard let continuation else { return }
		self.continuation = nil
		continuation.resume(with: result)
	}

	private static var keyWindow: UIWindow? {
		UIApplication.shared.connectedScenes
			.compactMap { $0 as? UIWindowScene }
			.flatMap { $0.windows }
			.first { $0.isKeyWindow }
	}
}

extension CoverageEstimateBridge: WKScriptMessageHandler {
	func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
		guard message.name == Self.messageHandlerName,
			  let geojsonString = message.body as? String,
			  let data = geojsonString.data(using: .utf8) else {
			finish(.failure(BridgeError.invalidResponse))
			return
		}
		Logger.services.info("🛰️ [SitePlanner] Bridge received a coverage result (\(data.count, privacy: .public) bytes)")
		finish(.success(data))
	}
}

extension CoverageEstimateBridge: WKNavigationDelegate {
	func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
		Logger.services.error("🛰️ [SitePlanner] Navigation failed: \(error.localizedDescription, privacy: .public)")
		finish(.failure(BridgeError.navigationFailed(error)))
	}

	func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
		Logger.services.error("🛰️ [SitePlanner] Provisional navigation failed: \(error.localizedDescription, privacy: .public)")
		finish(.failure(BridgeError.navigationFailed(error)))
	}
}
