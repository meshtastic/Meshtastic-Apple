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

struct NodeInfoItem: View {

	@Bindable var node: NodeInfoEntity
	@Query var hardware: [DeviceHardwareEntity]
	@EnvironmentObject var meshtasticAPI: MeshtasticAPI
	private let hardwareModel: Int64

	init(node: NodeInfoEntity) {
		self.node = node
		let hwModel = Int64(node.liveUser?.hwModelId ?? 0)
		hardwareModel = hwModel
		_hardware = Query(filter: #Predicate<DeviceHardwareEntity> { hw in
			hw.hwModel == hwModel
		}, sort: [SortDescriptor(\.hwModelSlug)])
	}

	private var hasDevice: Bool {
		hardwarePresentation != nil
	}

	private var isActivelySupported: Bool {
		hardwarePresentation?.activelySupported ?? false
	}

	private var hardwarePresentation: HardwareCatalogPresentation? {
		HardwareCatalogResolver.presentation(for: hardwareModel, in: hardware)
	}

	private var supportRosette: some View {
		Image(systemName: isActivelySupported ? "checkmark.seal.fill" : "xmark.seal.fill")
			.foregroundStyle(isActivelySupported ? .green : .secondary)
	}

	private func modelName(for user: UserEntity) -> String {
		hardwarePresentation?.displayName ?? user.hwModel ?? "Unknown"
	}

	private func isPortduino(_ user: UserEntity) -> Bool {
		user.hwModel == "PORTDUINO"
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

	private func sectionTitle(for user: UserEntity) -> String {
		if user.hwModel == "UNSET" { return "Hardware" }
		if isPortduino(user) { return "Community Hardware" }
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
		if let user = node.liveUser {
			Section(sectionTitle(for: user)) {
				if user.hwModel == "UNSET" {
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
							DeviceHardwareImage(hwId: user.hwModelId)
								.frame(maxWidth: .infinity)
								.frame(height: 200)
								.cornerRadius(12)
							supportRosette
								.font(.title2)
								.padding(8)
						}
						Text(modelName(for: user))
							.font(.headline)
							.frame(maxWidth: .infinity, alignment: .center)
					}
					.listRowSeparator(.hidden)
				} else if hasDevice && (supportLevel == .niche || supportLevel == .legacy) {
					// MARK: - Niche / Legacy Device
					HStack(spacing: 16) {
						DeviceHardwareImage(hwId: user.hwModelId)
							.frame(width: 60, height: 60)
							.cornerRadius(8)
							.opacity(0.6)
						Text(modelName(for: user))
							.font(.subheadline)
							.foregroundStyle(.secondary)
						Spacer()
						supportRosette
							.font(.title2)
					}
					.listRowSeparator(.hidden)
				} else if isPortduino(user) {
					// MARK: - Portduino / Linux (community-supported, no firmware)
					HStack(spacing: 16) {
						DeviceHardwareImage(platformioTarget: "native")
							.frame(width: 60, height: 60)
							.cornerRadius(8)
						VStack(alignment: .leading, spacing: 4) {
							Text(modelName(for: user))
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
							Text(modelName(for: user))
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
}
