import MeshtasticProtobufs
import OSLog
import SwiftUI

struct MessageText: View {
	let message: MessageEntity
	let originalMessage: String?
	let tapBackDestination: MessageDestination
	let isCurrentUser: Bool
	let onReply: () -> Void

	private let linkColor = Color(red: 0.4627, green: 0.8392, blue: 1) /* #76d6ff */

	@Environment(\.managedObjectContext)
	private var context
	@Environment(\.colorScheme)
	private var colorScheme: ColorScheme
	@State
	private var isShowingDeleteConfirmation = false

	private var foregroundColor: Color {
		if backgroundColor.isLight() {
			return Color.black
		}
		else {
			return Color.white
		}
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

	var body: some View {
		ZStack(alignment: .topLeading) {
			let markdownText = LocalizedStringKey(
				message.messagePayloadMarkdown ?? (message.messagePayload ?? "EMPTY MESSAGE")
			)

			ZStack {
				Text(markdownText)
					.font(.body)
					.foregroundColor(foregroundColor)
					.tint(linkColor)
					.padding(.all, 16)
					.background(backgroundColor)
					.cornerRadius(8)
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
					.contextMenu {
						MessageContextMenuItems(
							message: message,
							tapBackDestination: tapBackDestination,
							isCurrentUser: isCurrentUser,
							onReply: onReply,
							isShowingDeleteConfirmation: $isShowingDeleteConfirmation
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
			.padding(.top, originalMessage == nil ? 0 : 16)

			if let originalMessage {
				HStack(spacing: 0) {
					Spacer()
						.frame(width: 10)

					HStack() {
						Image(systemName: "arrowshape.turn.up.left")
							.font(.body)
							.symbolRenderingMode(.monochrome)
							.foregroundColor(foregroundColor.opacity(0.8))

						Text(originalMessage)
							.font(.footnote)
							.foregroundColor(foregroundColor).opacity(0.8)
					}
					.padding(.vertical, 4)
					.padding(.horizontal, 8)
					.background(colorScheme == .dark ? .black : .white)
					.overlay(
						RoundedRectangle(cornerRadius: 8)
							.stroke(backgroundColor, lineWidth: 1)
					)
					.clipShape(
						RoundedRectangle(cornerRadius: 8)
					)
				}
			}
		}
		.frame(width: .infinity)
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
