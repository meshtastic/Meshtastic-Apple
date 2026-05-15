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

/// Checks the Meshtastic docs site repo for existing translations (read-only, no auth needed
/// for public repos) and saves translated markdown files locally for upload via GitHub Action.
actor DocsTranslationUploader {

	static let shared = DocsTranslationUploader()

	/// The target repo to check for existing translations.
	private let targetRepo = "meshtastic/meshtastic"

	/// Base path in the repo where translations are stored.
	private let translationsBasePath = "docs/i18n"

	/// GitHub API base URL.
	private let apiBase = "https://api.github.com"

	private var inFlightChecks: Set<String> = []

	private init() {}

	// MARK: - Public API

	/// Checks if translations exist on the docs site for the given version + language.
	func translationsExist(languageCode: String, appVersion: String) async -> Bool {
		let dirPath = "\(translationsBasePath)/\(languageCode)/\(appVersion)"
		do {
			let exists = try await directoryExistsInRepo(path: dirPath)
			if exists {
				Logger.docs.info("DocsTranslationUploader: Translations exist at \(dirPath, privacy: .public)")
			}
			return exists
		} catch {
			Logger.docs.error("DocsTranslationUploader: Error checking repo: \(error.localizedDescription, privacy: .public)")
			return false
		}
	}

	/// Checks if there's already an open PR for this version + language.
	func openPRExists(languageCode: String, appVersion: String) async -> Bool {
		let branchName = "translations/\(languageCode)/\(appVersion)"
		do {
			return try await openPRExistsInRepo(branch: branchName)
		} catch {
			Logger.docs.error("DocsTranslationUploader: Error checking PRs: \(error.localizedDescription, privacy: .public)")
			return false
		}
	}

	/// Saves translated markdown files to the local translations directory.
	/// These files are committed to the repo and picked up by the GitHub Action.
	func saveTranslationsLocally(
		languageCode: String,
		appVersion: String,
		pages: [DocPage]
	) async -> Int? {
		let key = "\(appVersion)/\(languageCode)"
		guard !inFlightChecks.contains(key) else { return nil }
		inFlightChecks.insert(key)
		defer { inFlightChecks.remove(key) }

		// Check if translations already exist upstream
		let exists = await translationsExist(languageCode: languageCode, appVersion: appVersion)
		if exists { return nil }

		let prExists = await openPRExists(languageCode: languageCode, appVersion: appVersion)
		if prExists {
			Logger.docs.info("DocsTranslationUploader: PR already open for \(key, privacy: .public)")
			return nil
		}

		var savedCount = 0
		for page in pages {
			guard let translatedMd = await getTranslatedMarkdown(for: page, languageCode: languageCode) else {
				continue
			}

			let outputDir = translationsDirectory(languageCode: languageCode, appVersion: appVersion, section: page.section.rawValue)
			try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

			let outputFile = outputDir.appendingPathComponent("\(page.id).md")
			do {
				try translatedMd.write(to: outputFile, atomically: true, encoding: .utf8)
				savedCount += 1
			} catch {
				Logger.docs.error("DocsTranslationUploader: Failed to save \(page.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
			}
		}

		Logger.docs.info("DocsTranslationUploader: Saved \(savedCount, privacy: .public) files for \(key, privacy: .public)")
		return savedCount
	}

	/// Local translations directory for a version + language + section.
	func translationsDirectory(languageCode: String, appVersion: String, section: String) -> URL {
		let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
			.appendingPathComponent("translations", isDirectory: true)
		return base
			.appendingPathComponent(languageCode, isDirectory: true)
			.appendingPathComponent(appVersion, isDirectory: true)
			.appendingPathComponent(section, isDirectory: true)
	}

	// MARK: - Cache Access

	private func getTranslatedMarkdown(for page: DocPage, languageCode: String) async -> String? {
		let sourceURL = page.markdownURL ?? page.htmlURL
		guard let sourceHash = TranslationCache.sha256Hash(ofFileAt: sourceURL) else { return nil }
		let sourceFile = "\(page.section.rawValue)/\(page.id).\(page.markdownURL != nil ? "md" : "html")"
		guard let cachedURL = await TranslationCache.shared.retrieve(
			sourceFile: sourceFile,
			languageCode: languageCode,
			currentHash: sourceHash
		) else { return nil }
		return try? String(contentsOf: cachedURL, encoding: .utf8)
	}

	// MARK: - GitHub API (Read-Only, No Auth)

	private func directoryExistsInRepo(path: String) async throws -> Bool {
		let url = URL(string: "\(apiBase)/repos/\(targetRepo)/contents/\(path)")!
		var request = URLRequest(url: url)
		request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
		let (_, response) = try await URLSession.shared.data(for: request)
		return (response as? HTTPURLResponse)?.statusCode == 200
	}

	private func openPRExistsInRepo(branch: String) async throws -> Bool {
		let owner = targetRepo.split(separator: "/").first ?? "meshtastic"
		let encoded = branch.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? branch
		let url = URL(string: "\(apiBase)/repos/\(targetRepo)/pulls?head=\(owner):\(encoded)&state=open")!
		var request = URLRequest(url: url)
		request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
		let (data, _) = try await URLSession.shared.data(for: request)
		let prs = try JSONDecoder().decode([GitHubPRStub].self, from: data)
		return !prs.isEmpty
	}
}

private struct GitHubPRStub: Decodable {
	let number: Int
}
