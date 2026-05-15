// Meshtastic/Views/Settings/HelpAndDocumentation/DocPageView.swift

import SwiftUI
import WebKit
import OSLog

// MARK: - WKWebView representable

private struct DocWebView: UIViewRepresentable {

	let htmlURL: URL?
	let htmlString: String?
	let baseURL: URL?

	// Root directory — grants WKWebView read access to all sibling pages and assets.
	private var docsRoot: URL {
		if let htmlURL {
			return htmlURL.deletingLastPathComponent().deletingLastPathComponent()
		}
		if let baseURL {
			return baseURL.deletingLastPathComponent()
		}
		return URL(fileURLWithPath: "/")
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
		if let htmlString {
			let currentContent = webView.url?.absoluteString ?? ""
			if currentContent.contains("translated") { return }
			webView.loadHTMLString(htmlString, baseURL: baseURL)
			Logger.docs.debug("DocWebView loading translated HTML string")
		} else if let htmlURL {
			guard webView.url != htmlURL else { return }
			webView.loadFileURL(htmlURL, allowingReadAccessTo: docsRoot)
			Logger.docs.debug("DocWebView loading \(htmlURL.lastPathComponent)")
		}
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
			if url.isFileURL {
				return url.path.hasPrefix(docsRoot.path) ? .allow : .cancel
			}
			if url.scheme == "about" { return .allow }
			if url.scheme == "https" || url.scheme == "http" {
				await UIApplication.shared.open(url)
				return .cancel
			}
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

	/// Pre-rendered HTML file on disk — CSS resolves via absolute bundle URL embedded in file.
	@State private var renderedFileURL: URL?
	/// Translated HTML string used while rendered file is being written.
	@State private var translatedHTML: String?
	@State private var isTranslating = false
	@State private var translationTask: Task<Void, Never>?
	@State private var translatedTitle: String?

	private var translatedBaseURL: URL {
		page.htmlURL.deletingLastPathComponent()
	}

	var body: some View {
		ZStack {
			if let renderedFileURL {
				DocWebView(htmlURL: renderedFileURL, htmlString: nil, baseURL: nil)
			} else if let translatedHTML {
				DocWebView(htmlURL: nil, htmlString: translatedHTML, baseURL: translatedBaseURL)
			} else {
				DocWebView(htmlURL: page.htmlURL, htmlString: nil, baseURL: nil)
			}

			if isTranslating {
				VStack {
					ProgressView("Translating…")
						.padding(12)
						.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
					Spacer()
				}
				.padding(.top, 40)
			}
		}
		.ignoresSafeArea(edges: .bottom)
		.navigationTitle(translatedTitle ?? page.title)
		.navigationBarTitleDisplayMode(.inline)
		.accessibilityLabel("\(page.title) documentation page")
		.accessibilityHint("Web view showing the \(page.title) documentation")
		.onAppear {
			startTranslation()
		}
		.onDisappear {
			translationTask?.cancel()
			translationTask = nil
		}
		.onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
			translationTask?.cancel()
			renderedFileURL = nil
			translatedHTML = nil
			translatedTitle = nil
			startTranslation()
		}
		.onReceive(NotificationCenter.default.publisher(for: DocTranslationService.languageBecameAvailableNotification)) { _ in
			if translatedTitle == nil {
				let languageCode = Locale.current.language.languageCode?.identifier ?? "en"
				guard languageCode != "en" else { return }
				Task {
					await DocTranslationService.shared.clearUIStringCache()
					let title = await DocTranslationService.shared.translatedUIString(page.title, targetLanguage: languageCode)
					if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title != page.title {
						await MainActor.run { translatedTitle = title }
					}
				}
			}
		}
	}

	// MARK: - Translation Loading

	private func startTranslation() {
		let languageCode = Locale.current.language.languageCode?.identifier ?? "en"
		guard languageCode != "en" else { return }

		translationTask = Task.detached(priority: .userInitiated) {

			// 1. Check for a pre-rendered HTML file on disk (fastest, CSS resolves perfectly)
			if let fileURL = await TranslationCache.shared.renderedHTMLFileURL(for: page, languageCode: languageCode) {
				let title = await DocTranslationService.shared.translatedUIString(page.title, targetLanguage: languageCode)
				await MainActor.run {
					renderedFileURL = fileURL
					if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title != page.title {
						translatedTitle = title
					}
				}
				Task.detached(priority: .utility) {
					await DocTranslationService.shared.prefetchAll(excluding: page.id)
				}
				return
			}

			// 2. Translate the page (community CDN download or on-device)
			await MainActor.run { isTranslating = true }

			async let htmlResult = DocTranslationService.shared.translatedHTMLString(for: page)
			async let titleResult = DocTranslationService.shared.translatedUIString(page.title, targetLanguage: languageCode)

			let html = await htmlResult
			let title = await titleResult

			await MainActor.run {
				isTranslating = false
				if let html { translatedHTML = html }
				if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title != page.title {
					translatedTitle = title
				}
			}

			// 3. Switch to rendered file now that translation has written it
			if html != nil {
				if let fileURL = await TranslationCache.shared.renderedHTMLFileURL(for: page, languageCode: languageCode) {
					await MainActor.run {
						renderedFileURL = fileURL
						translatedHTML = nil
					}
				}
				Task.detached(priority: .utility) {
					await DocTranslationService.shared.prefetchAll(excluding: page.id)
				}
			}
		}
	}
}
