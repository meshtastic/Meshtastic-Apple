import MeshtasticProtobufs
import OSLog
import SwiftUI
import DatadogSessionReplay
import MapKit

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
	@State private var saveChannelLink: SaveChannelLinkData?
	@State private var isShowingDeleteConfirmation = false
	@State private var shouldNavigateToMap = false
	
	@FocusState private var isTapbackInputFocused: Bool
	@State private var tapbackText = ""
	
	var body: some View {
		NavigationStack{
			if let positionExchange = message.positionExchange, let node = message.fromUser?.userNode {
				PositionMessageView(
					location: positionExchange,
					isCurrentUser: isCurrentUser,
					message: message,
					onTap: { shouldNavigateToMap = true }
				)
				.contextMenu {
					MessageContextMenuItems(
						message: message,
						tapBackDestination: tapBackDestination,
						isCurrentUser: isCurrentUser,
						isShowingDeleteConfirmation: $isShowingDeleteConfirmation,
						onReply: onReply
					)
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
				.navigationDestination(isPresented: $shouldNavigateToMap) {
					NodeMapSwiftUI(node: node, showUserLocation: true)
						.onDisappear { shouldNavigateToMap = false }
				}
			} else {
				SessionReplayPrivacyView(textAndInputPrivacy: .maskAll) {
					
					let markdownText = LocalizedStringKey(message.messagePayloadMarkdown ?? (message.messagePayload ?? "EMPTY MESSAGE"))
					return Text(markdownText)
						.tint(Self.linkBlue)
						.padding(.vertical, 10)
						.padding(.horizontal, 8)
						.foregroundColor(.white)
						.background(isCurrentUser ? .accentColor : Color(.gray))
						.cornerRadius(15)
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
						.contextMenu {
							MessageContextMenuItems(
								message: message,
								tapBackDestination: tapBackDestination,
								isCurrentUser: isCurrentUser,
								isShowingDeleteConfirmation: $isShowingDeleteConfirmation,
								onReply: onReply
							)
						}
						.environment(\.openURL, OpenURLAction { url in
							saveChannelLink = nil
							var addChannels = false
							if url.absoluteString.lowercased().contains("meshtastic.org/v/#") {
								// Handle contact URL
								ContactURLHandler.handleContactUrl(url: url, accessoryManager: AccessoryManager.shared)
								return .handled // Prevent default browser opening
							} else if url.absoluteString.lowercased().contains("meshtastic.org/e/") {
								// Handle channel URL
								let components = url.absoluteString.components(separatedBy: "#")
								guard !components.isEmpty, let lastComponent = components.last else {
									Logger.services.error("No valid components found in channel URL: \(url.absoluteString, privacy: .public)")
									return .discarded
								}
								addChannels = Bool(url.query?.contains("add=true") ?? false)
								guard let lastComponent = components.last else {
									Logger.services.error("Channel URL missing fragment component: \(url.absoluteString, privacy: .public)")
									self.saveChannelLink = nil
									return .discarded
								}
								let cs = lastComponent.components(separatedBy: "?").first ?? ""
								self.saveChannelLink = SaveChannelLinkData(data: cs, add: addChannels)
								Logger.services.debug("Add Channel: \(addChannels, privacy: .public)")
								Logger.mesh.debug("Opening Channel Settings URL: \(url.absoluteString, privacy: .public)")
								return .handled // Prevent default browser opening
							}
							return .systemAction // Open other URLs in browser
						})
					// Display sheet for channel settings
						.sheet(item: $saveChannelLink) { link in
							SaveChannelQRCode(
								channelSetLink: link.data,
								addChannels: link.add,
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
		}}
}

// New view component for displaying position messages
struct PositionMessageView: View {
	let location: LocationEntity
	let isCurrentUser: Bool
	let message: MessageEntity
	let onTap: () -> Void
	
	@State private var region: MKCoordinateRegion
	
	init(location: LocationEntity, isCurrentUser: Bool, message: MessageEntity, onTap: @escaping () -> Void) {
		self.location = location
		self.isCurrentUser = isCurrentUser
		self.message = message
		self.onTap = onTap
		
		// Convert location coordinates from Int32 to CLLocationDegrees
		let latitude = Double(location.latitudeI) / 1e7
		let longitude = Double(location.longitudeI) / 1e7
		
		_region = State(initialValue: MKCoordinateRegion(
			center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
			span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
		))
	}
	
	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			// Mini map
			Map(position: .constant(.region(region))) {
				let coordinate = CLLocationCoordinate2D(
					latitude: Double(location.latitudeI) / 1e7,
					longitude: Double(location.longitudeI) / 1e7
				)
				Annotation("", coordinate: coordinate) {
					Image(systemName: "pin.circle.fill")
						.foregroundStyle(Color(UIColor(hex: UInt32(message.fromUser?.num ?? 0))))
				}
			}
			.frame(width: 200, height: 150)
			.cornerRadius(10)
			
			// Location details
			VStack(alignment: .leading, spacing: 2) {
				HStack {
					Image(systemName: "location.fill")
						.font(.system(size: 12))
					Text("Shared Location")
						.font(.system(size: 12, weight: .semibold))
				}
				.foregroundColor(.white.opacity(0.9))
				
				if location.altitude != 0 {
					HStack(spacing: 4) {
						Image(systemName: "arrow.up")
							.font(.system(size: 10))
						let altitudeMeters = Measurement(value: Double(location.altitude), unit: UnitLength.meters)
						let altitudeFeet = altitudeMeters.converted(to: .feet)
						if Locale.current.measurementSystem == .metric {
							Text(altitudeFormatter.string(from: altitudeMeters))
								.font(.system(size: 11))
						} else {
							Text(altitudeFormatter.string(from: altitudeFeet))
								.font(.system(size: 11))
						}
					}
					.foregroundColor(.white.opacity(0.8))
				}
				
				if location.speed > 0 {
					HStack(spacing: 4) {
						Image(systemName: "speedometer")
							.font(.system(size: 10))
						let speedKmh = Measurement(value: Double(location.speed), unit: UnitSpeed.kilometersPerHour)
						Text(speedKmh.formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0)))))
							.font(.system(size: 11))
					}
					.foregroundColor(.white.opacity(0.8))
				}
			}
			.padding(.horizontal, 8)
			.padding(.bottom, 6)
		}
		.background(isCurrentUser ? .accentColor : Color(.gray))
		.cornerRadius(15)
		.contentShape(Rectangle())
		.onTapGesture {
			onTap()
		}
		.overlay {
			/// Show the lock if the message is pki encrypted
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
		}
	}
	
	private var messageContent: some View {
		let markdownText = LocalizedStringKey(message.messagePayloadMarkdown ?? (message.messagePayload ?? "EMPTY MESSAGE"))
		return Text(markdownText)
			.tint(Self.linkBlue)
			.padding(.vertical, 10)
			.padding(.horizontal, 8)
			.foregroundColor(.white)
			.background(isCurrentUser ? .accentColor : Color(.gray))
			.cornerRadius(15)
			.background {
				TextField("", text: $tapbackText)
					.keyboardType(.emoji)
					.scrollDismissesKeyboard(.immediately)
					.focused($isTapbackInputFocused)
					.frame(width: 0, height: 0)
					.opacity(0)
					.onChange(of: tapbackText) {
						processTapback()
					}
			}
			.overlay(messageOverlays)
			.contextMenu {
				MessageContextMenuItems(
					message: message,
					tapBackDestination: tapBackDestination,
					isCurrentUser: isCurrentUser,
					isShowingDeleteConfirmation: $isShowingDeleteConfirmation,
					isShowingTapbackInput: Binding(
						get: { isTapbackInputFocused },
						set: { isTapbackInputFocused = $0 }
					),
					onReply: onReply
				)
			}
	}
	
	@ViewBuilder
	private var messageOverlays: some View {
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
		if message.portNum == Int32(PortNum.storeForwardApp.rawValue) {
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
		if tapBackDestination.overlaySensorMessage && message.portNum == Int32(PortNum.detectionSensorApp.rawValue) {
			Image(systemName: "sensor.fill")
				.padding()
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
				.foregroundStyle(Color.orange)
				.symbolRenderingMode(.multicolor)
				.symbolEffect(.variableColor.reversing.cumulative, options: .repeat(20).speed(3))
				.offset(x: 20, y: -20)
		}
	}
	
	private func handleURL(_ url: URL) -> OpenURLAction.Result {
		saveChannelLink = nil
		var addChannels = false
		if url.absoluteString.lowercased().contains("meshtastic.org/v/#") {
			// Handle contact URL
			ContactURLHandler.handleContactUrl(url: url, accessoryManager: AccessoryManager.shared)
			return .handled // Prevent default browser opening
		} else if url.absoluteString.lowercased().contains("meshtastic.org/e/") {
			// Handle channel URL
			let components = url.absoluteString.components(separatedBy: "#")
			guard !components.isEmpty, let lastComponent = components.last else {
				Logger.services.error("No valid components found in channel URL: \(url.absoluteString, privacy: .public)")
				return .discarded
			}
			addChannels = Bool(url.query?.contains("add=true") ?? false)
			guard let lastComponent = components.last else {
				Logger.services.error("Channel URL missing fragment component: \(url.absoluteString, privacy: .public)")
				self.saveChannelLink = nil
				return .discarded
			}
			let cs = lastComponent.components(separatedBy: "?").first ?? ""
			self.saveChannelLink = SaveChannelLinkData(data: cs, add: addChannels)
			Logger.services.debug("Add Channel: \(addChannels, privacy: .public)")
			Logger.mesh.debug("Opening Channel Settings URL: \(url.absoluteString, privacy: .public)")
			return .handled // Prevent default browser opening
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
	
	private func processTapback() {
		guard !tapbackText.isEmpty else { return }
		let emojiToSend = tapbackText
		
		Task {
			do {
				try await accessoryManager.sendMessage(
					message: emojiToSend,
					toUserNum: tapBackDestination.userNum,
					channel: tapBackDestination.channelNum,
					isEmoji: true,
					replyID: message.messageId
				)
				await MainActor.run {
					switch tapBackDestination {
					case let .channel(channel):
						context.refresh(channel, mergeChanges: true)
					case let .user(user):
						context.refresh(user, mergeChanges: true)
					}
				}
			} catch {
				Logger.services.warning("Failed to send tapback.")
			}
		}
		
		tapbackText = ""
		isTapbackInputFocused = false
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

