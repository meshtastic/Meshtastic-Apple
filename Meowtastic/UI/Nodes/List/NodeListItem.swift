import CoreLocation
import MapKit
import SwiftUI

struct NodeListItem: View {
	@ObservedObject
	var node: NodeInfoEntity

	var connected: Bool
	var connectedNode: Int64
	var modemPreset: ModemPresets = ModemPresets(rawValue: UserDefaults.modemPreset) ?? ModemPresets.longFast

	private let detailInfoFont = Font.system(size: 14, weight: .regular, design: .rounded)
	private let detailIconSize: CGFloat = 16

	@Environment(\.colorScheme)
	private var colorScheme: ColorScheme
	@EnvironmentObject
	private var locationManager: LocationManager

	private var isSignal: Bool {
		node.snr != 0 && node.rssi != 0
	}
	private var isBattery: Bool {
		let deviceMetrics = node.telemetries?.filtered(
			using: NSPredicate(format: "metricsType == 0")
		)
		let mostRecent = deviceMetrics?.lastObject as? TelemetryEntity
		let batteryLevel = mostRecent?.batteryLevel
		let voltage = mostRecent?.voltage

		if let voltage, let batteryLevel, voltage > 0 || batteryLevel > 0 {
			return true
		}

		return false
	}

	var body: some View {
		NavigationLink {
			NodeDetail(node: node)
		} label: {
			HStack(alignment: .top) {
				avatar

				VStack(alignment: .leading, spacing: 8) {
					name

					if node.isOnline, isSignal || isBattery {
						HStack(alignment: .center, spacing: 16) {
							signalStrength
							battery
						}
					}

					lastHeard

					NodeIconListView(connectedNode: connectedNode, node: node)
						.padding(.vertical, 4)
						.padding(.horizontal, 12)
						.overlay(
							RoundedRectangle(cornerRadius: 16)
								.stroke(.gray, lineWidth: 1)
						)
						.clipShape(
							RoundedRectangle(cornerRadius: 16)
						)
				}
				.frame(maxWidth: .infinity, alignment: .leading)
			}
			.padding(.vertical, 8)
		}
	}

	@ViewBuilder
	private var avatar: some View {
		ZStack(alignment: .top) {
			AvatarNode(
				node,
				size: 64
			)
			.padding([.top, .bottom, .trailing], 10)

			if connected {
				HStack(spacing: 0) {
					Spacer()
					Image(systemName: "antenna.radiowaves.left.and.right.circle.fill")
						.font(.system(size: 24))
						.foregroundColor(colorScheme == .dark ? .white : .gray)
						.background(
							Circle()
								.foregroundColor(colorScheme == .dark ? .black : .white)
						)
				}
			}
			else if node.favorite {
				HStack(spacing: 0) {
					Spacer()
					Image(systemName: "star.circle.fill")
						.font(.system(size: 24))
						.foregroundColor(colorScheme == .dark ? .white : .gray)
						.background(
							Circle()
								.foregroundColor(colorScheme == .dark ? .black : .white)
						)
				}
			}
		}
		.frame(width: 80, height: 80)
	}

	@ViewBuilder
	private var name: some View {
		Text(node.user?.longName ?? "Unknown")
			.fontWeight(.medium)
			.font(.title2)
			.lineLimit(1)
			.minimumScaleFactor(0.5)
	}

	@ViewBuilder
	private var signalStrength: some View {
		if isSignal {
			LoraSignalView(
				snr: node.snr,
				rssi: node.rssi,
				preset: modemPreset
			)
		}
		else {
			Color.clear
		}
	}

	@ViewBuilder
	private var battery: some View {
		if isBattery {
			BatteryView(
				node: node
			)
		}
		else {
			Color.clear
		}
	}

	@ViewBuilder
	private var lastHeard: some View {
		if let lastHeard = node.lastHeard, lastHeard.timeIntervalSince1970 > 0 {
			HStack {
				Image(systemName: node.isOnline ? "clock.badge.checkmark.fill" : "clock.badge.exclamationmark.fill")
					.font(detailInfoFont)
					.foregroundColor(node.isOnline ? .green : .gray)

				Text(lastHeard.relative())
					.font(detailInfoFont)
					.foregroundColor(.gray)
			}
		}
		else {
			HStack {
				Image(systemName: "clock.badge.questionmark.fill")
					.font(detailInfoFont)
					.foregroundColor(node.isOnline ? .green : .gray)

				Text("No idea")
					.font(detailInfoFont)
					.foregroundColor(.gray)
			}
		}
	}
}
