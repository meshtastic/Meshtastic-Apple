// MARK: DocsTranslationUploader
//
//  DocsTranslationUploader.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 2026.
//

import Foundation
import OSLog

// MARK: - DocsTranslationUploader

/// After all pages for a language are translated, automatically commits the translated
/// markdown files to `meshtastic/translations`. A GitHub Action in that repo
/// then picks them up and opens a PR on the docs site.
///
/// Read-only checks against public repos need no auth.
/// Write operations target meshtastic/translations using a fine-grained token from Secrets.json.
actor DocsTranslationUploader {

	static let shared = DocsTranslationUploader()

	/// Docs site repo (read-only checks, no auth needed — public repo).
	private let docsRepo = "meshtastic/meshtastic"

	/// Dedicated translations repo (write — commits translated files here).
	private let translationsRepo = "meshtastic/translations"

	/// Path prefix in the docs site where translations live.
	private let docsTranslationsPath = "docs/i18n"

	private let apiBase = "https://api.github.com"

	/// Tracks individual files already uploaded this session (per-file retry on failure).
	private var uploadedFilesThisSession: Set<String> = []

	private init() {}

	// MARK: - Public API

	/// Called automatically after prefetch completes for a language.
	/// Checks docs site for existing translations, then commits new ones to this repo.
	func uploadIfNeeded(
		languageCode: String,
		pages: [DocPage]
	) async {
		let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
		let key = "\(languageCode)/\(appVersion)"

		// 1. Check if docs site already has these translations (no auth needed)
		let alreadyOnDocsSite = await checkDocsRepoHasTranslations(
			languageCode: languageCode,
			appVersion: appVersion
		)
		if alreadyOnDocsSite { return }

		// 2. Check if translations repo already has them
		let alreadyStaged = await checkTranslationsRepoHasFiles(
			languageCode: languageCode,
			appVersion: appVersion
		)
		if alreadyStaged { return }

		// 3. Get token for writing
		guard let token = loadGitHubToken() else {
			Logger.docs.info("DocsTranslationUploader: No GitHub token configured — skipping auto-upload")
			return
		}

		// 4. Commit translated files (per-file tracking allows retry of failures)
		Logger.docs.info("DocsTranslationUploader: Uploading \(languageCode, privacy: .public) translations for v\(appVersion, privacy: .public)")

		var uploadedCount = 0
		for page in pages {
			let filePath = "apple-apps/\(languageCode)/\(appVersion)/\(page.section.rawValue)/\(page.id).md"

			// Skip files already uploaded this session
			guard !uploadedFilesThisSession.contains(filePath) else { continue }

			guard let translatedMd = await getTranslatedMarkdown(for: page, languageCode: languageCode) else {
				continue
			}

			do {
				try await commitFile(
					repo: translationsRepo,
					path: filePath,
					content: translatedMd,
					message: "Add \(languageCode) translation for \(page.id) (v\(appVersion))",
					token: token
				)
				uploadedFilesThisSession.insert(filePath)
				uploadedCount += 1
			} catch {
				Logger.docs.error("DocsTranslationUploader: Failed to upload \(page.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
			}
		}

		if uploadedCount > 0 {
			Logger.docs.info("DocsTranslationUploader: Committed \(uploadedCount, privacy: .public) files for \(key, privacy: .public)")
		}

		// 5. If every page was uploaded (this session or just now), commit a manifest
		let allPaths = pages.map { "apple-apps/\(languageCode)/\(appVersion)/\($0.section.rawValue)/\($0.id).md" }
		let allUploaded = allPaths.allSatisfy { uploadedFilesThisSession.contains($0) }
		if allUploaded {
			await uploadManifest(
				languageCode: languageCode,
				appVersion: appVersion,
				pages: pages,
				token: token
			)
			await uploadNavLabels(
				languageCode: languageCode,
				appVersion: appVersion,
				pages: pages,
				token: token
			)
			await uploadSearchIndex(
				languageCode: languageCode,
				appVersion: appVersion,
				token: token
			)
		}
	}

	// MARK: - Manifest

	/// Uploads a `manifest.json` indicating the complete set of translated docs for this version.
	private func uploadManifest(
		languageCode: String,
		appVersion: String,
		pages: [DocPage],
		token: String
	) async {
		let filePath = "apple-apps/\(languageCode)/\(appVersion)/manifest.json"
		guard !uploadedFilesThisSession.contains(filePath) else { return }

		let manifest: [String: Any] = [
			"language": languageCode,
			"appVersion": appVersion,
			"complete": true,
			"pageCount": pages.count,
			"pages": pages.map { ["section": $0.section.rawValue, "id": $0.id] },
			"generatedAt": ISO8601DateFormatter().string(from: Date()),
			"platform": "apple"
		]

		guard let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]),
			  let json = String(data: data, encoding: .utf8) else { return }

		do {
			try await commitFile(
				repo: translationsRepo,
				path: filePath,
				content: json,
				message: "Add manifest for \(languageCode) v\(appVersion) (\(pages.count) pages)",
				token: token
			)
			uploadedFilesThisSession.insert(filePath)
			Logger.docs.info("DocsTranslationUploader: Uploaded manifest for \(languageCode, privacy: .public) v\(appVersion, privacy: .public)")
		} catch {
			Logger.docs.error("DocsTranslationUploader: Failed to upload manifest: \(error.localizedDescription, privacy: .public)")
		}
	}

	// MARK: - Nav Labels

	/// Uploads a `nav-labels.json` with translated page titles, section names, and UI chrome.
	private func uploadNavLabels(
		languageCode: String,
		appVersion: String,
		pages: [DocPage],
		token: String
	) async {
		let filePath = "apple-apps/\(languageCode)/\(appVersion)/nav-labels.json"
		guard !uploadedFilesThisSession.contains(filePath) else { return }

		// Ensure section names and UI chrome strings are translated and cached
		let chromeStrings = ["Help & Docs", "Search docs"] + DocSection.allCases.map(\.displayName)
		for source in chromeStrings {
			_ = await DocTranslationService.shared.translatedUIString(source, targetLanguage: languageCode)
		}

		// Collect translated labels from the UI string cache
		let labels = await DocTranslationService.shared.exportUIStringCache(for: languageCode)
		guard !labels.isEmpty else {
			Logger.docs.info("DocsTranslationUploader: No nav labels cached for \(languageCode, privacy: .public) — skipping")
			return
		}

		guard let data = try? JSONSerialization.data(withJSONObject: labels, options: [.prettyPrinted, .sortedKeys]),
			  let json = String(data: data, encoding: .utf8) else { return }

		do {
			try await commitFile(
				repo: translationsRepo,
				path: filePath,
				content: json,
				message: "Add nav labels for \(languageCode) v\(appVersion)",
				token: token
			)
			uploadedFilesThisSession.insert(filePath)
			Logger.docs.info("DocsTranslationUploader: Uploaded nav-labels.json for \(languageCode, privacy: .public)")
		} catch {
			Logger.docs.error("DocsTranslationUploader: Failed to upload nav labels: \(error.localizedDescription, privacy: .public)")
		}
	}

	// MARK: - Read-Only Checks (No Auth)

	// MARK: - Search Index

	/// Uploads a `search-index.json` with translated titles and keywords for localized search.
	private func uploadSearchIndex(
		languageCode: String,
		appVersion: String,
		token: String
	) async {
		let filePath = "apple-apps/\(languageCode)/\(appVersion)/search-index.json"
		guard !uploadedFilesThisSession.contains(filePath) else { return }

		guard let entries = await DocTranslationService.shared.exportSearchIndex(for: languageCode),
			  !entries.isEmpty else {
			Logger.docs.info("DocsTranslationUploader: No search index for \(languageCode, privacy: .public) — skipping")
			return
		}

		guard let data = try? JSONEncoder().encode(entries),
			  let json = String(data: data, encoding: .utf8) else { return }

		do {
			try await commitFile(
				repo: translationsRepo,
				path: filePath,
				content: json,
				message: "Add search index for \(languageCode) v\(appVersion)",
				token: token
			)
			uploadedFilesThisSession.insert(filePath)
			Logger.docs.info("DocsTranslationUploader: Uploaded search-index.json for \(languageCode, privacy: .public)")
		} catch {
			Logger.docs.error("DocsTranslationUploader: Failed to upload search index: \(error.localizedDescription, privacy: .public)")
		}
	}

	// MARK: - Read-Only Checks (No Auth)

	private func checkDocsRepoHasTranslations(languageCode: String, appVersion: String) async -> Bool {
		let path = "\(docsTranslationsPath)/\(languageCode)/\(appVersion)"
		return await directoryExists(repo: docsRepo, path: path)
	}

	private func checkTranslationsRepoHasFiles(languageCode: String, appVersion: String) async -> Bool {
		let path = "apple-apps/\(languageCode)/\(appVersion)/manifest.json"
		return await fileExists(repo: translationsRepo, path: path)
	}

	private func fileExists(repo: String, path: String) async -> Bool {
		guard let url = URL(string: "\(apiBase)/repos/\(repo)/contents/\(path)") else { return false }
		var request = URLRequest(url: url)
		request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
		do {
			let (_, response) = try await URLSession.shared.data(for: request)
			return (response as? HTTPURLResponse)?.statusCode == 200
		} catch {
			return false
		}
	}

	private func directoryExists(repo: String, path: String) async -> Bool {
		guard let url = URL(string: "\(apiBase)/repos/\(repo)/contents/\(path)") else { return false }
		var request = URLRequest(url: url)
		request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
		do {
			let (_, response) = try await URLSession.shared.data(for: request)
			return (response as? HTTPURLResponse)?.statusCode == 200
		} catch {
			return false
		}
	}

	// MARK: - Write Operations (Token Required)

	private func commitFile(repo: String, path: String, content: String, message: String, token: String) async throws {
		guard let url = URL(string: "\(apiBase)/repos/\(repo)/contents/\(path)") else { return }
		var request = URLRequest(url: url)
		request.httpMethod = "PUT"
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

		let base64 = Data(content.utf8).base64EncodedString()
		let body: [String: String] = [
			"message": message,
			"content": base64
		]
		request.httpBody = try JSONEncoder().encode(body)

		let (_, response) = try await URLSession.shared.data(for: request)
		let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
		guard statusCode == 200 || statusCode == 201 else {
			throw UploadError.commitFailed(path, statusCode)
		}
	}

	// MARK: - Cache Access

	private func getTranslatedMarkdown(for page: DocPage, languageCode: String) async -> String? {
		let sourceURL = page.markdownURL ?? page.htmlURL
		guard let sourceHash = TranslationCache.sha256Hash(ofFileAt: sourceURL) else { return nil }
		let ext = page.markdownURL != nil ? "md" : "html"
		let sourceFile = "\(page.section.rawValue)/\(page.id).\(ext)"
		guard let cachedURL = await TranslationCache.shared.retrieve(
			sourceFile: sourceFile,
			languageCode: languageCode,
			currentHash: sourceHash
		) else { return nil }
		return try? String(contentsOf: cachedURL, encoding: .utf8)
	}

	// MARK: - Token

	private func loadGitHubToken() -> String? {
		// 1. Environment variable (for local testing via Xcode scheme)
		if let envToken = ProcessInfo.processInfo.environment["TRANSLATIONS_GITHUB_TOKEN"],
		   !envToken.isEmpty {
			return envToken
		}
		// 2. Secrets.json (injected by Xcode Cloud ci_pre_xcodebuild.sh)
		if let url = Bundle.main.url(forResource: "secrets", withExtension: "json", subdirectory: "SupportingFiles"),
		   let data = try? Data(contentsOf: url),
		   let json = try? JSONDecoder().decode([String: String].self, from: data),
		   let token = json["TRANSLATIONS_GITHUB_TOKEN"],
		   !token.isEmpty {
			return token
		}
		return nil
	}

	// MARK: - Errors

	enum UploadError: LocalizedError {
		case commitFailed(String, Int)

		var errorDescription: String? {
			switch self {
			case .commitFailed(let path, let code):
				return "Failed to commit '\(path)' (HTTP \(code))"
			}
		}
	}
}
