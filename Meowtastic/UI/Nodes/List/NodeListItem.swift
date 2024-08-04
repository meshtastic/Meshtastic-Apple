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

	var body: some View {
		NavigationLink {
			NodeDetail(node: node)
		} label: {
			HStack(alignment: .top) {
				avatar

				VStack(alignment: .leading, spacing: 8) {
					name

					if node.isOnline {
						HStack(alignment: .center, spacing: 16) {
							signalStrength
							battery
						}
					}
					else {
						lastHeard
							.padding(.top, 8)
					}

					if node.positions?.count ?? 0 > 0 && connectedNode != node.num {
						distance
					}

					NodeIconListView(connectedNode: connectedNode, node: node)
						.padding(.top, 8)
				}
				.frame(alignment: .leading)
			}
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
			.lineLimit(2)
			.fontWeight(.medium)
			.font(.title2)
	}

	@ViewBuilder
	private var signalStrength: some View {
		if node.snr != 0, node.rssi != 0 {
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
		let deviceMetrics = node.telemetries?.filtered(
			using: NSPredicate(format: "metricsType == 0")
		)
		let mostRecent = deviceMetrics?.lastObject as? TelemetryEntity
		let batteryLevel = mostRecent?.batteryLevel
		let voltage = mostRecent?.voltage

		if let voltage, let batteryLevel, voltage > 0 || batteryLevel > 0 {
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

	@ViewBuilder
	private var distance: some View {
		if
			let currentCoordinate = locationManager.lastKnownLocation?.coordinate,
			let lastCoordinate = (node.positions?.lastObject as? PositionEntity)?.coordinate
		{
			let myLocation = CLLocation(
				latitude: currentCoordinate.latitude,
				longitude: currentCoordinate.longitude
			)

			HStack {
				let location = CLLocation(
					latitude: lastCoordinate.latitude,
					longitude: lastCoordinate.longitude
				)
				let distance = location.distance(from: myLocation)

				Image(systemName: "mappin.and.ellipse.circle.fill")
					.font(detailInfoFont)
					.foregroundColor(.gray)

				let formatter = MKDistanceFormatter()
				let distanceFormatted = formatter.string(fromDistance: Double(distance))

				Text(distanceFormatted)
					.font(detailInfoFont)
					.foregroundColor(.gray)
			}
		}
	}
}
