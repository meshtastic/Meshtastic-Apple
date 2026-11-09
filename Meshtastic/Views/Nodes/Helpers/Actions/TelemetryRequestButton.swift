import SwiftUI
import OSLog

enum LocalStatsRequestTransport {
	case sharedChannel
	case remoteAdmin

	static func shouldChooseMethod(from: Int64, to: Int64) -> Bool {
		from != to
	}

	static func remoteAdminAvailable(for destinationPublicKey: Data?) -> Bool {
		destinationPublicKey?.count == 32
	}
}

/// Asks a node for one kind of telemetry. Beside a log row it is an icon; on a log screen it
/// is a labeled button. Sending says so, and a routing error that answers the request is
/// reported by `TelemetryRequestTracker`.
struct TelemetryRequestButton: View {
	enum Style {
		case icon
		case labeled(title: LocalizedStringKey, cooldownTitle: LocalizedStringKey)
	}

	@EnvironmentObject var accessoryManager: AccessoryManager
	@StateObject private var rateLimitStorage = RateLimitStorage.shared

	var node: NodeInfoEntity
	var kind: TelemetryRequestKind
	var style = Style.icon

	@State private var sentAlertPresented = false
	@State private var sendError: String?
	@State private var presentedSheet: MethodSheet?
	/// Set by the method sheet when it sent the request, so the sent alert shows once it closes.
	@State private var sentFromSheet = false

	private struct MethodSheet: Identifiable {
		let id = UUID()
	}

	static let rateLimit: TimeInterval = 30

	private var nodeName: String {
		node.user?.displayLongName ?? node.num.toHex()
	}

	var body: some View {
		let completion = rateLimitStorage.rateLimitRemainingPercentage(forKey: kind.rateLimitKey)
		let secondsRemaining = Int(rateLimitStorage.rateLimitSecondsRemaining(forKey: kind.rateLimitKey))
		Group {
			switch style {
			case .icon:
				Button(action: request) {
					Group {
						if completion > 0 {
							Image("progress.ring.dashed", variableValue: completion)
						} else {
							Image(systemName: "arrow.clockwise")
						}
					}
					.imageScale(.medium)
					.frame(width: 44, height: 44)
					.contentShape(Rectangle())
					// The full target without making the row taller than its neighbors.
					.padding(.vertical, -8)
				}
				.buttonStyle(.borderless)
				.disabled(completion > 0)
				.accessibilityLabel(kind.requestTitle)
				.accessibilityValue(completion > 0 ? String(localized: "Wait \(secondsRemaining) s") : "")
			case let .labeled(title, cooldownTitle):
				if completion > 0 {
					Label {
						Text("\(Text(cooldownTitle)) \(secondsRemaining)s")
							.foregroundStyle(.secondary)
							.lineLimit(1)
					} icon: {
						Image("progress.ring.dashed", variableValue: completion)
							.foregroundStyle(.secondary)
					}
					.disabled(true)
				} else {
					Button(action: request) {
						Label {
							Text(title)
								.lineLimit(1)
						} icon: {
							Image(systemName: "arrow.clockwise")
								.symbolRenderingMode(.hierarchical)
						}
					}
				}
			}
		}
		.hostedAlert("Telemetry Requested", isPresented: $sentAlertPresented) {
			Button("OK", role: .cancel) { }
		} message: {
			Text("Requested \(kind.name) from \(nodeName). The reply can take a while.")
		}
		.hostedAlert("Couldn’t Send Request", isPresented: Binding(get: { sendError != nil }, set: { if !$0 { sendError = nil } })) {
			Button("OK", role: .cancel) { }
		} message: {
			Text(sendError ?? "")
		}
		.hostedSheet(item: $presentedSheet, onDismiss: {
			if sentFromSheet {
				sentFromSheet = false
				sentAlertPresented = true
			}
		}) { _ in
			LocalStatsRequestMethodSheet(node: node, nodeName: nodeName) {
				sentFromSheet = true
			}
		}
	}

	private func request() {
		let source = accessoryManager.activeConnection?.device.num ?? 0
		// Local stats can also go to a node that authorizes this radio as a remote admin.
		if kind == .localStats, LocalStatsRequestTransport.shouldChooseMethod(from: source, to: node.num) {
			presentedSheet = MethodSheet()
		} else {
			send()
		}
	}

	private func send() {
		Task { @MainActor in
			do {
				try await Self.send(kind, to: node, nodeName: nodeName, transport: .sharedChannel, accessoryManager: accessoryManager)
				sentAlertPresented = true
			} catch {
				sendError = error.localizedDescription
				Logger.mesh.warning("Failed to send \(kind.rawValue, privacy: .public) telemetry request: \(error.localizedDescription, privacy: .public)")
			}
		}
	}

	/// Sends the request and starts the cooldown.
	@MainActor
	static func send(
		_ kind: TelemetryRequestKind,
		to node: NodeInfoEntity,
		nodeName: String,
		transport: LocalStatsRequestTransport,
		accessoryManager: AccessoryManager
	) async throws {
		try await accessoryManager.sendTelemetryRequest(
			kind,
			destNum: node.num,
			nodeName: nodeName,
			transport: transport,
			destinationPublicKey: node.user?.publicKey
		)
		RateLimitStorage.shared.actionOccured(forKey: kind.rateLimitKey, rateLimit: rateLimit)
	}
}

private struct LocalStatsRequestMethodSheet: View {
	@Environment(\.dismiss) private var dismiss
	@EnvironmentObject private var accessoryManager: AccessoryManager

	let node: NodeInfoEntity
	let nodeName: String
	let onSent: () -> Void
	@State private var errorMessage: String?
	@State private var isSending = false

	private var remoteAdminAvailable: Bool {
		LocalStatsRequestTransport.remoteAdminAvailable(for: node.user?.publicKey)
	}

	var body: some View {
		SheetNavigationStack {
			List {
				Section("Send local stats request") {
					Text("Choose the encryption method for this request to \(nodeName).")
						.foregroundStyle(.secondary)
				}

				Section {
					Button {
						send(transport: .sharedChannel)
					} label: {
						Label {
							VStack(alignment: .leading, spacing: 3) {
								Text("Shared channel")
								Text("Encrypted with this mesh channel. Use this for ordinary sharing.")
									.font(.footnote)
									.foregroundStyle(.secondary)
							}
						} icon: {
							Image(systemName: "person.2.fill")
						}
					}
					.disabled(isSending)

					Button {
						send(transport: .remoteAdmin)
					} label: {
						Label {
							VStack(alignment: .leading, spacing: 3) {
								Text("Remote admin")
								Text(remoteAdminAvailable
									? "Uses PKI. The node must authorize your identity as a remote admin."
									: "Unavailable because this node has no public key.")
									.font(.footnote)
									.foregroundStyle(.secondary)
							}
						} icon: {
							Image(systemName: "lock.fill")
						}
					}
					.disabled(isSending || !remoteAdminAvailable)
				}
			}
			.navigationTitle("Request method")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") { dismiss() }
				}
			}
			.hostedAlert("Couldn’t send Local Stats request", isPresented: .constant(errorMessage != nil)) {
				Button("OK") { errorMessage = nil }
			} message: {
				Text(errorMessage ?? "")
			}
		}
	}

	private func send(transport: LocalStatsRequestTransport) {
		isSending = true
		Task { @MainActor in
			do {
				try await TelemetryRequestButton.send(
					.localStats,
					to: node,
					nodeName: nodeName,
					transport: transport,
					accessoryManager: accessoryManager
				)
				onSent()
				dismiss()
			} catch {
				errorMessage = error.localizedDescription
				isSending = false
				Logger.mesh.warning("Failed to send local stats request: \(error)")
			}
		}
	}
}
