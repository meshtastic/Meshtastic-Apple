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
				takesKeyboard: !lineMode && session.state == .open,
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
				ExtraKeyRows(session: session, onHistory: lineMode ? recallHistory : nil)
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
			size: { session.setTerminalSize(cols: $0, rows: $1) }
		)
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

/// Termux's two rows of keys that touch keyboards lack.
struct ExtraKeyRows: View {
	@ObservedObject var session: RemoteShellSession
	/// In line mode the up and down arrows recall history instead of reaching the node.
	var onHistory: ((_ older: Bool) -> Void)?

	var body: some View {
		VStack(spacing: 0) {
			Divider()
			HStack(spacing: 0) {
				key("ESC", label: "Escape") { session.send(.escape) }
				key("/", label: "Slash") { session.type("/") }
				key("-", label: "Hyphen") { session.type("-") }
				key("HOME", label: "Home") { session.send(.home) }
				key("↑", label: "Up arrow") { arrow(.up) }
				key("END", label: "End") { session.send(.end) }
				key("PGUP", label: "Page up") { session.send(.pageUp) }
			}
			HStack(spacing: 0) {
				key("TAB", label: "Tab") { session.send(.tab) }
				modifier("CTRL", label: String(localized: "Control"), state: session.control) { session.control = session.control.next }
				modifier("ALT", label: String(localized: "Alt"), state: session.alt) { session.alt = session.alt.next }
				key("←", label: "Left arrow") { session.send(.left) }
				key("↓", label: "Down arrow") { arrow(.down) }
				key("→", label: "Right arrow") { session.send(.right) }
				key("PGDN", label: "Page down") { session.send(.pageDown) }
			}
		}
		.background(Color(.secondarySystemBackground))
		.disabled(session.state != .open)
	}

	private func arrow(_ key: TerminalKey) {
		if let onHistory {
			onHistory(key == .up)
		} else {
			session.send(key)
		}
	}

	private func key(_ title: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Text(title)
				.font(.footnote.monospaced().weight(.medium))
				.frame(maxWidth: .infinity, minHeight: 44)
				.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.accessibilityLabel(label)
	}

	private func modifier(_ title: String, label: String, state: StickyModifier, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Text(title)
				.font(.footnote.monospaced().weight(state == .off ? .medium : .bold))
				.foregroundStyle(state == .locked ? Color(.systemBackground) : Color.primary)
				.frame(maxWidth: .infinity, minHeight: 44)
				.background {
					RoundedRectangle(cornerRadius: 6)
						.fill(state == .locked ? Color.accentColor : state == .once ? Color.accentColor.opacity(0.25) : .clear)
						.padding(3)
				}
				.overlay(alignment: .bottom) {
					// State in shape as well as color: one bar for next key, two for locked.
					if state != .off {
						HStack(spacing: 2) {
							ForEach(0..<(state == .locked ? 2 : 1), id: \.self) { _ in
								Rectangle().frame(width: 10, height: 2)
							}
						}
						.foregroundStyle(state == .locked ? Color(.systemBackground) : Color.accentColor)
						.padding(.bottom, 6)
					}
				}
				.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
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
