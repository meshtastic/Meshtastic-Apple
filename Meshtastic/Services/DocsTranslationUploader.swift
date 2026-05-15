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
    }

    // MARK: - Read-Only Checks (No Auth)

    private func checkDocsRepoHasTranslations(languageCode: String, appVersion: String) async -> Bool {
        let path = "\(docsTranslationsPath)/\(languageCode)/\(appVersion)"
        return await directoryExists(repo: docsRepo, path: path)
    }

    private func checkTranslationsRepoHasFiles(languageCode: String, appVersion: String) async -> Bool {
        let path = "apple-apps/\(languageCode)/\(appVersion)"
        return await directoryExists(repo: translationsRepo, path: path)
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
        // Read from Secrets.json (injected by Xcode Cloud ci_pre_xcodebuild.sh)
        guard let url = Bundle.main.url(forResource: "secrets", withExtension: "json", subdirectory: "SupportingFiles"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONDecoder().decode([String: String].self, from: data),
              let token = json["TRANSLATIONS_GITHUB_TOKEN"],
              !token.isEmpty else {
            return nil
        }
        return token
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
