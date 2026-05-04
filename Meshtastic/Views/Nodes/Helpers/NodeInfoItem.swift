//
//  NodeInfoItem.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/9/23.
//

import SwiftUI
import CoreLocation
import MapKit
import SwiftData

struct NodeInfoItem: View {

	@Bindable var node: NodeInfoEntity
	@Query var hardware: [DeviceHardwareEntity]
	@EnvironmentObject var meshtasticAPI: MeshtasticAPI

	init(node: NodeInfoEntity) {
		self.node = node
		let hwModel = Int64(node.user?.hwModelId ?? 0)
		_hardware = Query(filter: #Predicate<DeviceHardwareEntity> { hw in
			hw.hwModel == hwModel
		}, sort: [SortDescriptor(\.hwModelSlug)])
	}

	private var hasDevice: Bool {
		hardware.first != nil
	}

	private var isActivelySupported: Bool {
		hardware.first?.activelySupported ?? false
	}

	private var supportRosette: some View {
		Image(systemName: isActivelySupported ? "checkmark.seal.fill" : "xmark.seal.fill")
			.foregroundStyle(isActivelySupported ? .green : .secondary)
	}

	private var modelName: String {
		node.user?.hwDisplayName ?? node.user?.hwModel ?? "Unknown"
	}

	private var supportLevel: SupportLevel {
		guard let device = hardware.first else { return .discontinued }
		return SupportLevel(rawValue: device.supportLevel) ?? .discontinued
	}

	private var sectionTitle: String {
		if node.user?.hwModel == "UNSET" { return "Hardware" }
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
		if let user = node.user {
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
					Text(modelName)
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
					Text(modelName)
						.font(.subheadline)
						.foregroundStyle(.secondary)
					Spacer()
					supportRosette
						.font(.title2)
				}
				.listRowSeparator(.hidden)
			} else {
				// MARK: - Discontinued / Unknown Device
				HStack(spacing: 16) {
					supportRosette
						.font(.system(size: 40))
					VStack(alignment: .leading, spacing: 4) {
						Text(modelName)
							.font(.subheadline)
							.foregroundStyle(.secondary)
						Text(supportLevel.description)
							.font(.caption)
							.foregroundStyle(.tertiary)
					}
					Spacer()
				}
				.listRowSeparator(.hidden)
			}
		}
		}
		.accessibilityElement(children: .combine)
	}
}
