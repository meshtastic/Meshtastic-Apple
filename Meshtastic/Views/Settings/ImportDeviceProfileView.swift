//
//  ImportDeviceProfileView.swift
//  Meshtastic
//
//  Review sheet for "Import Device Configuration": shows what a parsed `.cfg` profile will apply to the
//  connected node, lets the user toggle coarse sections (Security & Identity defaults off), warns about
//  sensitive material and the LoRa/channel reboot, and — after an explicit confirmation — applies the
//  selected sections in order, reporting per-item progress and a final summary.
//

import SwiftUI
import MeshtasticProtobufs
import OSLog

@available(iOS 18, *)
struct ImportDeviceProfileView: View {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@Environment(\.modelContext) private var context
	@Environment(\.dismiss) private var dismiss

	let plan: DeviceProfileImportPlan

	@State private var selection: Set<ImportSection>
	@State private var phase: Phase = .review
	@State private var progress: ProgressState?
	@State private var isPresentingConfirm = false
	@State private var importTask: Task<Void, Never>?
	/// Liveness backstop: set true if the apply is still running after a grace period so the user can
	/// always leave even if a single send stalls on the transport.
	@State private var canForceDismiss = false

	private enum Phase: Equatable {
		case review
		case applying
		case done(DeviceProfileImportResult)

		static func == (lhs: Phase, rhs: Phase) -> Bool {
			switch (lhs, rhs) {
			case (.review, .review), (.applying, .applying): return true
			case (.done, .done): return true
			default: return false
			}
		}
	}

	private struct ProgressState {
		let title: String
		let index: Int
		let total: Int
	}

	init(plan: DeviceProfileImportPlan) {
		self.plan = plan
		// Default every present section ON except Security & Identity.
		_selection = State(initialValue: Set(plan.presentSections.filter(\.defaultsOn)))
	}

	private var connectedNode: NodeInfoEntity? {
		guard let num = accessoryManager.activeDeviceNum else { return nil }
		return getNodeInfo(id: num, context: context)
	}

	private var isApplying: Bool { phase == .applying }

	private var canImport: Bool {
		accessoryManager.isConnected && !selection.isEmpty && !isApplying
	}

	var body: some View {
		NavigationStack {
			Group {
				switch phase {
				case .review, .applying:
					reviewList
				case .done(let result):
					resultList(result)
				}
			}
			.navigationTitle("Import Configuration")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					if isApplying {
						// Always give the user a way out of an in-progress import. Cancel stops the run at the
						// next step; once the grace period elapses the same button also force-dismisses so a
						// stalled send can never trap the sheet.
						Button(canForceDismiss ? "Dismiss" : "Cancel") {
							importTask?.cancel()
							if canForceDismiss { dismiss() }
						}
					} else {
						Button(isReviewing ? "Cancel" : "Done") { dismiss() }
					}
				}
				if isReviewing && !isApplying {
					ToolbarItem(placement: .confirmationAction) {
						Button("Import") { isPresentingConfirm = true }
							.disabled(!canImport)
					}
				}
			}
			.confirmationDialog("Apply Configuration", isPresented: $isPresentingConfirm, titleVisibility: .visible) {
				Button("Apply Configuration", role: .destructive) { startImport() }
				Button("Cancel", role: .cancel) { }
			} message: {
				Text(confirmationMessage)
			}
		}
		.interactiveDismissDisabled(isApplying && !canForceDismiss)
	}

	private var isReviewing: Bool {
		if case .done = phase { return false }
		return true
	}

	// MARK: Review

	@ViewBuilder
	private var reviewList: some View {
		List {
			Section {
				Text("Apply this saved configuration to \(connectedNode?.user?.longName ?? "the connected node").")
					.font(.callout)
				if !accessoryManager.isConnected {
					Label("Connect to a radio before importing.", systemImage: "antenna.radiowaves.left.and.right.slash")
						.font(.caption)
						.foregroundColor(.orange)
				}
				if isApplying && canForceDismiss {
					Label("This is taking longer than expected. You can cancel or dismiss.", systemImage: "clock.arrow.circlepath")
						.font(.caption)
						.foregroundColor(.orange)
				}
			}

			if plan.containsSensitive(in: selection) {
				Section {
					Label {
						VStack(alignment: .leading, spacing: 4) {
							Text("This import overwrites sensitive material")
								.font(.callout.bold())
							Text(sensitiveDetail)
								.font(.caption)
								.foregroundColor(.secondary)
						}
					} icon: {
						Image(systemName: "exclamationmark.shield.fill").foregroundColor(.orange)
					}
				}
			}

			if plan.willReboot(in: selection) {
				Section {
					Label("Applying LoRa/channel settings reboots the radio; it will briefly disconnect.", systemImage: "arrow.clockwise.circle")
						.font(.caption)
						.foregroundColor(.orange)
				}
			}

			Section("Sections to Import") {
				ForEach(plan.presentSections) { section in
					sectionRow(section)
				}
			}
		}
	}

	@ViewBuilder
	private func sectionRow(_ section: ImportSection) -> some View {
		let sectionItems = plan.items.filter { $0.section == section }
		let isOn = Binding(
			get: { selection.contains(section) },
			set: { newValue in
				if newValue { selection.insert(section) } else { selection.remove(section) }
			}
		)
		Toggle(isOn: isOn) {
			VStack(alignment: .leading, spacing: 2) {
				HStack(spacing: 6) {
					Text(section.title)
					if sectionItems.contains(where: \.isSensitive) {
						Image(systemName: "key.fill").font(.caption2).foregroundColor(.orange)
					}
				}
				Text(sectionItems.map(\.summary).joined(separator: ", "))
					.font(.caption)
					.foregroundColor(.secondary)
				if section == .security {
					Text("Changes this node's identity (private/public key) and admin keys — can break existing direct messages and lock local administration.")
						.font(.caption2)
						.foregroundColor(.orange)
				}
			}
		}
		.disabled(isApplying)
		.overlay(alignment: .trailing) {
			if let progress, isApplying, currentSection == section {
				ProgressView().padding(.trailing, 44)
			}
		}
	}

	private var currentSection: ImportSection? {
		guard let progress else { return nil }
		let items = plan.items(for: selection)
		guard progress.index < items.count else { return nil }
		return items[progress.index].section
	}

	// MARK: Result

	@ViewBuilder
	private func resultList(_ result: DeviceProfileImportResult) -> some View {
		List {
			Section {
				if result.isCompleteSuccess {
					// Sends are fire-and-forget (no device ack), so report what was sent and nudge the user
					// to verify rather than claiming the device confirmed every change.
					Label("Sent \(result.applied.count) setting\(result.applied.count == 1 ? "" : "s") to the node.", systemImage: "checkmark.circle.fill")
						.foregroundColor(.green)
				} else if result.wasCancelled {
					Label("Import cancelled — sent \(result.applied.count) of \(result.applied.count + result.skipped.count) setting\(result.applied.count + result.skipped.count == 1 ? "" : "s").", systemImage: "xmark.circle.fill")
						.foregroundColor(.orange)
				} else {
					Label("Import stopped after a failure — sent \(result.applied.count) setting\(result.applied.count == 1 ? "" : "s") first.", systemImage: "exclamationmark.triangle.fill")
						.foregroundColor(.orange)
				}
				if result.rebooting {
					Text("Your radio is rebooting to apply LoRa/channel changes — reconnect to verify.")
						.font(.caption)
						.foregroundColor(.secondary)
				} else if !result.applied.isEmpty {
					Text("Reconnect to the node to confirm the changes were applied.")
						.font(.caption)
						.foregroundColor(.secondary)
				}
				// A destructive channel replace can half-complete: the node may already be on a different
				// primary channel/PSK even though the step is reported as failed.
				if result.failed?.kind == .channelURL {
					Text("Channel changes may have partially applied. Re-import Channels & LoRa to bring the node to a consistent state.")
						.font(.caption)
						.foregroundColor(.orange)
				}
			}
			if let failed = result.failed {
				Section("Failed") {
					VStack(alignment: .leading, spacing: 2) {
						Text(failed.kind.displayName)
						Text(failed.message).font(.caption).foregroundColor(.secondary)
					}
				}
			}
			if !result.applied.isEmpty {
				Section("Sent") {
					ForEach(result.applied, id: \.rawValue) { kind in
						Label(kind.displayName, systemImage: "checkmark").foregroundColor(.secondary)
					}
				}
			}
			if !result.skipped.isEmpty {
				Section("Not Applied") {
					ForEach(result.skipped, id: \.rawValue) { kind in
						Text(kind.displayName).foregroundColor(.secondary)
					}
				}
			}
		}
	}

	// MARK: Apply

	private func startImport() {
		guard importTask == nil else { return }   // no re-entrant / double apply
		canForceDismiss = false
		importTask = Task { await runImport() }
		// Liveness backstop: if the run is still going after a grace period (e.g. a single send stalled on
		// the transport), let the user out. The apply keeps running harmlessly in the background.
		Task {
			try? await Task.sleep(nanoseconds: 90 * 1_000_000_000)
			if isApplying { canForceDismiss = true }
		}
	}

	private func runImport() async {
		// Re-resolve the connected node at apply time so a device that dropped while the sheet was open
		// can't leave us acting on a stale/faulted entity.
		guard let node = connectedNode, let user = node.user else {
			phase = .done(DeviceProfileImportResult(
				failed: (kind: plan.items(for: selection).first?.kind ?? .owner, message: "No connected node.")
			))
			importTask = nil
			return
		}
		phase = .applying
		let gateway = AccessoryProfileApplyGateway(accessoryManager: accessoryManager, node: user)
		let result = await DeviceProfileImporter.apply(
			plan: plan,
			selection: selection,
			gateway: gateway,
			progress: { item, index, total in
				progress = ProgressState(title: item.kind.displayName, index: index, total: total)
			}
		)
		progress = nil
		importTask = nil
		canForceDismiss = false
		// Only publish the result if we're still the active apply (the user may have force-dismissed).
		if isApplying { phase = .done(result) }
	}

	// MARK: Copy

	private var sensitiveDetail: String {
		var parts: [String] = []
		if selection.contains(.security) { parts.append("your node's private key & admin keys".localized) }
		if selection.contains(.channelsAndLoRa) { parts.append("channel keys (PSKs)".localized) }
		if selection.contains(.network) { parts.append("Wi-Fi password".localized) }
		if plan.items(for: selection).contains(where: { $0.kind == .mqtt }) { parts.append("MQTT password".localized) }
		let list = parts.isEmpty ? "sensitive credentials".localized : parts.joined(separator: ", ")
		return String(format: "Includes %@. Only import files from a source you trust.".localized, list)
	}

	private var confirmationMessage: String {
		var lines: [String] = []
		if plan.containsSensitive(in: selection) {
			lines.append("This overwrites sensitive security material on the connected node.".localized)
		}
		if selection.contains(.security) {
			lines.append("It replaces this node's identity and admin keys, which can break existing direct messages.".localized)
		}
		if plan.willReboot(in: selection) {
			lines.append("The radio will reboot to apply LoRa/channel changes.".localized)
		}
		if lines.isEmpty {
			lines.append("Apply the selected configuration to the connected node?".localized)
		}
		return lines.joined(separator: " ")
	}
}
