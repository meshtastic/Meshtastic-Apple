import SwiftUI
import OSLog
import DatadogSessionReplay

struct TextMessageField: View {
	static let maxbytes = 200
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.horizontalSizeClass) var horizontalSizeClass
	@Environment(\.dismiss) var dismiss

	let destination: MessageDestination
	@Binding var replyMessageId: Int64
	@FocusState.Binding var isFocused: Bool

	@State private var typingMessage: String = ""
	@State private var totalBytes = 0
	@State private var sendPositionWithMessage = false

	var body: some View {
		SessionReplayPrivacyView(textAndInputPrivacy: .maskAllInputs) {
			if #available(iOS 18.0, macOS 15.0, *) {
				FormattingComposeArea(
					typingMessage: $typingMessage,
					totalBytes: $totalBytes,
					replyMessageId: $replyMessageId,
					isFocused: $isFocused,
					maxbytes: Self.maxbytes,
					onSend: sendMessage,
					onAlert: { typingMessage += "🔔 Alert Bell Character! \u{7}" },
					onRequestPosition: requestPosition
				)
			} else {
				VStack(spacing: 0) {
					HStack(alignment: .top) {
						if replyMessageId != 0 || isFocused {
							Button {
								withAnimation(.easeInOut(duration: 0.2)) {
									replyMessageId = 0
								}
								isFocused = false
							} label: {
								Image(systemName: "x.circle.fill")
									.font(.largeTitle)
							}
							if replyMessageId != 0 {
								Text("Reply")
									.padding(.top, 10)
							}
						}
						TextField("Message", text: $typingMessage, axis: .vertical)
							.frame(minHeight: 36)
							.padding(.horizontal, 16)
							.padding(.vertical, 12)
							.background(
								RoundedRectangle(cornerRadius: 20)
									.strokeBorder(.tertiary, lineWidth: 1)
									.background(RoundedRectangle(cornerRadius: 20).fill(Color(.systemBackground)))
							)
							.contentShape(RoundedRectangle(cornerRadius: 20))
							.onChange(of: typingMessage) { _, value in
								totalBytes = value.utf8.count
								while totalBytes > Self.maxbytes {
									typingMessage = String(typingMessage.dropLast())
									totalBytes = typingMessage.utf8.count
								}
							}
							.keyboardType(.default)
							.focused($isFocused)
							.multilineTextAlignment(.leading)
							.onSubmit {
#if targetEnvironment(macCatalyst)
								sendMessage()
#endif
							}
							.foregroundColor(.primary)
						if !typingMessage.isEmpty {
							Button(action: sendMessage) {
								Image(systemName: "arrow.up.circle.fill")
									.font(.largeTitle)
									.foregroundColor(.accentColor)
							}
						}
					}
					.padding(15)
					if isFocused {
						if #available(iOS 26.0, macOS 26.0, *) {
							legacyToolbarContent
								.padding(.vertical, 8)
								.padding(.horizontal)
								.background(.ultraThinMaterial, in: Capsule())
							Spacer()
								.frame(height: 10)
						} else {
							Divider()
							legacyToolbarContent
								.padding(.horizontal, 15)
								.padding(.vertical, 10)
								.background(.bar)
						}
					}
				}
			}
		}
	}

	private var legacyToolbarContent: some View {
		HStack {
			Spacer()
			#if targetEnvironment(macCatalyst)
			Button {
				if let nsApp = NSClassFromString("NSApplication")?.value(forKeyPath: "sharedApplication") as? NSObject {
					let selector = NSSelectorFromString("orderFrontCharacterPalette:")
					if nsApp.responds(to: selector) {
						nsApp.perform(selector, with: nil)
					}
				}
			} label: {
				Image(systemName: "face.smiling")
			}
			Spacer()
			#endif
			AlertButton { typingMessage += "🔔 Alert Bell Character! \u{7}" }
			Spacer()
			RequestPositionButton(action: requestPosition)
			Spacer()
			TextMessageSize(maxbytes: Self.maxbytes, totalBytes: totalBytes)
		}
	}

	private func requestPosition() {
		let userLongName = accessoryManager.activeConnection?.device.longName ?? "Unknown"
		sendPositionWithMessage = true
		typingMessage = "📍 " + userLongName + " \(destination.positionShareMessage)."
	}

	private func sendMessage() {
		Task {
			do {
				try await accessoryManager.sendMessage(
					message: typingMessage,
					toUserNum: destination.userNum,
					channel: destination.channelNum,
					isEmoji: false,
					replyID: replyMessageId)

				typingMessage = ""
				isFocused = false
				replyMessageId = 0

				if sendPositionWithMessage {
					try await accessoryManager.sendPosition(
						channel: destination.channelNum,
						destNum: destination.positionDestNum,
						wantResponse: destination.wantPositionResponse
					)
					Logger.mesh.info("Location Sent")
				}
			} catch {
				Logger.mesh.info("Error sending message")
			}
		}
	}
}

// MARK: - FormattingComposeArea

@available(iOS 18.0, macOS 15.0, *)
private struct FormattingComposeArea: View {
	@Binding var typingMessage: String
	@Binding var totalBytes: Int
	@Binding var replyMessageId: Int64
	@FocusState.Binding var isFocused: Bool
	let maxbytes: Int
	let onSend: () -> Void
	let onAlert: () -> Void
	let onRequestPosition: () -> Void

	@State private var textSelection: TextSelection?
	@State private var showToolbar = false

	var body: some View {
		VStack(spacing: 0) {
			MessagePreview(text: typingMessage)
			HStack(alignment: .top) {
				if replyMessageId != 0 || isFocused {
					Button {
						withAnimation(.easeInOut(duration: 0.2)) {
							replyMessageId = 0
						}
						isFocused = false
					} label: {
						Image(systemName: "x.circle.fill")
							.font(.largeTitle)
					}
					if replyMessageId != 0 {
						Text("Reply")
							.padding(.top, 10)
					}
				}
				TextEditor(text: $typingMessage, selection: $textSelection)
					.frame(minHeight: 36, maxHeight: 200)
					.padding(.horizontal, 16)
					.padding(.vertical, 4)
					.scrollContentBackground(.hidden)
					.background(
						RoundedRectangle(cornerRadius: 20)
							.strokeBorder(.tertiary, lineWidth: 1)
							.background(RoundedRectangle(cornerRadius: 20).fill(Color(.systemBackground)))
					)
					.contentShape(RoundedRectangle(cornerRadius: 20))
					.onChange(of: typingMessage) { _, value in
						totalBytes = value.utf8.count
						while totalBytes > maxbytes {
							typingMessage = String(typingMessage.dropLast())
							totalBytes = typingMessage.utf8.count
						}
					}
					.keyboardType(.default)
					.focused($isFocused)
					.multilineTextAlignment(.leading)
					.foregroundColor(.primary)
				if !typingMessage.isEmpty {
					Button(action: onSend) {
						Image(systemName: "arrow.up.circle.fill")
							.font(.largeTitle)
							.foregroundColor(.accentColor)
					}
				}
			}
			.padding(15)
			#if targetEnvironment(macCatalyst)
			.background(
				ReturnKeyHandler {
					if !typingMessage.isEmpty {
						onSend()
					}
				}
			)
			#endif
			if showToolbar {
				if #available(iOS 26.0, macOS 26.0, *) {
					toolbarContent
						.padding(.vertical, 8)
						.padding(.horizontal)
						.background(.ultraThinMaterial, in: Capsule())
					Spacer()
						.frame(height: 10)
				} else {
					Divider()
					toolbarContent
						.padding(.horizontal, 15)
						.padding(.vertical, 6)
						.background(.bar)
				}
			}
		}
		.onChange(of: isFocused) { _, focused in
			if focused {
				showToolbar = true
			} else {
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
					if !isFocused {
						showToolbar = false
					}
				}
			}
		}
	}

	private var toolbarContent: some View {
		HStack {
			ScrollView(.horizontal, showsIndicators: false) {
				HStack {
					if typingMessage.count >= 3 {
						FormattingToolbarButtons(typingMessage: $typingMessage, textSelection: $textSelection)
					}
					#if targetEnvironment(macCatalyst)
					Button {
						if let nsApp = NSClassFromString("NSApplication")?.value(forKeyPath: "sharedApplication") as? NSObject {
							let selector = NSSelectorFromString("orderFrontCharacterPalette:")
							if nsApp.responds(to: selector) {
								nsApp.perform(selector, with: nil)
							}
						}
					} label: {
						Image(systemName: "face.smiling")
					}
					#endif
					AlertButton(action: onAlert, compact: true)
					RequestPositionButton(action: onRequestPosition, compact: true)
				}
			}
			Spacer()
			TextMessageSize(maxbytes: maxbytes, totalBytes: totalBytes, compact: true)
		}
	}
}

private extension MessageDestination {
	var positionShareMessage: String {
		switch self {
		case .user: return "has shared their position and requested a response with your position"
		case .channel: return "has shared their position with you"
		}
	}

	var positionDestNum: Int64 {
		switch self {
		case let .user(user): return user.num
		case .channel: return Int64(Constants.maximumNodeNum)
		}
	}

	var wantPositionResponse: Bool {
		switch self {
		case .user: return true
		case .channel: return false
		}
	}
}

// MARK: - ReturnKeyHandler (Mac Catalyst)

#if targetEnvironment(macCatalyst)
/// Finds the UITextView backing a SwiftUI TextEditor and intercepts Return
/// via a delegate proxy, calling `action` instead of inserting a newline.
/// Shift+Return still inserts a newline.
private struct ReturnKeyHandler: UIViewRepresentable {
	let action: () -> Void

	func makeCoordinator() -> Coordinator {
		Coordinator(action: action)
	}

	func makeUIView(context: Context) -> UIView {
		let view = UIView(frame: .zero)
		view.isHidden = true
		view.isUserInteractionEnabled = false
		context.coordinator.hostView = view
		return view
	}

	func updateUIView(_ uiView: UIView, context: Context) {
		context.coordinator.action = action
		// Defer to next run loop so the TextEditor's UITextView is in the hierarchy
		DispatchQueue.main.async {
			context.coordinator.installDelegateProxy()
		}
	}

	class Coordinator: NSObject, UITextViewDelegate {
		var action: () -> Void
		weak var hostView: UIView?
		weak var originalDelegate: UITextViewDelegate?
		weak var hookedTextView: UITextView?

		init(action: @escaping () -> Void) {
			self.action = action
		}

		func installDelegateProxy() {
			guard let hostView, hookedTextView == nil else { return }
			guard let textView = findTextView(in: hostView.superview) else { return }
			originalDelegate = textView.delegate
			textView.delegate = self
			hookedTextView = textView
		}

		private func findTextView(in view: UIView?) -> UITextView? {
			guard let view else { return nil }
			// Walk siblings and parent hierarchy to find the UITextView
			if let parent = view.superview {
				for sibling in parent.subviews {
					if let found = findTextViewRecursive(in: sibling) {
						return found
					}
				}
				// Go up one more level
				if let grandparent = parent.superview {
					for child in grandparent.subviews {
						if let found = findTextViewRecursive(in: child) {
							return found
						}
					}
				}
			}
			return nil
		}

		private func findTextViewRecursive(in view: UIView) -> UITextView? {
			if let textView = view as? UITextView {
				return textView
			}
			for subview in view.subviews {
				if let found = findTextViewRecursive(in: subview) {
					return found
				}
			}
			return nil
		}

		// MARK: UITextViewDelegate — intercept Return

		func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
			if text == "\n" {
				action()
				return false
			}
			return originalDelegate?.textView?(textView, shouldChangeTextIn: range, replacementText: text) ?? true
		}

		// MARK: Forward all other delegate methods

		func textViewDidChange(_ textView: UITextView) {
			originalDelegate?.textViewDidChange?(textView)
		}

		func textViewDidBeginEditing(_ textView: UITextView) {
			originalDelegate?.textViewDidBeginEditing?(textView)
		}

		func textViewDidEndEditing(_ textView: UITextView) {
			originalDelegate?.textViewDidEndEditing?(textView)
		}

		func textViewDidChangeSelection(_ textView: UITextView) {
			originalDelegate?.textViewDidChangeSelection?(textView)
		}
	}
}
#endif
