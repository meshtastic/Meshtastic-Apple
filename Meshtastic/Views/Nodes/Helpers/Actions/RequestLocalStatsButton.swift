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

struct RequestLocalStatsButton: View {
	@EnvironmentObject var accessoryManager: AccessoryManager
	@StateObject private var rateLimitStorage = RateLimitStorage.shared

	var node: NodeInfoEntity
	var title = "Request Local Stats"
	var cooldownTitle = "Local Stats"
	var systemImage = "chart.bar"

	@State
	private var isPresentingLocalStatsSentAlert: Bool = false
	@State
	private var presentedSheet: LocalStatsRequestSheet?

	private enum LocalStatsRequestSheet: String, Identifiable {
		case method

		var id: String { rawValue }
	}

	var body: some View {
		let completion = rateLimitStorage.rateLimitRemainingPercentage(forKey: "localstats")
		let secondsRemaining = rateLimitStorage.rateLimitSecondsRemaining(forKey: "localstats")
		Group {
			if completion > 0.0 {
				Label {
					Text("\(cooldownTitle) \(Int(secondsRemaining))s")
						.foregroundStyle(.secondary)
						.lineLimit(1)
				} icon: {
					Image("progress.ring.dashed", variableValue: completion)
						.foregroundStyle(.secondary)
				}.disabled(true)
			} else {
				Button(action: requestLocalStats) {
					Label {
					Text(title)
						.lineLimit(1)
					} icon: {
					Image(systemName: systemImage)
						.symbolRenderingMode(.hierarchical)
					}
				}
			}
		}
		.alert("Local Stats Requested", isPresented: $isPresentingLocalStatsSentAlert) {
			Button("OK", role: .cancel) { }
		} message: {
			Text("A local stats request has been sent to \(node.user?.longName ?? "this node"). Responses can take some time.")
		}
		.sheet(item: $presentedSheet) { _ in
			LocalStatsRequestMethodSheet(node: node)
		}
	}

	private func requestLocalStats() {
		let destination = node.user?.num ?? 0
		let source = accessoryManager.activeConnection?.device.num ?? 0
		if LocalStatsRequestTransport.shouldChooseMethod(from: source, to: destination) {
			presentedSheet = .method
		} else {
			sendLocalStats(transport: .sharedChannel)
		}
	}

	private func sendLocalStats(transport: LocalStatsRequestTransport) {
		rateLimitStorage.actionOccured(forKey: "localstats", rateLimit: 30.0)
		Task { @MainActor in
			do {
				try await accessoryManager.sendLocalStatsRequest(
					destNum: node.user?.num ?? 0,
					wantResponse: true,
					transport: transport,
					destinationPublicKey: node.user?.publicKey
				)
				isPresentingLocalStatsSentAlert = true
			} catch {
				Logger.mesh.warning("Failed to send local stats request: \(error)")
			}
		}
	}
}

private struct LocalStatsRequestMethodSheet: View {
	@Environment(\.dismiss) private var dismiss
	@EnvironmentObject private var accessoryManager: AccessoryManager

	let node: NodeInfoEntity
	@State private var errorMessage: String?
	@State private var isSending = false

	private var destination: Int64 { node.user?.num ?? 0 }
	private var destinationPublicKey: Data? { node.user?.publicKey }
	private var remoteAdminAvailable: Bool {
		LocalStatsRequestTransport.remoteAdminAvailable(for: destinationPublicKey)
	}

	var body: some View {
		NavigationStack {
			List {
				Section("Send local stats request") {
					Text("Choose the encryption method for this request to \(node.user?.longName ?? "this node").")
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
			.alert("Couldn’t send Local Stats request", isPresented: .constant(errorMessage != nil)) {
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
				try await accessoryManager.sendLocalStatsRequest(
					destNum: destination,
					wantResponse: true,
					transport: transport,
					destinationPublicKey: destinationPublicKey
				)
				RateLimitStorage.shared.actionOccured(forKey: "localstats", rateLimit: 30.0)
				dismiss()
			} catch {
				errorMessage = error.localizedDescription
				isSending = false
				Logger.mesh.warning("Failed to send local stats request: \(error)")
			}
		}
	}
}
