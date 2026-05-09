// Meshtastic/Views/Settings/HelpAndDocumentation/DocPageView.swift

import SwiftUI
import WebKit
import OSLog

// MARK: - WKWebView representable

private struct DocWebView: UIViewRepresentable {

	let htmlURL: URL

	// Root of the bundled docs directory — grants WKWebView read access to all sibling pages and assets.
	private var docsRoot: URL {
		htmlURL.deletingLastPathComponent().deletingLastPathComponent()
	}

	func makeUIView(context: Context) -> WKWebView {
		let config = WKWebViewConfiguration()
		let webView = WKWebView(frame: .zero, configuration: config)
		webView.isOpaque = false
		webView.backgroundColor = .clear
		webView.scrollView.backgroundColor = .clear
		webView.accessibilityLabel = "Documentation page"
		webView.navigationDelegate = context.coordinator
		return webView
	}

	func updateUIView(_ webView: WKWebView, context: Context) {
		// loadFileURL correctly resolves all relative paths (CSS, images, inter-page links)
		// without needing to read the HTML ourselves or set a manual baseURL.
		guard webView.url != htmlURL else { return }
		webView.loadFileURL(htmlURL, allowingReadAccessTo: docsRoot)
		Logger.docs.debug("DocWebView loading \(htmlURL.lastPathComponent)")
	}

	func makeCoordinator() -> Coordinator {
		Coordinator(docsRoot: docsRoot)
	}

	// MARK: Coordinator

	final class Coordinator: NSObject, WKNavigationDelegate {
		let docsRoot: URL

		init(docsRoot: URL) {
			self.docsRoot = docsRoot
		}

		func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
			guard let url = action.request.url else { return .allow }

			// Allow the initial file load and same-page anchor jumps
			if url.isFileURL {
				// Only allow reads within the docs bundle
				if url.path.hasPrefix(docsRoot.path) {
					return .allow
				}
				Logger.docs.warning("Blocked file URL outside docs bundle: \(url.path)")
				return .cancel
			}

			// Open external http/https links in Safari
			if url.scheme == "https" || url.scheme == "http" {
				await UIApplication.shared.open(url)
				return .cancel
			}

			// Handle meshtastic:/// deep links — route through the app's URL handler
			if url.scheme == "meshtastic" {
				await UIApplication.shared.open(url)
				return .cancel
			}

			return .cancel
		}

		func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
			Logger.docs.debug("DocWebView finished loading \(webView.url?.lastPathComponent ?? "unknown")")
		}
	}
}

// MARK: - DocPageView

struct DocPageView: View {

	let page: DocPage

	var body: some View {
		DocWebView(htmlURL: page.htmlURL)
			.ignoresSafeArea(edges: .bottom)
			.navigationTitle(page.title)
			.navigationBarTitleDisplayMode(.inline)
			.accessibilityLabel("\(page.title) documentation page")
			.accessibilityHint("Web view showing the \(page.title) documentation")
	}
}
