//
//  RemoteShellView.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/8/26.
//

import SwiftUI

/// A terminal on a Linux `meshtasticd` node, over the mesh. Takes the whole window.
struct RemoteShellView: View {
	@StateObject private var session: RemoteShellSession
	@Environment(\.dismiss) private var dismiss

	@AppStorage("remoteShellLineMode") private var lineMode = false
	@AppStorage("remoteShellTextSize") private var textSize = 13.0
	@State private var composer = ""
	@State private var history: [String] = []
	@State private var historyIndex: Int?
	/// Set by the keyboard key to put the on-screen keyboard away in character mode.
	@State private var keyboardHidden = false
	@State private var pinchStartSize: Double?
	@FocusState private var composerFocused: Bool

	static let quickCommands = [
		"uptime",
		"df -h",
		"free -h",
		"ip -br addr",
		"systemctl status meshtasticd --no-pager",
		"journalctl -u meshtasticd -n 30 --no-pager"
	]
	private static let historyLimit = 50
	private static let textSizes = 9.0...22.0

	init(nodeNum: Int64, nodeName: String, accessoryManager: AccessoryManager) {
		_session = StateObject(wrappedValue: RemoteShellSession(nodeNum: nodeNum, nodeName: nodeName, accessoryManager: accessoryManager))
	}

	var body: some View {
		VStack(spacing: 0) {
			header
			Divider()
			TerminalTextView(
				content: content,
				fontSize: textSize,
				takesKeyboard: !lineMode && session.state == .open && !keyboardHidden,
				handlers: handlers
			)
			// Notices sit over the terminal so showing one never changes its size, which
			// would send a resize to the node.
			.overlay(alignment: .top) { notices }
			.overlay { stateMessage }
			if lineMode {
				lineModeBar
			}
			if showsExtraKeys {
				TerminalKeyBar(
					session: session,
					onHistory: lineMode ? recallHistory : nil,
					onCharacter: lineMode ? { composer += $0 } : nil,
					keyboardShown: lineMode ? composerFocused : !keyboardHidden,
					toggleKeyboard: toggleKeyboard
				)
			}
		}
		.background(Color(.systemBackground))
		.onAppear { session.start() }
		.onDisappear { session.close() }
	}

	private var content: TerminalContent {
		let visible = session.echo.visible(atSecretPrompt: session.atSecretPrompt)
		let pending = session.echo.confirmedOnLine && !session.atSecretPrompt && !session.echo.disabledUntilEnter
		return TerminalContent(
			lines: session.screen.lines,
			cursorColumn: session.screen.cursorColumn,
			revision: session.screen.revision,
			sentPrediction: lineMode ? "" : visible.sent,
			unsentPrediction: lineMode || !pending ? "" : visible.unsent,
			showsCursor: session.state == .open && !lineMode
		)
	}

	private var handlers: TerminalInputHandlers {
		TerminalInputHandlers(
			text: { session.type($0) },
			backspace: { session.backspace() },
			key: { session.send($0) },
			chord: { session.sendChord($0, control: $1, alt: $2) },
			paste: { session.paste($0) },
			size: { session.setTerminalSize(cols: $0, rows: $1) },
			tapped: showKeyboard,
			pinch: { scale, ended in
				let start = pinchStartSize ?? textSize
				pinchStartSize = ended ? nil : start
				textSize = min(max((start * scale).rounded(), Self.textSizes.lowerBound), Self.textSizes.upperBound)
			}
		)
	}

	private func toggleKeyboard() {
		if lineMode {
			composerFocused.toggle()
		} else {
			keyboardHidden.toggle()
		}
	}

	/// A tap on the output brings the keyboard back, as in SwiftTermApp.
	private func showKeyboard() {
		if lineMode {
			composerFocused = true
		} else {
			keyboardHidden = false
		}
	}

	private var showsExtraKeys: Bool {
		UIDevice.current.userInterfaceIdiom != .mac
	}

	// MARK: - Header

	private var header: some View {
		HStack(spacing: 12) {
			Button("Done") {
				session.close()
				dismiss()
			}
			VStack(alignment: .leading, spacing: 2) {
				Text(session.nodeName)
					.font(.headline)
					.lineLimit(1)
				Text(statusText)
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
			.accessibilityElement(children: .combine)
			Spacer(minLength: 0)
			if session.state.canReconnect {
				Button("Reconnect") { session.reconnect() }
			}
			menu
		}
		.padding(.horizontal)
		.padding(.vertical, 8)
	}

	private var statusText: String {
		switch session.state {
		case .startingAdmin:
			return String(localized: "Starting remote admin session…")
		case .opening:
			return String(localized: "Opening session…")
		case .open:
			if let roundTrip = session.roundTrip {
				return String(localized: "Open, \(Int(roundTrip * 1000)) ms round trip")
			}
			return String(localized: "Open")
		case .closing:
			return String(localized: "Closing…")
		case let .closed(reason):
			if let reason {
				return String(localized: "Session closed: \(reason)")
			}
			return String(localized: "Session closed")
		case .failed:
			return String(localized: "Session failed")
		}
	}

	private var menu: some View {
		Menu {
			Toggle(isOn: $lineMode) {
				Label("Line Mode", systemImage: "text.line.first.and.arrowtriangle.forward")
			}
			Button {
				if let text = UIPasteboard.general.string { session.paste(text) }
			} label: {
				Label("Paste", systemImage: "doc.on.clipboard")
			}
			.disabled(session.state != .open)
			Button {
				UIPasteboard.general.string = session.screen.lines.map { String($0.map(\.character)) }.joined(separator: "\n")
			} label: {
				Label("Copy All Output", systemImage: "doc.on.doc")
			}
			Button {
				session.clearScreen()
			} label: {
				Label("Clear Screen", systemImage: "clear")
			}
			Button(role: .destructive) {
				session.close()
			} label: {
				Label("End Session", systemImage: "xmark.circle")
			}
			.disabled(session.state != .open && session.state != .opening)
			Divider()
			Button {
				textSize = min(textSize + 1, Self.textSizes.upperBound)
			} label: {
				Label("Larger Text", systemImage: "textformat.size.larger")
			}
			.disabled(textSize >= Self.textSizes.upperBound)
			Button {
				textSize = max(textSize - 1, Self.textSizes.lowerBound)
			} label: {
				Label("Smaller Text", systemImage: "textformat.size.smaller")
			}
			.disabled(textSize <= Self.textSizes.lowerBound)
		} label: {
			Image(systemName: "ellipsis.circle")
				.imageScale(.large)
				.frame(minWidth: 44, minHeight: 44)
		}
		.accessibilityLabel("More options")
	}

	// MARK: - Notices

	private var notices: some View {
		VStack(spacing: 6) {
			if session.screen.fullScreenRequested {
				noticeRow(
					String(localized: "Full-screen programs need more than the mesh can carry, so their output may not display correctly."),
					systemImage: "rectangle.on.rectangle.slash"
				) {
					session.acknowledgeFullScreen()
				}
			}
			if let notice = session.notice {
				noticeRow(notice, systemImage: "exclamationmark.triangle") {
					session.notice = nil
				}
			}
			if let heard = session.waitingLastHeard {
				VStack(alignment: .leading, spacing: 2) {
					Label(String(localized: "Waiting for the node, last heard \(heard) s ago"), systemImage: "hourglass")
						.font(.footnote.weight(.semibold))
					if !lineMode {
						Text("Line mode sends a whole command at once, which is lighter on a busy mesh.")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(10)
				.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
			}
		}
		.padding(.horizontal, 10)
		.padding(.top, 8)
	}

	private func noticeRow(_ text: String, systemImage: String, dismiss: @escaping () -> Void) -> some View {
		HStack(alignment: .top, spacing: 8) {
			Label(text, systemImage: systemImage)
				.font(.footnote)
				.frame(maxWidth: .infinity, alignment: .leading)
			Button(action: dismiss) {
				Image(systemName: "xmark")
					.frame(minWidth: 44, minHeight: 44)
			}
			.accessibilityLabel("Dismiss")
		}
		.padding(.leading, 10)
		.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
	}

	@ViewBuilder
	private var stateMessage: some View {
		switch session.state {
		case .startingAdmin, .opening, .closing:
			VStack(spacing: 10) {
				ProgressView()
				Text(statusText)
					.font(.callout)
			}
			.padding(20)
			.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
		case let .failed(message):
			reconnectCard(message)
		case let .closed(reason):
			reconnectCard(reason.map { String(localized: "Session closed: \($0)") } ?? String(localized: "Session closed"))
		case .open:
			EmptyView()
		}
	}

	private func reconnectCard(_ message: String) -> some View {
		VStack(spacing: 12) {
			Text(message)
				.font(.callout)
				.multilineTextAlignment(.center)
			Button("Reconnect") { session.reconnect() }
				.buttonStyle(.borderedProminent)
		}
		.padding(20)
		.frame(maxWidth: 420)
		.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
		.padding()
	}

	// MARK: - Line mode

	private var lineModeBar: some View {
		VStack(spacing: 8) {
			ScrollView(.horizontal, showsIndicators: false) {
				HStack(spacing: 8) {
					ForEach(chips, id: \.self) { command in
						Button(command) {
							composer = command
							composerFocused = true
						}
						.font(.footnote.monospaced())
						.buttonStyle(.bordered)
						.buttonBorderShape(.roundedRectangle)
					}
				}
				.padding(.horizontal)
			}
			HStack(spacing: 8) {
				Group {
					if session.atSecretPrompt {
						SecureField("Password", text: $composer)
					} else {
						TextField("Command", text: $composer)
					}
				}
				.font(.body.monospaced())
				.textInputAutocapitalization(.never)
				.autocorrectionDisabled()
				.textFieldStyle(.roundedBorder)
				.focused($composerFocused)
				.submitLabel(.send)
				.onSubmit(sendLine)
				.onKeyPress(.upArrow) {
					recallHistory(older: true)
					return .handled
				}
				.onKeyPress(.downArrow) {
					recallHistory(older: false)
					return .handled
				}
				Button("Send", action: sendLine)
					.buttonStyle(.borderedProminent)
					.disabled(session.state != .open)
			}
			.padding(.horizontal)
		}
		.padding(.vertical, 8)
		.onAppear { composerFocused = true }
	}

	private var chips: [String] {
		var seen = Set<String>()
		return (history.prefix(5) + Self.quickCommands).filter { seen.insert($0).inserted }
	}

	private func sendLine() {
		guard session.state == .open else { return }
		let line = composer
		let secret = session.atSecretPrompt
		session.sendLine(line)
		if !secret, !line.trimmingCharacters(in: .whitespaces).isEmpty {
			history.removeAll { $0 == line }
			history.insert(line, at: 0)
			if history.count > Self.historyLimit { history.removeLast() }
		}
		composer = ""
		historyIndex = nil
		composerFocused = true
	}

	private func recallHistory(older: Bool) {
		guard !history.isEmpty else { return }
		if older {
			let next = (historyIndex ?? -1) + 1
			guard next < history.count else { return }
			historyIndex = next
			composer = history[next]
		} else {
			guard let index = historyIndex else { return }
			if index == 0 {
				historyIndex = nil
				composer = ""
			} else {
				historyIndex = index - 1
				composer = history[index - 1]
			}
		}
	}
}

/// The keys a touch keyboard lacks, in one row laid out like SwiftTerm's: Escape and Control on
/// the left, the arrows on the right, and Tab, Alt, symbols, the navigation keys and the
/// keyboard button between them, scrolling sideways when the row is narrow.
struct TerminalKeyBar: View {
	@ObservedObject var session: RemoteShellSession
	/// In line mode the up and down arrows recall history instead of reaching the node.
	var onHistory: ((_ older: Bool) -> Void)?
	/// In line mode the symbol keys go into the command being written rather than straight to the node.
	var onCharacter: ((String) -> Void)?
	let keyboardShown: Bool
	let toggleKeyboard: () -> Void

	private static let symbols: [(text: String, label: LocalizedStringKey)] = [
		("~", "Tilde"), ("|", "Pipe"), ("/", "Slash"), ("-", "Hyphen")
	]

	var body: some View {
		HStack(spacing: 4) {
			Group {
				key("esc", label: "Escape", special: true) { session.send(.escape) }
				modifier("ctrl", label: String(localized: "Control"), state: session.control) { session.control = session.control.next }
			}
			.disabled(session.state != .open)
			ScrollView(.horizontal, showsIndicators: false) {
				HStack(spacing: 4) {
					Group {
						key(systemImage: "arrow.right.to.line.compact", label: "Tab", special: true) { session.send(.tab) }
						modifier("alt", label: String(localized: "Alt"), state: session.alt) { session.alt = session.alt.next }
						ForEach(Self.symbols, id: \.text) { symbol in
							key(symbol.text, label: symbol.label) { character(symbol.text) }
						}
						key("home", label: "Home", special: true) { session.send(.home) }
						key("end", label: "End", special: true) { session.send(.end) }
						key("pgup", label: "Page up", special: true) { session.send(.pageUp) }
						key("pgdn", label: "Page down", special: true) { session.send(.pageDown) }
					}
					.disabled(session.state != .open)
					key(
						systemImage: keyboardShown ? "keyboard.chevron.compact.down" : "keyboard",
						label: keyboardShown ? "Hide Keyboard" : "Show Keyboard",
						special: true,
						action: toggleKeyboard
					)
				}
				.padding(.vertical, 1)
			}
			Group {
				RepeatingKey(systemImage: "arrow.left", label: "Left arrow") { session.send(.left) }
				RepeatingKey(systemImage: "arrow.down", label: "Down arrow") { arrow(.down) }
				RepeatingKey(systemImage: "arrow.up", label: "Up arrow") { arrow(.up) }
				RepeatingKey(systemImage: "arrow.right", label: "Right arrow") { session.send(.right) }
			}
			.disabled(session.state != .open)
		}
		.padding(.horizontal, 4)
		.padding(.vertical, 3)
		.background(Color(.secondarySystemBackground))
	}

	private func character(_ text: String) {
		if let onCharacter {
			onCharacter(text)
		} else {
			session.type(text)
		}
	}

	private func arrow(_ key: TerminalKey) {
		if let onHistory {
			onHistory(key == .up)
		} else {
			session.send(key)
		}
	}

	private func key(_ title: String, label: LocalizedStringKey, special: Bool = false, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Text(verbatim: title)
		}
		.buttonStyle(TerminalKeyStyle(special: special))
		.accessibilityLabel(label)
	}

	private func key(systemImage: String, label: LocalizedStringKey, special: Bool = false, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Image(systemName: systemImage)
		}
		.buttonStyle(TerminalKeyStyle(special: special))
		.accessibilityLabel(label)
	}

	private func modifier(_ title: String, label: String, state: StickyModifier, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Text(verbatim: title)
				.overlay(alignment: .bottom) {
					// State in shape as well as color: one bar for next key, two for locked.
					if state != .off {
						HStack(spacing: 2) {
							ForEach(0..<(state == .locked ? 2 : 1), id: \.self) { _ in
								Rectangle().frame(width: 8, height: 2)
							}
						}
						.offset(y: 7)
					}
				}
		}
		.buttonStyle(TerminalKeyStyle(special: true, state: state))
		.accessibilityLabel(label)
		.accessibilityValue(modifierValue(state))
		.accessibilityAddTraits(state == .off ? [] : .isSelected)
		.onChange(of: state) { _, newState in
			AccessibilityNotification.Announcement("\(label), \(modifierValue(newState))").post()
		}
	}

	private func modifierValue(_ state: StickyModifier) -> String {
		switch state {
		case .off: String(localized: "Off")
		case .once: String(localized: "Applies to the next key")
		case .locked: String(localized: "Locked")
		}
	}
}

/// A key cap: a rounded key with a drop shadow, darker for special keys, filled with the
/// accent color for a modifier that is on.
private struct TerminalKeyCap<Label: View>: View {
	var special = false
	var state = StickyModifier.off
	var pressed = false
	@ViewBuilder let label: Label

	var body: some View {
		label
			.font(.footnote.monospaced().weight(.medium))
			.foregroundStyle(state == .locked ? Color(.systemBackground) : Color.primary)
			.padding(.horizontal, 6)
			// 44 pt wide; with the vertical padding the tap target is 44 pt tall too (design#163).
			.frame(minWidth: 44, minHeight: 38)
			.background {
				RoundedRectangle(cornerRadius: 5)
					.fill(fill)
					.shadow(color: .black.opacity(0.3), radius: 0, x: 0, y: 1)
			}
			.padding(.vertical, 3)
			.contentShape(Rectangle())
	}

	private var fill: Color {
		switch state {
		case .locked: return .accentColor
		case .once: return .accentColor.opacity(0.35)
		case .off:
			if pressed { return Color(.systemGray3) }
			return special ? Color(.systemGray4) : Color(.tertiarySystemBackground)
		}
	}
}

private struct TerminalKeyStyle: ButtonStyle {
	var special = false
	var state = StickyModifier.off
	@Environment(\.isEnabled) private var isEnabled

	func makeBody(configuration: Configuration) -> some View {
		TerminalKeyCap(special: special, state: state, pressed: configuration.isPressed) {
			configuration.label
		}
		.opacity(isEnabled ? 1 : 0.5)
	}
}

/// An arrow key that repeats while held, after a short pause, as SwiftTerm's do. It repeats
/// slower than a local terminal, since every press crosses the mesh.
private struct RepeatingKey: View {
	let systemImage: String
	let label: LocalizedStringKey
	let action: () -> Void
	@State private var repeatTask: Task<Void, Never>?
	@Environment(\.isEnabled) private var isEnabled

	var body: some View {
		TerminalKeyCap(pressed: repeatTask != nil) {
			Image(systemName: systemImage)
		}
		.opacity(isEnabled ? 1 : 0.5)
		.gesture(
			DragGesture(minimumDistance: 0)
				.onChanged { _ in
					guard isEnabled, repeatTask == nil else { return }
					start()
				}
				.onEnded { _ in stop() }
		)
		.onDisappear { stop() }
		.accessibilityElement()
		.accessibilityLabel(label)
		.accessibilityAddTraits(.isButton)
		.accessibilityAction { if isEnabled { action() } }
	}

	private func start() {
		action()
		repeatTask = Task { @MainActor in
			try? await Task.sleep(for: .milliseconds(600))
			while !Task.isCancelled {
				action()
				try? await Task.sleep(for: .milliseconds(150))
			}
		}
	}

	private func stop() {
		repeatTask?.cancel()
		repeatTask = nil
	}
}
