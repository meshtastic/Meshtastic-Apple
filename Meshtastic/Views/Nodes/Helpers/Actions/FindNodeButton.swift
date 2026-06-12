import SwiftUI
import OSLog

extension NSNotification.Name {
	static let findNodeResponseDidChange = NSNotification.Name("findNodeResponseDidChange")
}

struct FindNodeButton: View {
	@EnvironmentObject var accessoryManager: AccessoryManager

	var fromUser: UserEntity?
	var toUser: UserEntity?
	var nodeName: String

	@State private var isWaitingForResponse = false
	@State private var hasActiveFindNode = false
	@State private var alert: FindNodeAlert?

	private var canSend: Bool {
		fromUser != nil && toUser != nil && accessoryManager.isConnected && !isWaitingForResponse
	}

	var body: some View {
		Group {
			Button {
				sendFindNode(stop: false)
			} label: {
				if isWaitingForResponse {
					Label {
						Text("Waiting for Find Node")
							.foregroundStyle(.secondary)
					} icon: {
						ProgressView()
					}
				} else {
					Label {
						Text("Find Node")
					} icon: {
						Image(systemName: "speaker.wave.2")
					}
				}
			}
			.disabled(!canSend)

			if hasActiveFindNode {
				Button(role: .cancel) {
					sendFindNode(stop: true)
				} label: {
					Label("Stop Buzzing", systemImage: "speaker.slash")
				}
				.disabled(!canSend)
			}
		}
		.alert(item: $alert) { alert in
			Alert(
				title: Text(alert.title),
				message: Text(alert.message),
				dismissButton: .default(Text("OK"))
			)
		}
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
			} catch {
				responseTask.cancel()
				await MainActor.run {
					isWaitingForResponse = false
					alert = FindNodeAlert(
						title: String(localized: "Find Node Failed"),
						message: String(localized: "The request could not be sent. Check the connection and try again.")
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
			alert = FindNodeAlert(
				title: String(localized: "No Find Node Response"),
				message: requestedStop
					? String(localized: "The stop request was sent, but this firmware did not return a Find Node response.")
					: String(localized: "The request was sent, but this firmware did not return a Find Node response.")
			)
			return
		}

		switch response.result {
		case .started:
			hasActiveFindNode = true
			let duration = response.durationSeconds == 0 ? 30 : response.durationSeconds
			alert = FindNodeAlert(
				title: String(localized: "Find Node Started"),
				message: "\(nodeName) is buzzing for \(duration) seconds."
			)
		case .stopped:
			hasActiveFindNode = false
			alert = FindNodeAlert(
				title: String(localized: "Find Node Stopped"),
				message: "\(nodeName) stopped buzzing."
			)
		case .noBuzzer:
			hasActiveFindNode = false
			alert = FindNodeAlert(
				title: String(localized: "No Buzzer Detected"),
				message: "Firmware did not detect a supported buzzer output on \(nodeName)."
			)
		case .buzzerDisabled:
			hasActiveFindNode = false
			alert = FindNodeAlert(
				title: String(localized: "Buzzer Disabled"),
				message: "\(nodeName) has buzzer hardware, but buzzer mode is disabled."
			)
		case .unrecognized:
			hasActiveFindNode = false
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
}
