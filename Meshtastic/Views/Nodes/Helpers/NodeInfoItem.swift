//
//  NodeInfoItem.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/9/23.
//

import SwiftUI
import CoreLocation
import MapKit
@preconcurrency import SwiftData

/// Value-type hardware data captured while a user row is live.
///
/// Rendering the hardware section from this summary avoids retaining SwiftData user data in its
/// view hierarchy while still allowing the parent query to observe later user updates.
struct NodeInfoItemSummary: Equatable {
	let hwModel: String?
	let hwModelId: Int64

	@MainActor init?(user: UserEntity) {
		guard user.modelContext != nil, !user.isDeleted else { return nil }

		hwModel = user.hwModel
		hwModelId = Int64(user.hwModelId)
	}
}

struct NodeInfoItem: View {

	@Query private var users: [UserEntity]

	init(nodeNum: Int64) {
		_users = Query(filter: #Predicate<UserEntity> { $0.num == nodeNum })
	}

	var body: some View {
		// Query the current user by node number instead of dereferencing `NodeInfoEntity.user`.
		// The relationship can retain an invalid backing object after a store reset, whereas this
		// query drops deleted users and re-renders when live hardware metadata changes.
		if let user = users.first,
			let summary = NodeInfoItemSummary(user: user) {
			NodeInfoHardwareSection(summary: summary)
				.id(summary.hwModelId)
		} else {
			EmptyView()
		}
	}
}

/// The hardware query is initialized from the summary's value data rather than a live node
/// relationship, so the detail can continue rendering safely after the node is detached.
private struct NodeInfoHardwareSection: View {
	let summary: NodeInfoItemSummary
	@Query private var hardware: [DeviceHardwareEntity]
	@EnvironmentObject private var meshtasticAPI: MeshtasticAPI

	init(summary: NodeInfoItemSummary) {
		self.summary = summary
		let hardwareModel = summary.hwModelId
		_hardware = Query(
			filter: #Predicate<DeviceHardwareEntity> { $0.hwModel == hardwareModel },
			sort: [SortDescriptor(\.hwModelSlug)]
		)
	}

	private var hasDevice: Bool {
		hardwarePresentation != nil
	}

	private var isActivelySupported: Bool {
		hardwarePresentation?.activelySupported ?? false
	}

	private var hardwarePresentation: HardwareCatalogPresentation? {
		HardwareCatalogResolver.presentation(for: summary.hwModelId, in: hardware)
	}

	private var supportRosette: some View {
		Image(systemName: isActivelySupported ? "checkmark.seal.fill" : "xmark.seal.fill")
			.foregroundStyle(isActivelySupported ? .green : .secondary)
	}

	private var modelName: String {
		hardwarePresentation?.displayName ?? summary.hwModel ?? "Unknown"
	}

	private var isPortduino: Bool {
		summary.hwModel == "PORTDUINO"
	}

	private var supportLevel: SupportLevel? {
		hardwarePresentation?.supportLevel
	}

	private var hardwareDescription: String {
		if let supportLevel {
			return supportLevel.description
		}
		return hasDevice
			? "This hardware model has multiple indistinguishable variants."
			: "Hardware model information is unavailable."
	}

	private var sectionTitle: String {
		if summary.hwModel == "UNSET" { return "Hardware" }
		if isPortduino { return "Community Hardware" }
		guard let supportLevel else { return "Hardware" }
		switch supportLevel {
		case .flagship:
			return "Supported Hardware"
		case .niche:
			return "Niche Hardware"
		case .legacy:
			return "Legacy Hardware"
		case .discontinued:
			return "Discontinued Hardware"
		}
	}

	var body: some View {
		Section(sectionTitle) {
			if summary.hwModel == "UNSET" {
				// MARK: - Unset / Incomplete
				HStack {
					Image(systemName: "flipphone")
						.symbolRenderingMode(.hierarchical)
						.font(.title2)
						.foregroundStyle(.secondary)
					Text("Incomplete")
						.foregroundStyle(.secondary)
				}
			} else if meshtasticAPI.isLoadingDeviceList && !hasDevice {
				// MARK: - Loading
				HStack {
					ProgressView()
					Text("Loading hardware info…")
						.font(.subheadline)
						.foregroundStyle(.secondary)
				}
				.listRowSeparator(.hidden)
			} else if hasDevice && supportLevel == .flagship {
				// MARK: - Flagship Device (Hero Layout)
				VStack(spacing: 12) {
					ZStack(alignment: .bottomTrailing) {
						DeviceHardwareImage(hwId: Int32(summary.hwModelId))
							.frame(maxWidth: .infinity)
							.frame(height: 200)
							.cornerRadius(12)
						supportRosette
							.font(.title2)
							.padding(8)
					}
					Text(modelName)
						.font(.headline)
						.frame(maxWidth: .infinity, alignment: .center)
				}
				.listRowSeparator(.hidden)
			} else if hasDevice && (supportLevel == .niche || supportLevel == .legacy) {
				// MARK: - Niche / Legacy Device
				HStack(spacing: 16) {
					DeviceHardwareImage(hwId: Int32(summary.hwModelId))
						.frame(width: 60, height: 60)
						.cornerRadius(8)
						.opacity(0.6)
					Text(modelName)
						.font(.subheadline)
						.foregroundStyle(.secondary)
					Spacer()
					supportRosette
						.font(.title2)
				}
				.listRowSeparator(.hidden)
			} else if isPortduino {
				// MARK: - Portduino / Linux (community-supported, no firmware)
				HStack(spacing: 16) {
					DeviceHardwareImage(platformioTarget: "native")
						.frame(width: 60, height: 60)
						.cornerRadius(8)
					VStack(alignment: .leading, spacing: 4) {
						Text(modelName)
							.font(.subheadline)
							.foregroundStyle(.secondary)
						Text("Community supported Linux device.")
							.font(.caption)
							.foregroundStyle(.tertiary)
					}
					Spacer()
					supportRosette
						.font(.title2)
				}
				.listRowSeparator(.hidden)
			} else {
				// MARK: - Discontinued / Unknown Device
				HStack(spacing: 16) {
					if hardwarePresentation?.activelySupported == nil {
						Image(systemName: "questionmark.circle.fill")
							.font(.system(size: 40))
							.foregroundStyle(.secondary)
					} else {
						supportRosette
							.font(.system(size: 40))
					}
					VStack(alignment: .leading, spacing: 4) {
						Text(modelName)
							.font(.subheadline)
							.foregroundStyle(.secondary)
						Text(hardwareDescription)
							.font(.caption)
							.foregroundStyle(.tertiary)
					}
					Spacer()
				}
				.listRowSeparator(.hidden)
			}
		}
		.accessibilityElement(children: .combine)

		// Device links section (shown only when device has a platformioTarget)
		if let target = hardwarePresentation?.platformioTarget {
			DeviceLinksSection(platformioTarget: target)
		}
	}
}
