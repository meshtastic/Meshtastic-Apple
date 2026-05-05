// Meshtastic/Views/Settings/HelpAndDocumentation/AIDocAssistantView.swift

import SwiftUI
import OSLog
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - AIDocAssistantView (iOS 26+ only)

@available(iOS 26, *)
struct AIDocAssistantView: View {

	@Environment(\.dismiss) private var dismiss

	@State private var query = ""
	@State private var response: String = ""
	@State private var isLoading = false
	@State private var errorMessage: String?

	private let bundle = DocBundle.shared

	var body: some View {
		NavigationStack {
			Form {
				// ── Chirpy header ──────────────────────────────────────────────
				Section {
					VStack(spacing: 8) {
						Image("AppIcon_Chirpy_Thumb")
							.resizable()
							.scaledToFit()
							.frame(width: 80, height: 80)
							.accessibilityHidden(true)
						Text("Hi, I'm Chirpy!")
							.font(.headline)
						Text("Ask me anything about the Meshtastic app.")
							.font(.subheadline)
							.foregroundStyle(.secondary)
							.multilineTextAlignment(.center)
					}
					.frame(maxWidth: .infinity)
					.padding(.vertical, 8)
					.listRowBackground(Color.clear)
				}

				Section("Your question") {
					TextField("e.g. How do I pair a radio?", text: $query, axis: .vertical)
						.lineLimit(3...6)
						.submitLabel(.send)
						.onSubmit { Task { await sendQuery() } }
						.accessibilityLabel("Question input")
						.accessibilityHint("Type your question about Meshtastic and tap Ask Chirpy")
				}

				Section {
					Button(action: { Task { await sendQuery() } }) {
						HStack {
							Spacer()
							if isLoading {
								ProgressView()
									.progressViewStyle(.circular)
									.padding(.trailing, 4)
								Text("Chirpy is thinking…")
									.foregroundStyle(.secondary)
							} else {
								Label("Ask Chirpy", systemImage: "sparkles")
							}
							Spacer()
						}
					}
					.disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
					.accessibilityLabel(isLoading ? "Chirpy is loading an answer" : "Ask Chirpy your question")
				}

				if let error = errorMessage {
					Section {
						Label(error, systemImage: "exclamationmark.triangle")
							.foregroundStyle(.red)
					}
				}

				if !response.isEmpty {
					Section("Chirpy says") {
						Text(response)
							.textSelection(.enabled)
							.accessibilityLabel("Chirpy's answer")
					}
				}
			}
			.scrollDismissesKeyboard(.interactively)
			.navigationTitle("Ask Chirpy")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Done") { dismiss() }
				}
			}
		}
	}

	// MARK: - Query execution

	@MainActor
	private func sendQuery() async {
		let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return }

		isLoading = true
		errorMessage = nil
		response = ""

		defer { isLoading = false }

		let contextPages = bundle.retrievePages(for: trimmed)
		let context = buildContext(pages: contextPages)

		do {
			response = try await runLanguageModel(question: trimmed, context: context)
			Logger.docs.info("AI assistant answered query using \(contextPages.count) pages")
		} catch {
			errorMessage = "Could not generate an answer. Please try again."
			Logger.docs.error("AI assistant error: \(error.localizedDescription)")
		}
	}

	private func buildContext(pages: [DocPage]) -> String {
		guard !pages.isEmpty else {
			return "No specific documentation context available."
		}
		return pages.compactMap { page -> String? in
			guard let html = try? String(contentsOf: page.htmlURL, encoding: .utf8) else { return nil }
			// Strip HTML tags for plain-text context
			let plain = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
			return "## \(page.title)\n\(plain.trimmingCharacters(in: .whitespacesAndNewlines))"
		}.joined(separator: "\n\n")
	}

	@MainActor
	private func runLanguageModel(question: String, context: String) async throws -> String {
		#if canImport(FoundationModels)
		return try await runWithContext(question: question, context: context, pages: bundle.retrievePages(for: question))
		#else
		return "AI assistance is not available on this device."
		#endif
	}

	#if canImport(FoundationModels)
	@MainActor
	private func runWithContext(question: String, context: String, pages: [DocPage], isRetry: Bool = false) async throws -> String {
		let pageList = pages.map { "- \($0.title)" }.joined(separator: "\n")
		let prompt = """
		You are Chirpy, the friendly AI assistant for the Meshtastic iOS app. You are helpful, concise, and enthusiastic about mesh networking. Answer the user's question based only on the documentation context provided below. If the answer is not in the context, say so briefly and suggest they check the full documentation.

		Pages used:
		\(pageList)

		Documentation context:
		\(context)

		Question: \(question)
		"""
		do {
			let lmSession = LanguageModelSession()
			let result = try await lmSession.respond(to: prompt)
			return result.content
		} catch {
			// Retry with a single top page if this is not already a retry (handles context overflow errors)
			if !isRetry && pages.count > 1 {
				Logger.docs.warning("AI query failed — retrying with top 1 page: \(error.localizedDescription)")
				let topPage = Array(pages.prefix(1))
				let reducedContext = buildContext(pages: topPage)
				return try await runWithContext(question: question, context: reducedContext, pages: topPage, isRetry: true)
			}
			throw error
		}
	}
	#endif
}
