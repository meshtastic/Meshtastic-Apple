// MARK: TranslationCache
//
//  TranslationCache.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 2026.
//

import Foundation
import CryptoKit
import OSLog

// MARK: - TranslatedDocumentEntry

struct TranslatedDocumentEntry: Codable {
	let sourceFile: String
	let languageCode: String
	let contentHash: String
	var translatedAt: Date
	var lastAccessedAt: Date
	var fileSize: Int
}

// MARK: - TranslationCacheManifest

struct TranslationCacheManifest: Codable {
	var entries: [TranslatedDocumentEntry]
}

// MARK: - TranslationCache

actor TranslationCache {

	static let shared = TranslationCache()

	/// Maximum cache size per language in bytes (50 MB).
	private let maxCacheSizePerLanguage: Int = 50 * 1024 * 1024

	private var manifest: TranslationCacheManifest = TranslationCacheManifest(entries: [])

	private let fileManager = FileManager.default

	private init() {
		Task { await loadManifest() }
	}

	// MARK: - Directory Helpers

	/// Root directory for all translated docs: Application Support/TranslatedDocs/
	private var cacheRoot: URL {
		let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
		return appSupport.appendingPathComponent("TranslatedDocs", isDirectory: true)
	}

	private var manifestURL: URL {
		cacheRoot.appendingPathComponent("manifest.json")
	}

	/// Path for a cached translated file.
	private func fileURL(languageCode: String, contentHash: String, sourceFile: String) -> URL {
		let filename = URL(fileURLWithPath: sourceFile).deletingPathExtension().lastPathComponent
		return cacheRoot
			.appendingPathComponent(languageCode, isDirectory: true)
			.appendingPathComponent(String(contentHash.prefix(12)), isDirectory: true)
			.appendingPathComponent("\(filename).md")
	}

	// MARK: - SHA-256 Hashing

	/// Computes SHA-256 hex digest of the given data.
	static func sha256Hash(of data: Data) -> String {
		let digest = SHA256.hash(data: data)
		return digest.map { String(format: "%02x", $0) }.joined()
	}

	/// Computes SHA-256 hex digest of a file's contents.
	static func sha256Hash(ofFileAt url: URL) -> String? {
		guard let data = try? Data(contentsOf: url) else { return nil }
		return sha256Hash(of: data)
	}

	// MARK: - Manifest I/O

	/// Removes all cached translations and resets the manifest.
	func clearAll() {
		do {
			if fileManager.fileExists(atPath: cacheRoot.path) {
				try fileManager.removeItem(at: cacheRoot)
			}
			manifest = TranslationCacheManifest(entries: [])
			UserDefaults.standard.removeObject(forKey: "DocBrowserTranslatedLabels")
			UserDefaults.standard.removeObject(forKey: "DocBrowserTranslatedLabelsLanguage")
			Logger.docs.info("TranslationCache: Cleared all cached translations")
		} catch {
			Logger.docs.error("TranslationCache: Failed to clear cache: \(error.localizedDescription, privacy: .public)")
		}
	}

	private func loadManifest() {
		guard fileManager.fileExists(atPath: manifestURL.path) else {
			manifest = TranslationCacheManifest(entries: [])
			return
		}
		do {
			let data = try Data(contentsOf: manifestURL)
			let decoder = JSONDecoder()
			decoder.dateDecodingStrategy = .iso8601
			manifest = try decoder.decode(TranslationCacheManifest.self, from: data)
		} catch {
			Logger.docs.error("TranslationCache: Failed to load manifest: \(error.localizedDescription, privacy: .public)")
			manifest = TranslationCacheManifest(entries: [])
		}
	}

	private func saveManifest() {
		do {
			try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
			let encoder = JSONEncoder()
			encoder.dateEncodingStrategy = .iso8601
			encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
			let data = try encoder.encode(manifest)
			try data.write(to: manifestURL, options: .atomic)
		} catch {
			Logger.docs.error("TranslationCache: Failed to save manifest: \(error.localizedDescription, privacy: .public)")
		}
	}

	// MARK: - Rendered HTML Folder

	/// Root directory for rendered HTML files for a language: TranslatedDocs/{lang}/html/
	func renderedHTMLRoot(for languageCode: String) -> URL {
		cacheRoot
			.appendingPathComponent(languageCode, isDirectory: true)
			.appendingPathComponent("html", isDirectory: true)
	}

	/// Writes a fully rendered HTML file for a page into the language folder.
	func storeRenderedHTML(_ html: String, page: DocPage, languageCode: String) {
		let dir = renderedHTMLRoot(for: languageCode)
			.appendingPathComponent(page.section.rawValue, isDirectory: true)
		do {
			try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
			let fileURL = dir.appendingPathComponent("\(page.id).html")
			try Data(html.utf8).write(to: fileURL, options: .atomic)
		} catch {
			Logger.docs.error("TranslationCache: Failed to write rendered HTML for \(page.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
		}
	}

	/// Writes a translated index.json into the language folder.
	func storeRenderedIndex(_ entries: [TranslatedSearchEntry], languageCode: String) {
		let dir = renderedHTMLRoot(for: languageCode)
		do {
			try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
			let data = try JSONEncoder().encode(entries)
			try data.write(to: dir.appendingPathComponent("index.json"), options: .atomic)

			// Copy bundled assets (CSS, screenshots) so rendered HTML can reference ../assets/
			copyBundledAssets(to: dir)

			Logger.docs.info("TranslationCache: Wrote rendered index.json for \(languageCode, privacy: .public)")
		} catch {
			Logger.docs.error("TranslationCache: Failed to write rendered index: \(error.localizedDescription, privacy: .public)")
		}
	}

	/// Copies the bundled docs/assets folder into the rendered HTML root.
	private func copyBundledAssets(to htmlRoot: URL) {
		guard let bundledAssetsURL = Bundle.main.url(forResource: "assets", withExtension: nil, subdirectory: "docs") else {
			Logger.docs.warning("TranslationCache: Bundled docs/assets not found — CSS won't work in translated pages")
			return
		}
		let destAssets = htmlRoot.appendingPathComponent("assets", isDirectory: true)
		if fileManager.fileExists(atPath: destAssets.path) { return } // Already copied
		do {
			try fileManager.copyItem(at: bundledAssetsURL, to: destAssets)
		} catch {
			Logger.docs.error("TranslationCache: Failed to copy assets: \(error.localizedDescription, privacy: .public)")
		}
	}

	/// Returns the URL of the rendered HTML file for a page if it exists on disk.
	func renderedHTMLFileURL(for page: DocPage, languageCode: String) -> URL? {
		let url = renderedHTMLRoot(for: languageCode)
			.appendingPathComponent(page.section.rawValue, isDirectory: true)
			.appendingPathComponent("\(page.id).html")
		return fileManager.fileExists(atPath: url.path) ? url : nil
	}

	/// Returns the URL of the rendered HTML root if it exists and has an index.json.
	func renderedHTMLRootIfReady(for languageCode: String) -> URL? {
		let root = renderedHTMLRoot(for: languageCode)
		let indexURL = root.appendingPathComponent("index.json")
		guard fileManager.fileExists(atPath: indexURL.path) else { return nil }
		return root
	}

	// MARK: - Cache Lookup

	/// Retrieves cached translation if it exists and the content hash matches.
	/// Returns the file URL of the cached .md file, or nil if not found/stale.
	func retrieve(sourceFile: String, languageCode: String, currentHash: String) -> URL? {
		guard let index = manifest.entries.firstIndex(where: {
			$0.sourceFile == sourceFile && $0.languageCode == languageCode
		}) else {
			return nil
		}

		let entry = manifest.entries[index]

		// Invalidate if hash mismatch (source updated)
		if entry.contentHash != currentHash {
			Logger.docs.info("TranslationCache: Hash mismatch for \(sourceFile, privacy: .public) [\(languageCode, privacy: .public)] — invalidating")
			removeEntry(at: index)
			return nil
		}

		let url = fileURL(languageCode: languageCode, contentHash: currentHash, sourceFile: sourceFile)
		guard fileManager.fileExists(atPath: url.path) else {
			Logger.docs.warning("TranslationCache: Manifest entry exists but file missing for \(sourceFile, privacy: .public) [\(languageCode, privacy: .public)]")
			manifest.entries.remove(at: index)
			saveManifest()
			return nil
		}

		// Update last accessed
		manifest.entries[index].lastAccessedAt = Date()
		saveManifest()

		return url
	}

	// MARK: - Cache Store

	/// Stores a translated markdown file in the cache.
	func store(translatedMarkdown: String, sourceFile: String, languageCode: String, contentHash: String) {
		let url = fileURL(languageCode: languageCode, contentHash: contentHash, sourceFile: sourceFile)

		do {
			try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
			let data = Data(translatedMarkdown.utf8)
			try data.write(to: url, options: .atomic)

			let entry = TranslatedDocumentEntry(
				sourceFile: sourceFile,
				languageCode: languageCode,
				contentHash: contentHash,
				translatedAt: Date(),
				lastAccessedAt: Date(),
				fileSize: data.count
			)

			// Remove existing entry for same source+language if any
			manifest.entries.removeAll { $0.sourceFile == sourceFile && $0.languageCode == languageCode }
			manifest.entries.append(entry)

			saveManifest()

			// Enforce LRU eviction
			evictIfNeeded(languageCode: languageCode)

		} catch {
			Logger.docs.error("TranslationCache: Failed to store translation for \(sourceFile, privacy: .public) [\(languageCode, privacy: .public)]: \(error.localizedDescription, privacy: .public)")
		}
	}

	// MARK: - LRU Eviction

	private func evictIfNeeded(languageCode: String) {
		let languageEntries = manifest.entries.filter { $0.languageCode == languageCode }
		let totalSize = languageEntries.reduce(0) { $0 + $1.fileSize }

		guard totalSize > maxCacheSizePerLanguage else { return }

		Logger.docs.info("TranslationCache: Cache for '\(languageCode, privacy: .public)' exceeds 50 MB (\(totalSize, privacy: .public) bytes) — evicting LRU entries")

		// Sort by lastAccessedAt ascending (oldest first)
		let sorted = languageEntries.sorted { $0.lastAccessedAt < $1.lastAccessedAt }
		var currentSize = totalSize

		for entry in sorted {
			guard currentSize > maxCacheSizePerLanguage else { break }
			removeEntryByValue(entry)
			currentSize -= entry.fileSize
		}

		saveManifest()
	}

	// MARK: - Entry Removal

	private func removeEntry(at index: Int) {
		let entry = manifest.entries[index]
		let url = fileURL(languageCode: entry.languageCode, contentHash: entry.contentHash, sourceFile: entry.sourceFile)
		try? fileManager.removeItem(at: url)
		manifest.entries.remove(at: index)
		saveManifest()
	}

	private func removeEntryByValue(_ entry: TranslatedDocumentEntry) {
		let url = fileURL(languageCode: entry.languageCode, contentHash: entry.contentHash, sourceFile: entry.sourceFile)
		try? fileManager.removeItem(at: url)
		manifest.entries.removeAll {
			$0.sourceFile == entry.sourceFile && $0.languageCode == entry.languageCode && $0.contentHash == entry.contentHash
		}
	}
}
