// Meshtastic/Views/Settings/HelpAndDocumentation/DocPageView.swift

import SwiftUI
import WebKit
import OSLog

// MARK: - WKWebView representable

private struct DocWebView: UIViewRepresentable {

	let htmlURL: URL

	func makeUIView(context: Context) -> WKWebView {
		let config = WKWebViewConfiguration()
		let webView = WKWebView(frame: .zero, configuration: config)
		webView.isOpaque = false
		webView.backgroundColor = .clear
		webView.scrollView.backgroundColor = .clear
		webView.accessibilityLabel = "Documentation page"
		return webView
	}

	func updateUIView(_ webView: WKWebView, context: Context) {
		do {
			let html = try String(contentsOf: htmlURL, encoding: .utf8)
			// Load with a base URL set to the docs assets directory so relative CSS links resolve
			let baseURL = htmlURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("assets")
			webView.loadHTMLString(html, baseURL: baseURL)
			Logger.docs.debug("DocWebView loaded \(htmlURL.lastPathComponent)")
		} catch {
			let errorHTML = "<html><body><p>Could not load page.</p><p>\(error.localizedDescription)</p></body></html>"
			webView.loadHTMLString(errorHTML, baseURL: nil)
			Logger.docs.error("DocWebView failed to load \(htmlURL.lastPathComponent): \(error.localizedDescription)")
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
