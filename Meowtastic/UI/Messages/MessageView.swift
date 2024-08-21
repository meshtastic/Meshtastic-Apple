import MeshtasticProtobufs
import OSLog
import SwiftUI

struct MessageView: View {
	let message: MessageEntity
	let originalMessage: MessageEntity?
	let tapBackDestination: MessageDestination
	let isCurrentUser: Bool
	let onReply: () -> Void

	private let linkColor = Color(red: 0.4627, green: 0.8392, blue: 1) /* #76d6ff */
	private let statusFontSize: CGFloat = 12
	private let dateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .medium
		formatter.timeStyle = .short

		return formatter
	}()

	@Environment(\.managedObjectContext)
	private var context
	@Environment(\.colorScheme)
	private var colorScheme: ColorScheme
	@State
	private var isShowingDeleteConfirmation = false

	private var isDetectionSensorMessage: Bool {
		message.portNum == Int32(PortNum.detectionSensorApp.rawValue)
	}

	private var corners: RectangleCornerRadii {
		if isCurrentUser {
			RectangleCornerRadii(
				topLeading: 24,
				bottomLeading: 24,
				bottomTrailing: 4,
				topTrailing: 24
			)
		}
		else {
			RectangleCornerRadii(
				topLeading: 8,
				bottomLeading: 24,
				bottomTrailing: 4,
				topTrailing: 24
			)
		}
	}

	var body: some View {
		ZStack(alignment: .topLeading) {
			let markdownText = LocalizedStringKey(
				message.messagePayloadMarkdown ?? (message.messagePayload ?? "EMPTY MESSAGE")
			)

			VStack(alignment: isCurrentUser ? .trailing : .leading) {
				if
					let originalMessage,
					let payload = originalMessage.messagePayload
				{
					HStack(spacing: 0) {
						Spacer()
							.frame(width: 12)

						HStack {
							Image(systemName: "arrowshape.turn.up.left")
								.font(.system(size: 14))
								.symbolRenderingMode(.monochrome)
								.foregroundColor(
									getForegroundColor(
										for: originalMessage,
										isCurrentUser: isCurrentUser
									)
									.opacity(0.8))

							Text(payload)
								.font(.system(size: 14))
								.foregroundColor(
									getForegroundColor(
										for: originalMessage,
										isCurrentUser: isCurrentUser
									)
								)
								.opacity(0.8)
						}
						.padding(.vertical, 4)
						.padding(.horizontal, 8)
						.background(getBackgroundColor(for: originalMessage, isCurrentUser: isCurrentUser))
						.overlay(
							RoundedRectangle(cornerRadius: 8)
								.stroke(
									colorScheme == .dark ? .black : .white,
									lineWidth: 3
								)
						)
						.clipShape(
							RoundedRectangle(cornerRadius: 8)
						)

						Spacer()
							.frame(width: 12)
					}
					.zIndex(1)
				}

				VStack(alignment: .leading, spacing: 8) {
					Text(markdownText)
						.font(.body)
						.foregroundColor(
							getForegroundColor(
								for: message,
								isCurrentUser: isCurrentUser
							)
						)
						.tint(linkColor)
						.padding([.leading, .trailing, .top], 16)

					HStack {
						Spacer()

						if isCurrentUser {
							messageStatus
								.padding([.leading, .trailing], 8)
								.padding(.bottom, 4)
						}
						else {
							messageTime
								.padding([.leading, .trailing], 8)
								.padding(.bottom, 4)
						}
					}
				}
				.background(getBackgroundColor(for: message, isCurrentUser: isCurrentUser))
				.clipShape(
					UnevenRoundedRectangle(cornerRadii: corners, style: .continuous)
				)
				.overlay {
					let isDetectionSensorMessage = message.portNum == Int32(PortNum.detectionSensorApp.rawValue)

					if tapBackDestination.overlaySensorMessage, isDetectionSensorMessage {
						Image(systemName: "sensor.fill")
							.padding()
							.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
							.foregroundStyle(Color.orange)
							.symbolRenderingMode(.multicolor)
							.symbolEffect(
								.variableColor.reversing.cumulative,
								options: .repeat(20).speed(3)
							)
							.offset(x: 20, y: -20)
					}
				}
				.padding(.top, originalMessage == nil ? 0 : -22)
				.contextMenu {
					MessageContextMenuItems(
						isShowingDeleteConfirmation: $isShowingDeleteConfirmation,
						message: message,
						tapBackDestination: tapBackDestination,
						isCurrentUser: isCurrentUser,
						onReply: onReply
					)
				}
				.confirmationDialog(
					"Are you sure you want to delete this message?",
					isPresented: $isShowingDeleteConfirmation,
					titleVisibility: .visible
				) {
					Button("Delete Message", role: .destructive) {
						context.delete(message)
						try? context.save()
					}

					Button("Cancel", role: .cancel) { }
				}
			}
		}
		.id(message.messageId)
	}

	@ViewBuilder
	private var messageTime: some View {
		HStack(spacing: 4) {
			Image(systemName: "clock")
				.font(.system(size: statusFontSize))
				.foregroundColor(getForegroundColor(for: message).opacity(0.5))

			Text(message.timestamp.relative())
				.font(.system(size: statusFontSize))
				.lineLimit(1)
				.foregroundColor(getForegroundColor(for: message).opacity(0.5))
				.fixedSize(horizontal: true, vertical: false)
		}
	}

	@ViewBuilder
	private var messageStatus: some View {
		if message.receivedACK {
			let ackAt = Date(timeIntervalSince1970: TimeInterval(message.ackTimestamp))

			HStack(spacing: 4) {
				Image(systemName: "checkmark.circle.fill")
					.font(.system(size: statusFontSize))
					.foregroundColor(getForegroundColor(for: message).opacity(0.5))

				Text(ackAt.relative())
					.font(.system(size: statusFontSize))
					.lineLimit(1)
					.foregroundColor(getForegroundColor(for: message).opacity(0.5))
			}
		}
		else if message.ackError == 0 {
			HStack(spacing: 4) {
				Image(systemName: "checkmark.circle.badge.questionmark")
					.font(.system(size: statusFontSize))
					.foregroundColor(getForegroundColor(for: message).opacity(0.5))

				Text(message.timestamp.relative())
					.font(.system(size: statusFontSize))
					.lineLimit(1)
					.foregroundColor(getForegroundColor(for: message).opacity(0.5))
			}
		}
		else if message.ackError > 0 {
			Image(systemName: "checkmark.circle.trianglebadge.exclamationmark")
				.font(.system(size: statusFontSize))
				.foregroundColor(getForegroundColor(for: message).opacity(0.5))

			if let ackError = RoutingError(rawValue: Int(message.ackError)) {
				Text(ackError.display)
					.font(.system(size: statusFontSize))
					.lineLimit(1)
					.foregroundColor(getForegroundColor(for: message).opacity(0.5))
			}
			else {
				Text("Unknown ACK error")
					.font(.system(size: statusFontSize))
					.lineLimit(1)
					.foregroundColor(getForegroundColor(for: message).opacity(0.5))
			}
		}
	}

	private func getBackgroundColor(
		for message: MessageEntity,
		isCurrentUser: Bool
	) -> Color {
		if UserDefaults.moreColors {
			if let num = message.fromUser?.num {
				return Color(
					UIColor(hex: UInt32(num))
				)
			}
			else {
				if isCurrentUser {
					return Color.accentColor
				}
				else {
					if colorScheme == .dark {
						return Color(white: 0.1)
					}
					else {
						return Color(white: 0.9)
					}
				}
			}
		}
		else {
			if colorScheme == .dark {
				return Color(white: 0.1)
			}
			else {
				return Color(white: 0.9)
			}
		}
	}

	private func getForegroundColor(
		for message: MessageEntity,
		isCurrentUser: Bool = false
	) -> Color {
		let background = getBackgroundColor(for: message, isCurrentUser: isCurrentUser)

		if UserDefaults.moreColors {
			if background.isLight() {
				return Color.black
			}
			else {
				return Color.white
			}
		}
		else {
			if background.isLight() {
				return Color.black
			}
			else {
				return Color.white
			}
		}
	}
}

private extension MessageDestination {
	var overlaySensorMessage: Bool {
		switch self {
		case .user:
			return false

		case .channel:
			return true
		}
	}
}
