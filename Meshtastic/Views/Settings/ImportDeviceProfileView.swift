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
	/// The node's config as it stood just before the import, so verification can tell an unchanged
	/// section (the signature of a dropped write) from one the firmware normalized.
	@State private var configBeforeImport: [ImportItemKind: ImportPayload] = [:]
	@State private var importFinishedAt: Date?
	@State private var verification: DeviceProfileVerification?

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

			// Every import reboots, not just the LoRa/channel ones: the import runs inside a firmware edit
			// transaction and commit_edit_settings always saves and reboots (AdminModule.cpp:473-478).
			// `plan.willReboot` describes individual items, so it understates this and must not gate the warning.
			if !selection.isEmpty {
				Section {
					Label("Applying these settings reboots the radio; it will briefly disconnect.", systemImage: "arrow.clockwise.circle")
						.font(.caption)
						.foregroundColor(.orange)
				}
			}

			// The radio acks module configs it has no handler for, so an unsupported item would look like it
			// applied while being silently discarded. Report it here instead of sending it.
			if !plan.unsupported.isEmpty {
				Section("Not Supported by This Radio") {
					ForEach(plan.unsupported, id: \.item.kind) { entry in
						VStack(alignment: .leading, spacing: 2) {
							Label(entry.item.kind.displayName, systemImage: "slash.circle")
								.foregroundColor(.secondary)
							Text(unsupportedReason(entry.support))
								.font(.caption)
								.foregroundColor(.secondary)
						}
					}
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

	@ViewBuilder
	private func verificationRow(_ kind: ImportItemKind, _ outcome: VerificationOutcome) -> some View {
		VStack(alignment: .leading, spacing: 2) {
			switch outcome {
			case .applied:
				Label(kind.displayName, systemImage: "checkmark.circle.fill").foregroundColor(.green)
			case .likelyDropped:
				Label(kind.displayName, systemImage: "xmark.circle.fill").foregroundColor(.orange)
				Text("The radio still reports its previous value. Import this section again.")
					.font(.caption).foregroundColor(.secondary)
			case .inconclusive(let detail):
				Label(kind.displayName, systemImage: "questionmark.circle").foregroundColor(.secondary)
				Text(detail).font(.caption).foregroundColor(.secondary)
			case .notComparable(let reason):
				Label(kind.displayName, systemImage: "minus.circle").foregroundColor(.secondary)
				Text(reason).font(.caption).foregroundColor(.secondary)
			}
		}
	}

	private func unsupportedReason(_ support: FirmwareSupport) -> String {
		switch support {
		case .fromVersion(let version):
			return String(format: "Needs firmware %@ or newer.".localized, version)
		case .unimplemented:
			return "No firmware version supports importing this yet.".localized
		case .always:
			return ""
		}
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
					Text("Your radio is rebooting to save the imported settings — reconnect to verify.")
						.font(.caption)
						.foregroundColor(.secondary)
				} else if !result.applied.isEmpty {
					Text("Reconnect to the node to confirm the changes were applied.")
						.font(.caption)
						.foregroundColor(.secondary)
				}
				// The commit is what actually persists an import. If we could not confirm it reached the
				// radio, the node may have discarded everything and still be holding the edit transaction
				// open, which also blocks later config writes until it reboots.
				if result.commitUnconfirmed {
					Text("The node did not confirm saving these settings. Reconnect and check its configuration; you may need to import again.")
						.font(.caption)
						.foregroundColor(.orange)
				}
				// A destructive channel replace can half-complete: the node may already be on a different
				// primary channel/PSK even though the step is reported as failed.
				if result.failed?.kind == .channelURL {
					Text("Channel changes may have partially applied. Re-import Channels & LoRa to bring the node to a consistent state.")
						.font(.caption)
						.foregroundColor(.orange)
				}
			}
			// Applying MQTT or Serial config makes the firmware drop Bluetooth, so those two are sent last,
			// after everything else is safely saved. Over BLE the link is usually already gone by then.
			if !result.requiresReconnect.isEmpty {
				Section("Needs a Second Pass") {
					Text("Reconnect to the node and import these again — they could not be sent because applying them disconnects the radio.")
						.font(.caption)
						.foregroundColor(.secondary)
					ForEach(result.requiresReconnect, id: \.self) { kind in
						Label(kind.displayName, systemImage: "arrow.triangle.2.circlepath")
					}
				}
			}
			// The radio acks writes it silently discards, so "sent" is not "applied". Reading the config
			// back after the reboot is the only way to tell.
			Section("Check What Applied") {
				if let verification {
					if let unavailable = verification.unavailable {
						Text(unavailable).font(.caption).foregroundColor(.secondary)
					} else {
						ForEach(verification.outcomes, id: \.kind) { entry in
							verificationRow(entry.kind, entry.outcome)
						}
					}
				} else {
					Button {
						runVerification(result)
					} label: {
						Label("Verify Against the Radio", systemImage: "checkmark.shield")
					}
					.disabled(!canVerify)
					if !canVerify {
						Text("Available once the radio reconnects and sends its configuration back.")
							.font(.caption)
							.foregroundColor(.secondary)
					}
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
		// Snapshot what the radio holds now. The import cannot be verified from the sends alone: firmware
		// acks writes it discards, so only a later readback distinguishes applied from lost.
		let source = NodeProfileConfigSource(node: node, lastConfigRefresh: accessoryManager.lastConfigRefresh)
		configBeforeImport = Dictionary(
			uniqueKeysWithValues: plan.items(for: selection).compactMap { item in
				source.currentPayload(for: item.kind).map { (item.kind, $0) }
			}
		)
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
		importFinishedAt = Date()
		// Only publish the result if we're still the active apply (the user may have force-dismissed).
		if isApplying { phase = .done(result) }
	}

	/// True once the radio has sent a fresh configuration since the import finished.
	///
	/// Verifying before this would compare against the pre-import cache and report every item as lost,
	/// which is indistinguishable from a real total failure. So the action stays disabled until the
	/// radio has actually reported back after its reboot.
	private var canVerify: Bool {
		guard let importFinishedAt, let refreshed = accessoryManager.lastConfigRefresh else { return false }
		return refreshed >= importFinishedAt
	}

	private func runVerification(_ result: DeviceProfileImportResult) {
		guard let node = connectedNode else { return }
		let source = NodeProfileConfigSource(node: node,
											 lastConfigRefresh: accessoryManager.lastConfigRefresh)
		verification = DeviceProfileVerifier.verify(
			applied: result.applied,
			plan: plan,
			before: configBeforeImport,
			source: source,
			importFinishedAt: importFinishedAt ?? .distantFuture
		)
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
		// Unconditional: the transaction commit reboots regardless of which sections were picked.
		if !selection.isEmpty {
			lines.append("The radio will reboot to apply these changes.".localized)
		}
		if lines.isEmpty {
			lines.append("Apply the selected configuration to the connected node?".localized)
		}
		return lines.joined(separator: " ")
	}
}
