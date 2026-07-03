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
					Button(isReviewing ? "Cancel" : "Done") { dismiss() }
						.disabled(isApplying)
				}
				if isReviewing {
					ToolbarItem(placement: .confirmationAction) {
						Button(isApplying ? "Importing…" : "Import") { isPresentingConfirm = true }
							.disabled(!canImport)
					}
				}
			}
			.confirmationDialog("Apply Configuration", isPresented: $isPresentingConfirm, titleVisibility: .visible) {
				Button("Apply Configuration", role: .destructive) { Task { await runImport() } }
				Button("Cancel", role: .cancel) { }
			} message: {
				Text(confirmationMessage)
			}
		}
		.interactiveDismissDisabled(isApplying)
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
					Label("Applied \(result.applied.count) setting\(result.applied.count == 1 ? "" : "s").", systemImage: "checkmark.circle.fill")
						.foregroundColor(.green)
				} else {
					Label("Import stopped after a failure.", systemImage: "exclamationmark.triangle.fill")
						.foregroundColor(.orange)
				}
				if result.rebooting {
					Text("Your radio is rebooting to apply LoRa/channel changes — reconnect to verify.")
						.font(.caption)
						.foregroundColor(.secondary)
				}
			}
			if let failed = result.failed {
				Section("Failed") {
					VStack(alignment: .leading, spacing: 2) {
						Text(failed.kind.rawValue)
						Text(failed.message).font(.caption).foregroundColor(.secondary)
					}
				}
			}
			if !result.applied.isEmpty {
				Section("Applied") {
					ForEach(result.applied, id: \.rawValue) { kind in
						Label(kind.rawValue, systemImage: "checkmark").foregroundColor(.secondary)
					}
				}
			}
			if !result.skipped.isEmpty {
				Section("Not Applied") {
					ForEach(result.skipped, id: \.rawValue) { kind in
						Text(kind.rawValue).foregroundColor(.secondary)
					}
				}
			}
		}
	}

	// MARK: Apply

	private func runImport() async {
		// Re-resolve the connected node at apply time so a device that dropped while the sheet was open
		// can't leave us acting on a stale/faulted entity.
		guard let node = connectedNode, let user = node.user else {
			phase = .done(DeviceProfileImportResult(
				failed: (kind: plan.items(for: selection).first?.kind ?? .owner, message: "No connected node.")
			))
			return
		}
		phase = .applying
		let gateway = AccessoryProfileApplyGateway(accessoryManager: accessoryManager, node: user)
		let result = await DeviceProfileImporter.apply(
			plan: plan,
			selection: selection,
			gateway: gateway,
			progress: { item, index, total in
				progress = ProgressState(title: item.summary, index: index, total: total)
			}
		)
		progress = nil
		phase = .done(result)
	}

	// MARK: Copy

	private var sensitiveDetail: String {
		var parts: [String] = []
		if selection.contains(.security) { parts.append("your node's private key & admin keys") }
		if selection.contains(.channelsAndLoRa) { parts.append("channel keys (PSKs)") }
		if selection.contains(.network) { parts.append("Wi-Fi password") }
		if plan.items(for: selection).contains(where: { $0.kind == .mqtt }) { parts.append("MQTT password") }
		let list = parts.isEmpty ? "sensitive credentials" : parts.joined(separator: ", ")
		return "Includes \(list). Only import files from a source you trust."
	}

	private var confirmationMessage: String {
		var lines: [String] = []
		if plan.containsSensitive(in: selection) {
			lines.append("This overwrites sensitive security material on the connected node.")
		}
		if selection.contains(.security) {
			lines.append("It replaces this node's identity and admin keys, which can break existing direct messages.")
		}
		if plan.willReboot(in: selection) {
			lines.append("The radio will reboot to apply LoRa/channel changes.")
		}
		if lines.isEmpty {
			lines.append("Apply the selected configuration to the connected node?")
		}
		return lines.joined(separator: " ")
	}
}
