import SwiftUI
import OSLog

extension NSNotification.Name {
	static let findNodeResponseDidChange = NSNotification.Name("findNodeResponseDidChange")
}

struct FindNodeButton: View {
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	var fromUser: UserEntity?
	var toUser: UserEntity?
	var nodeName: String

	@State private var isWaitingForResponse = false
	@State private var hasActiveFindNode = false
	@State private var activeUntil: Date?
	@State private var activeResetTask: Task<Void, Never>?
	@State private var alert: FindNodeAlert?

	private var hasConnectedTransport: Bool {
		guard fromUser != nil,
			  toUser != nil,
			  accessoryManager.activeConnection != nil else {
			return false
		}

		switch accessoryManager.state {
		case .communicating, .retrievingDatabase, .subscribed:
			return true
		case .uninitialized, .idle, .discovering, .connecting, .retrying:
			return accessoryManager.isConnected
		}
	}

	private var isWaitingForSync: Bool {
		hasConnectedTransport && accessoryManager.state != .subscribed
	}

	private var canSend: Bool {
		fromUser != nil
			&& toUser != nil
			&& hasConnectedTransport
			&& !isWaitingForResponse
	}

	private var isActive: Bool {
		guard hasActiveFindNode else {
			return false
		}
		guard let activeUntil else {
			return true
		}
		return activeUntil > Date.now
	}

	var body: some View {
		TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
			VStack(alignment: .leading, spacing: 18) {
				HStack(alignment: .center, spacing: 16) {
					FindNodeBeaconView(isActive: isActive, reduceMotion: reduceMotion)
						.frame(width: 82, height: 82)
						.accessibilityHidden(true)

					VStack(alignment: .leading, spacing: 6) {
						Text("Find Node")
							.font(.headline)
						Text(statusText(at: timeline.date))
							.font(.subheadline)
							.foregroundStyle(.secondary)
							.fixedSize(horizontal: false, vertical: true)
						if isActive {
							Label("Locating", systemImage: "dot.radiowaves.left.and.right")
								.font(.caption.weight(.semibold))
								.foregroundStyle(.orange)
								.labelStyle(.titleAndIcon)
						} else if isWaitingForSync {
							Label("Syncing", systemImage: "arrow.triangle.2.circlepath")
								.font(.caption.weight(.medium))
								.foregroundStyle(.secondary)
								.labelStyle(.titleAndIcon)
						} else if hasConnectedTransport {
							Label("Ready", systemImage: "checkmark.circle")
								.font(.caption.weight(.medium))
								.foregroundStyle(.secondary)
								.labelStyle(.titleAndIcon)
						}
					}
					Spacer(minLength: 0)
				}

				HStack(spacing: 12) {
					Button {
						sendFindNode(stop: false)
					} label: {
						FindNodeActionLabel(
							title: isActive ? "Restart" : "Start Find Node",
							systemImage: isActive ? "arrow.clockwise.circle.fill" : "location.circle.fill"
						)
					}
					.buttonStyle(.borderedProminent)
					.controlSize(.large)
					.disabled(!canSend)

					if isActive {
						Button(role: .cancel) {
							sendFindNode(stop: true)
						} label: {
							FindNodeActionLabel(
								title: "Stop",
								systemImage: "stop.circle.fill"
							)
						}
						.buttonStyle(.bordered)
						.controlSize(.large)
						.disabled(!canSend)
					}
				}
			}
			.padding(18)
			.background(cardBackground)
			.overlay(cardBorder)
			.clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
		}
		.padding(.vertical, 10)
		.listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
		.listRowBackground(Color.clear)
		.accessibilityElement(children: .combine)
		.accessibilityLabel("Find Node")
		.accessibilityValue(accessibilityValue)
		.onChange(of: accessoryManager.isConnected) { _, isConnected in
			if !isConnected {
				resetActiveState()
			}
		}
		.onChange(of: toUser?.num) {
			resetActiveState()
		}
		.onDisappear {
			activeResetTask?.cancel()
		}
		.alert(item: $alert) { alert in
			Alert(
				title: Text(alert.title),
				message: Text(alert.message),
				dismissButton: .default(Text("OK"))
			)
		}
	}

	private var cardBackground: some ShapeStyle {
		LinearGradient(
			colors: isActive
				? [Color.orange.opacity(0.20), Color.orange.opacity(0.08), Color.clear]
				: [Color.accentColor.opacity(0.12), Color.clear],
			startPoint: .topLeading,
			endPoint: .bottomTrailing
		)
	}

	private var cardBorder: some View {
		RoundedRectangle(cornerRadius: 24, style: .continuous)
			.strokeBorder(isActive ? Color.orange.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 1)
	}

	private var accessibilityValue: String {
		if isWaitingForResponse {
			return hasActiveFindNode
				? String(localized: "Stopping buzzer")
				: String(localized: "Starting buzzer")
		}
		if isActive {
			return String(localized: "Buzzer active, repeating every 2 seconds")
		}
		if isWaitingForSync {
			return String(localized: "Connected, waiting for sync before sending")
		}
		if !hasConnectedTransport {
			return String(localized: "Not connected")
		}
		return String(localized: "Ready")
	}

	private func statusText(at date: Date = .now) -> String {
		if isWaitingForResponse {
			return hasActiveFindNode
				? String(localized: "Stopping buzzer...")
				: String(localized: "Starting buzzer...")
		}
		if isActive {
			if let activeUntil {
				let seconds = max(0, Int(activeUntil.timeIntervalSince(date).rounded(.up)))
				if seconds > 0 {
					return String(localized: "Buzzing every 2 seconds. Stops in \(seconds)s.")
				}
			}
			return String(localized: "Buzzing every 2 seconds")
		}
		if isWaitingForSync {
			return String(localized: "Connected. Request will send after sync finishes.")
		}
		if !hasConnectedTransport {
			return String(localized: "Connect to this node to use Find Node.")
		}
		return String(localized: "Play this node's buzzer so it is easier to locate nearby.")
	}

	private func sendFindNode(stop: Bool) {
		guard let fromUser, let toUser else {
			alert = FindNodeAlert(
				title: String(localized: "Find Node Unavailable"),
				message: String(localized: "Connect to a node with administration access, then try again.")
			)
			return
		}

		isWaitingForResponse = true
		let responseTask = Task {
			await waitForFindNodeResponse(nodeNum: toUser.num)
		}

		Task {
			do {
				_ = try await accessoryManager.sendFindNodeRequest(
					fromUser: fromUser,
					toUser: toUser,
					stop: stop
				)
				await MainActor.run {
					isWaitingForResponse = false
					if stop {
						resetActiveState()
					} else {
						startActive(durationSeconds: 30)
					}
				}
			} catch {
				responseTask.cancel()
				await MainActor.run {
					isWaitingForResponse = false
					alert = FindNodeAlert(
						title: String(localized: "Find Node Failed"),
						message: findNodeFailureMessage(for: error)
					)
				}
				Logger.mesh.warning("Failed to send find node request: \(error)")
				return
			}

			let response = await responseTask.value
			await MainActor.run {
				isWaitingForResponse = false
				handle(response: response, requestedStop: stop)
			}
		}
	}

	private func resetActiveState() {
		activeResetTask?.cancel()
		activeResetTask = nil
		isWaitingForResponse = false
		hasActiveFindNode = false
		activeUntil = nil
	}

	private func startActive(durationSeconds: UInt32) {
		hasActiveFindNode = true
		activeUntil = Date.now.addingTimeInterval(TimeInterval(durationSeconds))
		scheduleActiveReset(after: durationSeconds)
	}

	private func scheduleActiveReset(after durationSeconds: UInt32) {
		activeResetTask?.cancel()
		activeResetTask = Task {
			try? await Task.sleep(for: .seconds(durationSeconds))
			guard !Task.isCancelled else {
				return
			}
			await MainActor.run {
				hasActiveFindNode = false
				activeUntil = nil
				activeResetTask = nil
			}
		}
	}

	private func waitForFindNodeResponse(nodeNum: Int64) async -> FindNodeResponseEvent? {
		await withTaskGroup(of: FindNodeResponseEvent?.self) { group in
			group.addTask {
				for await notification in NotificationCenter.default.notifications(named: .findNodeResponseDidChange) {
					guard let event = notification.object as? FindNodeResponseEvent,
						  event.nodeNum == nodeNum else {
						continue
					}
					return event
				}
				return nil
			}
			group.addTask {
				try? await Task.sleep(for: .seconds(30))
				return nil
			}

			let result = await group.next() ?? nil
			group.cancelAll()
			return result
		}
	}

	private func handle(response: FindNodeResponseEvent?, requestedStop: Bool) {
		guard let response else {
			Logger.mesh.warning("Find Node request sent but no response was received for \(nodeName, privacy: .public)")
			return
		}

		switch response.result {
		case .started:
			let duration = response.durationSeconds == 0 ? 30 : response.durationSeconds
			startActive(durationSeconds: duration)
		case .stopped:
			resetActiveState()
		case .noBuzzer:
			resetActiveState()
			alert = FindNodeAlert(
				title: String(localized: "No Buzzer Detected"),
				message: "Firmware did not detect a supported buzzer output on \(nodeName)."
			)
		case .buzzerDisabled:
			resetActiveState()
			alert = FindNodeAlert(
				title: String(localized: "Buzzer Disabled"),
				message: "\(nodeName) has buzzer hardware, but buzzer mode is disabled."
			)
		case .unrecognized:
			resetActiveState()
			alert = FindNodeAlert(
				title: String(localized: "Unknown Find Node Response"),
				message: String(localized: "Firmware returned a Find Node response this app does not recognize.")
			)
		}
	}

	private struct FindNodeAlert: Identifiable {
		let id = UUID()
		let title: String
		let message: String
	}

	private func findNodeFailureMessage(for error: Error) -> String {
		if let localizedError = error as? LocalizedError,
		   let errorDescription = localizedError.errorDescription {
			return errorDescription
		}
		return String(localized: "The request could not be sent. Check the connection and try again.")
	}
}

private struct FindNodeActionLabel: View {
	let title: LocalizedStringKey
	let systemImage: String

	var body: some View {
		HStack(spacing: 8) {
			Image(systemName: systemImage)
				.imageScale(.medium)
				.frame(width: 20)
				.accessibilityHidden(true)
			Text(title)
				.lineLimit(1)
				.minimumScaleFactor(0.85)
		}
		.frame(maxWidth: .infinity, minHeight: 28, alignment: .center)
	}
}

private struct FindNodeBeaconView: View {
	let isActive: Bool
	let reduceMotion: Bool
	private let cadence: TimeInterval = 2.0

	var body: some View {
		TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive || reduceMotion)) { timeline in
			let phase = isActive && !reduceMotion
				? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cadence) / cadence
				: 0
			let pulse = isActive && !reduceMotion
				? 0.5 + 0.5 * sin(phase * .pi * 2.0)
				: 0.0

			ZStack {
				if isActive {
					ForEach(0..<3, id: \.self) { index in
						RippleRing(progress: (phase + Double(index) / 3.0).truncatingRemainder(dividingBy: 1.0))
					}

					Circle()
						.fill(Color.orange.opacity(0.08 + 0.06 * pulse))
						.frame(width: 74, height: 74)
						.scaleEffect(0.94 + 0.08 * pulse)
				}

				Circle()
					.fill(.regularMaterial)
					.background {
						Circle()
							.fill(
								RadialGradient(
									colors: isActive
										? [Color.orange.opacity(0.30), Color.orange.opacity(0.10), Color.clear]
										: [Color.accentColor.opacity(0.18), Color.clear],
									center: .center,
									startRadius: 4,
									endRadius: 42
								)
							)
					}
					.overlay {
						Circle()
							.fill(isActive ? Color.orange.opacity(0.14) : Color.accentColor.opacity(0.12))
					}
					.overlay {
						Circle()
							.strokeBorder(isActive ? Color.orange.opacity(0.36) : Color.accentColor.opacity(0.22), lineWidth: 1)
					}
					.frame(width: 58, height: 58)
					.shadow(color: isActive ? Color.orange.opacity(0.32) : Color.clear, radius: 18, y: 6)

				Image(systemName: isActive ? "location.fill" : "location.circle.fill")
					.font(.system(size: 24, weight: .semibold))
					.symbolRenderingMode(.palette)
					.foregroundStyle(isActive ? Color.orange : Color.accentColor, .white.opacity(0.9))
					.symbolEffect(.pulse, options: .speed(0.5), isActive: isActive && !reduceMotion)
			}
		}
	}

	private struct RippleRing: View {
		let progress: TimeInterval

		var body: some View {
			Circle()
				.stroke(Color.orange.opacity(max(0, 0.34 * pow(1 - progress, 1.5))), lineWidth: 2)
				.scaleEffect(0.52 + progress * 0.72)
		}
	}
}
