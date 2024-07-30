import MeshtasticProtobufs
import OSLog
import SwiftUI

struct MessageView: View {
	let message: MessageEntity
	let originalMessage: String?
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

	private var foregroundColor: Color {
		if backgroundColor.isLight() {
			return Color.black
		}
		else {
			return Color.white
		}
	}

	private var statusForegroundColor: Color {
		foregroundColor.opacity(0.5)
	}

	private var backgroundColor: Color {
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

	private var corners: RectangleCornerRadii {
		if isCurrentUser {
			RectangleCornerRadii(
				topLeading: 8,
				bottomLeading: 8,
				bottomTrailing: 0,
				topTrailing: 8
			)
		}
		else {
			RectangleCornerRadii(
				topLeading: 0,
				bottomLeading: 8,
				bottomTrailing: 8,
				topTrailing: 8
			)
		}
	}
	
	var body: some View {
		ZStack(alignment: .topLeading) {
			let markdownText = LocalizedStringKey(
				message.messagePayloadMarkdown ?? (message.messagePayload ?? "EMPTY MESSAGE")
			)
			
			VStack(alignment: isCurrentUser ? .trailing : .leading) {
				if let originalMessage {
					HStack(spacing: 0) {
						Spacer()
							.frame(width: 12)
						
						HStack() {
							Image(systemName: "arrowshape.turn.up.left")
								.font(.system(size: 14))
								.symbolRenderingMode(.monochrome)
								.foregroundColor(foregroundColor.opacity(0.8))
							
							Text(originalMessage)
								.font(.system(size: 14))
								.foregroundColor(foregroundColor).opacity(0.8)
						}
						.padding(.vertical, 4)
						.padding(.horizontal, 8)
						.background(backgroundColor)
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
						.foregroundColor(foregroundColor)
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
				.background(backgroundColor)
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
		.frame(width: .infinity)
	}

	@ViewBuilder
	private var messageTime: some View {
		HStack(spacing: 4) {
			Image(systemName: "clock")
				.font(.system(size: statusFontSize))
				.foregroundColor(statusForegroundColor)

			Text(message.timestamp.relative())
				.font(.system(size: statusFontSize))
				.lineLimit(1)
				.foregroundColor(statusForegroundColor)
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
					.foregroundColor(statusForegroundColor)

				Text(dateFormatter.string(from: ackAt))
					.font(.system(size: statusFontSize))
					.lineLimit(1)
					.foregroundColor(statusForegroundColor)
			}
		}
		else if message.ackError == 0 {
			HStack(spacing: 4) {
				Image(systemName: "checkmark.circle.badge.questionmark")
					.font(.system(size: statusFontSize))
					.foregroundColor(statusForegroundColor)

				Text(dateFormatter.string(from: message.timestamp))
					.font(.system(size: statusFontSize))
					.lineLimit(1)
					.foregroundColor(statusForegroundColor)
			}
		}
		else if message.ackError > 0 {
			Image(systemName: "checkmark.circle.trianglebadge.exclamationmark")
				.font(.system(size: statusFontSize))
				.foregroundColor(statusForegroundColor)

			if let ackError = RoutingError(rawValue: Int(message.ackError)) {
				Text(ackError.display)
					.font(.system(size: statusFontSize))
					.lineLimit(1)
					.foregroundColor(statusForegroundColor)
			}
			else {
				Text("Unknown ACK error")
					.font(.system(size: statusFontSize))
					.lineLimit(1)
					.foregroundColor(statusForegroundColor)
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
