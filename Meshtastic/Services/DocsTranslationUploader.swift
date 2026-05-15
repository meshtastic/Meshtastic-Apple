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

/// Checks the Meshtastic docs site repo for existing translations and opens PRs
/// with machine-translated markdown files for new app version + language combinations.
actor DocsTranslationUploader {

	static let shared = DocsTranslationUploader()

	/// The target repo in "owner/repo" format.
	private let targetRepo = "meshtastic/meshtastic"

	/// Base path in the repo where translations are stored.
	private let translationsBasePath = "docs/i18n"

	/// GitHub API base URL.
	private let apiBase = "https://api.github.com"

	private var inFlightUploads: Set<String> = []

	private init() {}

	// MARK: - Public API

	/// Checks if translations exist for the given version + language, and if not,
	/// uploads translated markdown files and opens a PR.
	/// - Parameters:
	///   - languageCode: The target language code (e.g., "fr", "es", "de").
	///   - appVersion: The app version string (e.g., "2.7.13").
	///   - pages: The doc pages with translated markdown cached locally.
	///   - token: GitHub personal access token with `repo` scope.
	/// - Returns: The PR URL if one was created, nil if translations already exist.
	func uploadIfNeeded(
		languageCode: String,
		appVersion: String,
		pages: [DocPage],
		token: String
	) async throws -> String? {
		let key = "\(appVersion)/\(languageCode)"
		guard !inFlightUploads.contains(key) else {
			Logger.docs.info("DocsTranslationUploader: Upload already in flight for \(key, privacy: .public)")
			return nil
		}
		inFlightUploads.insert(key)
		defer { inFlightUploads.remove(key) }

		// 1. Check if the translation directory already exists
		let dirPath = "\(translationsBasePath)/\(languageCode)/\(appVersion)"
		let exists = try await directoryExists(path: dirPath, token: token)
		if exists {
			Logger.docs.info("DocsTranslationUploader: Translations already exist at \(dirPath, privacy: .public)")
			return nil
		}

		// 2. Check if there's already an open PR for this version + language
		let branchName = "translations/\(languageCode)/\(appVersion)"
		let prExists = try await openPRExists(branch: branchName, token: token)
		if prExists {
			Logger.docs.info("DocsTranslationUploader: PR already exists for \(branchName, privacy: .public)")
			return nil
		}

		// 3. Get the default branch SHA
		let defaultBranchSHA = try await getDefaultBranchSHA(token: token)

		// 4. Create the branch
		try await createBranch(name: branchName, sha: defaultBranchSHA, token: token)
		Logger.docs.info("DocsTranslationUploader: Created branch \(branchName, privacy: .public)")

		// 5. Commit translated files
		for page in pages {
			guard let translatedMd = await getTranslatedMarkdown(for: page, languageCode: languageCode) else {
				continue
			}
			let filePath = "\(dirPath)/\(page.section.rawValue)/\(page.id).md"
			try await createOrUpdateFile(
				path: filePath,
				content: translatedMd,
				message: "Add \(languageCode) translation for \(page.id)",
				branch: branchName,
				token: token
			)
		}

		// 6. Open PR
		let prURL = try await createPR(
			title: "[\(languageCode.uppercased())] Add \(Locale.current.localizedString(forLanguageCode: languageCode) ?? languageCode) translations for v\(appVersion)",
			body: """
			Auto-generated machine translations for app version \(appVersion).

			**Language**: \(Locale.current.localizedString(forLanguageCode: languageCode) ?? languageCode) (\(languageCode))
			**Source**: On-device Apple Translation framework
			**Pages**: \(pages.count)

			> ⚠️ These translations were generated automatically and may need review by native speakers.
			""",
			head: branchName,
			base: "master",
			token: token
		)

		Logger.docs.info("DocsTranslationUploader: Created PR for \(languageCode, privacy: .public) v\(appVersion, privacy: .public): \(prURL, privacy: .public)")
		return prURL
	}

	// MARK: - Cache Access

	private func getTranslatedMarkdown(for page: DocPage, languageCode: String) async -> String? {
		guard let sourceHash = TranslationCache.sha256Hash(ofFileAt: page.markdownURL ?? page.htmlURL) else {
			return nil
		}
		let sourceFile = "\(page.section.rawValue)/\(page.id).md"
		guard let cachedURL = await TranslationCache.shared.retrieve(
			sourceFile: sourceFile,
			languageCode: languageCode,
			currentHash: sourceHash
		) else {
			return nil
		}
		return try? String(contentsOf: cachedURL, encoding: .utf8)
	}

	// MARK: - GitHub API Helpers

	private func directoryExists(path: String, token: String) async throws -> Bool {
		let url = URL(string: "\(apiBase)/repos/\(targetRepo)/contents/\(path)")!
		var request = URLRequest(url: url)
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

		let (_, response) = try await URLSession.shared.data(for: request)
		let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
		return statusCode == 200
	}

	private func openPRExists(branch: String, token: String) async throws -> Bool {
		let url = URL(string: "\(apiBase)/repos/\(targetRepo)/pulls?head=\(targetRepo.split(separator: "/").first ?? "meshtastic"):\(branch)&state=open")!
		var request = URLRequest(url: url)
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

		let (data, _) = try await URLSession.shared.data(for: request)
		let prs = try JSONDecoder().decode([GitHubPR].self, from: data)
		return !prs.isEmpty
	}

	private func getDefaultBranchSHA(token: String) async throws -> String {
		let url = URL(string: "\(apiBase)/repos/\(targetRepo)")!
		var request = URLRequest(url: url)
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

		let (data, _) = try await URLSession.shared.data(for: request)
		let repo = try JSONDecoder().decode(GitHubRepo.self, from: data)
		let defaultBranch = repo.defaultBranch

		let refURL = URL(string: "\(apiBase)/repos/\(targetRepo)/git/ref/heads/\(defaultBranch)")!
		var refRequest = URLRequest(url: refURL)
		refRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		refRequest.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

		let (refData, _) = try await URLSession.shared.data(for: refRequest)
		let ref = try JSONDecoder().decode(GitHubRef.self, from: refData)
		return ref.object.sha
	}

	private func createBranch(name: String, sha: String, token: String) async throws {
		let url = URL(string: "\(apiBase)/repos/\(targetRepo)/git/refs")!
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
		request.httpBody = try JSONEncoder().encode([
			"ref": "refs/heads/\(name)",
			"sha": sha
		])

		let (_, response) = try await URLSession.shared.data(for: request)
		let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
		guard statusCode == 201 || statusCode == 422 else {
			throw UploadError.branchCreationFailed(statusCode)
		}
	}

	private func createOrUpdateFile(path: String, content: String, message: String, branch: String, token: String) async throws {
		let url = URL(string: "\(apiBase)/repos/\(targetRepo)/contents/\(path)")!
		var request = URLRequest(url: url)
		request.httpMethod = "PUT"
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

		let base64Content = Data(content.utf8).base64EncodedString()
		let body: [String: String] = [
			"message": message,
			"content": base64Content,
			"branch": branch
		]
		request.httpBody = try JSONEncoder().encode(body)

		let (_, response) = try await URLSession.shared.data(for: request)
		let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
		guard statusCode == 200 || statusCode == 201 else {
			throw UploadError.fileCommitFailed(path, statusCode)
		}
	}

	private func createPR(title: String, body: String, head: String, base: String, token: String) async throws -> String {
		let url = URL(string: "\(apiBase)/repos/\(targetRepo)/pulls")!
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

		let prBody: [String: String] = [
			"title": title,
			"body": body,
			"head": head,
			"base": base
		]
		request.httpBody = try JSONEncoder().encode(prBody)

		let (data, response) = try await URLSession.shared.data(for: request)
		let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
		guard statusCode == 201 else {
			throw UploadError.prCreationFailed(statusCode)
		}

		let pr = try JSONDecoder().decode(GitHubPR.self, from: data)
		return pr.htmlURL
	}

	// MARK: - Error Types

	enum UploadError: LocalizedError {
		case branchCreationFailed(Int)
		case fileCommitFailed(String, Int)
		case prCreationFailed(Int)

		var errorDescription: String? {
			switch self {
			case .branchCreationFailed(let code): return "Failed to create branch (HTTP \(code))"
			case .fileCommitFailed(let path, let code): return "Failed to commit file '\(path)' (HTTP \(code))"
			case .prCreationFailed(let code): return "Failed to create PR (HTTP \(code))"
			}
		}
	}

	// MARK: - GitHub API Models

	private struct GitHubRepo: Decodable {
		let defaultBranch: String

		enum CodingKeys: String, CodingKey {
			case defaultBranch = "default_branch"
		}
	}

	private struct GitHubRef: Decodable {
		let object: GitHubRefObject
	}

	private struct GitHubRefObject: Decodable {
		let sha: String
	}
}

// MARK: - GitHubPR (shared)

struct GitHubPR: Decodable {
	let htmlURL: String
	let number: Int
	let state: String

	enum CodingKeys: String, CodingKey {
		case htmlURL = "html_url"
		case number
		case state
	}
}
