import MeshtasticProtobufs
import OSLog
import SwiftUI
import DatadogSessionReplay

struct MessageText: View {
	static let linkBlue = Color(red: 0.4627, green: 0.8392, blue: 1) /* #76d6ff */
	static let localeDateFormat = DateFormatter.dateFormat(
		fromTemplate: "yyMMddjmmssa",
		options: 0,
		locale: Locale.current
	)
	static let localeTimeFormat = DateFormatter.dateFormat(
		fromTemplate: "jmmssa",
		options: 0,
		locale: Locale.current
	)
	static let dateFormatString = (localeDateFormat ?? "MM/dd/YY j:mm:ss:a")
	static let timeFormatString = (localeTimeFormat ?? "j:mm:ss:a")
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	
	let message: MessageEntity
	let tapBackDestination: MessageDestination
	let isCurrentUser: Bool
	let onReply: () -> Void
	// State for handling channel URL sheet
	@State private var saveChannels = false
	@State private var channelSettings: String?
	@State private var addChannels = false
	@State private var isShowingDeleteConfirmation = false
	
	private func handleURL(_ url: URL) {
		channelSettings = nil
		if url.absoluteString.lowercased().contains("meshtastic.org/v/#") {
			// Handle contact URL
			ContactURLHandler.handleContactUrl(url: url, accessoryManager: AccessoryManager.shared)
		} else if url.absoluteString.lowercased().contains("meshtastic.org/e/") {
			// Handle channel URL
			let components = url.absoluteString.components(separatedBy: "#")
			guard !components.isEmpty, let lastComponent = components.last else {
				Logger.services.error("No valid components found in channel URL: \(url.absoluteString, privacy: .public)")
				return
			}
			self.addChannels = Bool(url.query?.contains("add=true") ?? false)
			self.channelSettings = lastComponent.components(separatedBy: "?").first ?? ""
			Logger.services.debug("Add Channel: \(self.addChannels, privacy: .public)")
			self.saveChannels = true
			Logger.mesh.debug("Opening Channel Settings URL: \(url.absoluteString, privacy: .public)")
		} else {
			// Open other URLs in browser
			UIApplication.shared.open(url)
		}
	}
	
	var body: some View {
		
		SessionReplayPrivacyView(textAndInputPrivacy: .maskAll) {
			
			let messageText = message.messagePayload ?? "EMPTY MESSAGE"
			
			// Use a properly sized container for the selectable text
			HStack {
				if isCurrentUser { Spacer(minLength: 50) }
				
				SelectableMessageBubble(
					text: messageText,
					markdown: message.messagePayloadMarkdown,
					isCurrentUser: isCurrentUser,
					onURLTap: { url in
						self.handleURL(url)
					}
				)
				.overlay {
					/// Show the lock if the message is pki encrypted and has a real ack if sent by the current user, or is pki encrypted for incoming messages
					if message.pkiEncrypted && message.realACK || !isCurrentUser && message.pkiEncrypted {
						VStack(alignment: .trailing) {
							Spacer()
							HStack {
								Spacer()
								Image(systemName: "lock.circle.fill")
									.symbolRenderingMode(.palette)
									.foregroundStyle(.white, .green)
									.font(.system(size: 20))
									.offset(x: 8, y: 8)
							}
						}
					}
					let isStoreAndForward = message.portNum == Int32(PortNum.storeForwardApp.rawValue)
					let isDetectionSensorMessage = message.portNum == Int32(PortNum.detectionSensorApp.rawValue)
					if isStoreAndForward {
						VStack(alignment: .trailing) {
							Spacer()
							HStack {
								Spacer()
								Image(systemName: "envelope.circle.fill")
									.symbolRenderingMode(.palette)
									.foregroundStyle(.white, .gray)
									.font(.system(size: 20))
									.offset(x: 8, y: 8)
							}
						}
					}
					if tapBackDestination.overlaySensorMessage {
						VStack {
							isDetectionSensorMessage ? Image(systemName: "sensor.fill")
								.padding()
								.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
								.foregroundStyle(Color.orange)
								.symbolRenderingMode(.multicolor)
								.symbolEffect(.variableColor.reversing.cumulative, options: .repeat(20).speed(3))
								.offset(x: 20, y: -20)
							: nil
						}
					} else {
						EmptyView()
					}
				}
				
				if !isCurrentUser { Spacer(minLength: 50) }
			}
			.contextMenu {
				MessageContextMenuItems(
					message: message,
					tapBackDestination: tapBackDestination,
					isCurrentUser: isCurrentUser,
					isShowingDeleteConfirmation: $isShowingDeleteConfirmation,
					onReply: onReply
				)
			}
			.sheet(isPresented: Binding(
				get: {
					saveChannels && !(channelSettings == nil)
				},
				set: { newValue in
					saveChannels = newValue
					if !newValue {
						channelSettings = nil
					}
				}
			)) {
				SaveChannelQRCode(
					channelSetLink: channelSettings ?? "Empty Channel URL",
					addChannels: addChannels,
					accessoryManager: accessoryManager
				)
				.presentationDetents([.large])
				.presentationDragIndicator(.visible)
			}
			.confirmationDialog(
				"Are you sure you want to delete this message?",
				isPresented: $isShowingDeleteConfirmation,
				titleVisibility: .visible
			) {
				Button("Delete Message", role: .destructive) {
					context.delete(message)
					do {
						try context.save()
					} catch {
						Logger.data.error("Failed to delete message \(message.messageId, privacy: .public): \(error.localizedDescription, privacy: .public)")
					}
				}
				Button("Cancel", role: .cancel) {}
			}
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
