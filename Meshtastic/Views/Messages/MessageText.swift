import MeshtasticProtobufs
import OSLog
import SwiftUI
#if !targetEnvironment(macCatalyst)
import Translation
#endif

struct MessageText: View {
	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager

	let message: MessageEntity
	let tapBackDestination: MessageDestination
	let isCurrentUser: Bool
	let onReply: () -> Void
	let onTapback: () -> Void
	// State for handling channel URL sheet
	@State private var saveChannelLink: SaveChannelLinkData?
	@State private var isShowingDeleteConfirmation = false
	@State private var isShowingTranslationPresentation = false

	var body: some View {
		messageContent
			.environment(\.openURL, OpenURLAction { url in
				handleURL(url)
			})
			.sheet(item: $saveChannelLink) { link in
				SaveChannelQRCode(
					channelSetLink: link.data,
					addChannels: link.add,
					accessoryManager: accessoryManager
				)
				.presentationDetents([.large])
				#if !targetEnvironment(macCatalyst)
				.presentationDragIndicator(.visible)
				#endif
			}
			.confirmationDialog(
				"Are you sure you want to delete this message?",
				isPresented: $isShowingDeleteConfirmation,
				titleVisibility: .visible
			) {
				Button("Delete Message", role: .destructive) {
					deleteMessage()
				}
				Button("Cancel", role: .cancel) {}
			}
	}

	private var sourceMessageText: String {
		message.messagePayload ?? "EMPTY MESSAGE"
	}

	private var hasTranslatedText: Bool { message.hasTranslatedPayload }

	private var isShowingTranslatedText: Bool {
		message.showTranslatedMessage && hasTranslatedText
	}

	private var canTranslate: Bool {
		guard !sourceMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
		#if targetEnvironment(macCatalyst)
		return false
		#else
		if #available(iOS 17.4, macOS 14.4, *) {
			return true
		}
		return false
		#endif
	}

	private var messageContent: some View {
		#if !targetEnvironment(macCatalyst)
		if #available(iOS 17.4, macOS 14.4, *), canTranslate {
			return AnyView(
				baseMessageContent
					.translationPresentation(
						isPresented: $isShowingTranslationPresentation,
						text: sourceMessageText,
						attachmentAnchor: .rect(.bounds),
						arrowEdge: .top,
						replacementAction: { replacement in
							saveTranslatedText(replacement)
						}
					)
			)
		}
		#endif

		return AnyView(baseMessageContent)
	}

	private func underlineLinks(in source: AttributedString) -> AttributedString {
		var result = source
		let linkColor = Color("Colors/MeshtasticLink")
		for run in result.runs where run.link != nil {
			result[run.range].underlineStyle = .single
			result[run.range].foregroundColor = linkColor
		}
		return result
	}

	private var baseMessageContent: some View {
		let payload = message.displayedMarkdownPayload
		return Group {
			if let attributed = try? AttributedString(markdown: payload, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
				Text(underlineLinks(in: attributed))
			} else {
				Text(LocalizedStringKey(payload))
			}
		}
			.tint(Color("Colors/MeshtasticLink"))
			.padding(.vertical, 10)
			.padding(.horizontal, 8)
			.foregroundColor(isCurrentUser ? .white : Color("Colors/MeshtasticBubbleText"))
			.background(isCurrentUser ? .accentColor : Color("Colors/MeshtasticBubble"))
			.cornerRadius(15)
			.overlay(messageOverlays)
			.contextMenu {
				MessageContextMenuItems(
					message: message,
					tapBackDestination: tapBackDestination,
					isCurrentUser: isCurrentUser,
					isShowingDeleteConfirmation: $isShowingDeleteConfirmation,
					onTapback: onTapback,
					onReply: onReply,
					canTranslate: canTranslate,
						hasTranslatedText: hasTranslatedText,
					isShowingTranslatedText: isShowingTranslatedText,
					onTranslate: { isShowingTranslationPresentation = true },
						onToggleTranslatedText: { toggleTranslatedText() },
						onClearTranslation: { clearTranslation() }
				)
			}
	}
	
	/// A bottom-trailing status badge (encryption lock, signing shield, store-forward envelope) with
	/// its symbol, tint, and localized VoiceOver label.
	private struct CornerBadge: Identifiable {
		/// Symbols are distinct within a single message's badge set, so this is a stable identity.
		var id: String { symbol }
		let symbol: String
		let tint: Color
		let label: String
	}

	/// Bottom-trailing status badges (encryption lock, signing shield, store-forward envelope), laid out
	/// in a single row so they sit side by side instead of stacking on the same corner pixel when a
	/// message qualifies for more than one (e.g. a signed store-and-forward broadcast).
	private var cornerBadges: [CornerBadge] {
		var badges: [CornerBadge] = []
		// Lock = private: a PKI-encrypted DM.
		if message.pkiEncrypted && message.realACK || !isCurrentUser && message.pkiEncrypted {
			badges.append(CornerBadge(symbol: "lock.circle.fill", tint: .green,
									  label: String(localized: "Encrypted message", comment: "VoiceOver label for the PKI-encrypted direct message badge")))
		}
		// Shield = authentic: a radio-verified, XEdDSA-signed broadcast. Affirmative only — unsigned
		// traffic shows nothing, and the ingest path only sets the flag on broadcasts, never DMs.
		if message.xeddsaSigned {
			badges.append(CornerBadge(symbol: "checkmark.shield.fill", tint: .green,
									  label: String(localized: "Verified sender", comment: "VoiceOver label for the signed and verified broadcast badge")))
		}
		if message.portNum == Int32(PortNum.storeForwardApp.rawValue) {
			badges.append(CornerBadge(symbol: "envelope.circle.fill", tint: .gray,
									  label: String(localized: "Store and forward message", comment: "VoiceOver label for the store-and-forward badge")))
		}
		return badges
	}

	@ViewBuilder
	private var messageOverlays: some View {
		let badges = cornerBadges
		if !badges.isEmpty {
			VStack(alignment: .trailing) {
				Spacer()
				HStack(spacing: 2) {
					Spacer()
					ForEach(badges) { badge in
						Image(systemName: badge.symbol)
							.symbolRenderingMode(.palette)
							.foregroundStyle(.white, badge.tint)
							.font(.system(size: 20))
							.accessibilityLabel(badge.label)
					}
				}
				.offset(x: 8, y: 8)
			}
		}
		if tapBackDestination.overlaySensorMessage && message.portNum == Int32(PortNum.detectionSensorApp.rawValue) {
			Image(systemName: "sensor.fill")
				.padding()
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
				.foregroundStyle(Color.orange)
				.symbolRenderingMode(.multicolor)
				.symbolEffect(.variableColor.reversing.cumulative, options: .repeat(20).speed(3))
				.offset(x: 20, y: -20)
				.accessibilityLabel(String(localized: "Detection sensor", comment: "VoiceOver label for the detection sensor message badge"))
		}
		if isShowingTranslatedText {
			Image(systemName: "translate")
				.font(.system(size: 20))
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
				.foregroundStyle(Color.blue)
				.symbolRenderingMode(.hierarchical)
				.offset(x: 38, y: 8)
				.accessibilityLabel(String(localized: "Showing translated text", comment: "VoiceOver label for the translated message badge"))
		}
	}

	private func handleURL(_ url: URL) -> OpenURLAction.Result {
		saveChannelLink = nil
		var addChannels = false
		if ContactURLHandler.canHandle(url) {
			// Handle contact URL
			ContactURLHandler.handleContactUrl(url: url, accessoryManager: AccessoryManager.shared)
			return .handled // Prevent default browser opening
		} else if MeshtasticChannelURL.canHandle(url) {
			do {
				let channelLink = try MeshtasticChannelURL.parse(url.absoluteString)
				addChannels = channelLink.addChannels
				self.saveChannelLink = SaveChannelLinkData(data: channelLink.payload, add: addChannels)
				Logger.services.debug("Add Channel: \(addChannels, privacy: .public)")
				Logger.mesh.debug("Opening Channel Settings URL")
				return .handled // Prevent default browser opening
			} catch {
				Logger.services.error("Invalid channel URL: \(error.localizedDescription, privacy: .public)")
				return .discarded
			}
		}
		return .systemAction // Open other URLs in browser
	}

	private func deleteMessage() {
		context.delete(message)
		do {
			try context.save()
		} catch {
			Logger.data.error("Failed to delete message \(message.messageId, privacy: .public): \(error.localizedDescription, privacy: .public)")
		}
	}

	private func saveTranslatedText(_ replacement: String) {
		message.messagePayloadTranslated = replacement
		message.messagePayloadTranslatedMarkdown = generateMessageMarkdown(message: replacement)
		message.showTranslatedMessage = true

		do {
			try context.save()
		} catch {
			Logger.data.error("Failed to save translated message \(message.messageId, privacy: .public): \(error.localizedDescription, privacy: .public)")
		}
	}

	private func toggleTranslatedText() {
		guard hasTranslatedText else { return }
		message.showTranslatedMessage.toggle()

		do {
			try context.save()
		} catch {
			Logger.data.error("Failed to toggle translated message \(message.messageId, privacy: .public): \(error.localizedDescription, privacy: .public)")
		}
	}

	private func clearTranslation() {
		message.messagePayloadTranslated = nil
		message.messagePayloadTranslatedMarkdown = nil
		message.showTranslatedMessage = false

		do {
			try context.save()
		} catch {
			Logger.data.error("Failed to clear translated message \(message.messageId, privacy: .public): \(error.localizedDescription, privacy: .public)")
		}
	}
}

private extension MessageDestination {
	var overlaySensorMessage: Bool {
		switch self {
		case .user: return false
		case .channel: return true
		}
	}
}
