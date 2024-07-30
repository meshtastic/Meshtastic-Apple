import SwiftUI
import CoreLocation

struct NodeListItem: View {
	@ObservedObject
	var node: NodeInfoEntity

	var connected: Bool
	var connectedNode: Int64
	var modemPreset: ModemPresets = ModemPresets(rawValue: UserDefaults.modemPreset) ?? ModemPresets.longFast
	var showBattery: Bool = false

	private let detailInfoFont = Font.system(size: 14, weight: .regular, design: .rounded)
	private let detailIconSize: CGFloat = 16

	@Environment(\.colorScheme)
	private var colorScheme: ColorScheme

	var body: some View {
		NavigationLink(value: node) {
			HStack(alignment: .top) {
				avatar

				VStack(alignment: .leading, spacing: 4) {
					name
					signalStrength
					battery

					lastHeard
						.padding(.top, 8)

					if node.positions?.count ?? 0 > 0 && connectedNode != node.num {
						distance
					}

					NodeIconListView(connectedNode: connectedNode, node: node)
						.padding(.top, 8)
				}
				.frame(maxWidth: .infinity, alignment: .leading)
			}
		}
	}

	@ViewBuilder
	private var avatar: some View {
		ZStack(alignment: .top) {
			Avatar(
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
		Text(node.user?.longName ?? "unknown".localized)
			.lineLimit(1)
			.fontWeight(.medium)
			.font(.title2)
			.minimumScaleFactor(0.5)
			.frame(width: .infinity)
	}

	@ViewBuilder
	private var signalStrength: some View {
		if node.viaMqtt || node.hopsAway > 0 || node.snr == 0 {
			EmptyView()
		}
		else {
			LoraSignalView(
				snr: node.snr,
				rssi: node.rssi,
				preset: modemPreset,
				withLabels: true
			)
		}
	}

	@ViewBuilder
	private var battery: some View {
		if !showBattery {
			EmptyView()
		}
		else {
			BatteryView(
				node: node,
				withLabels: true
			)
		}
	}

	@ViewBuilder
	private var lastHeard: some View {
		HStack {
			Image(systemName: node.isOnline ? "info.circle.fill" : "moon.circle.fill")
				.font(detailInfoFont)
				.foregroundColor(node.isOnline ? .green : .gray)

			LastHeardText(lastHeard: node.lastHeard)
				.font(detailInfoFont)
				.foregroundColor(.gray)
		}
	}

	@ViewBuilder
	private var distance: some View {
		HStack {
			if let lastPostion = node.positions?.lastObject as? PositionEntity,
			   let currentLocation = LocationsHandler.shared.locationsArray.last
			{
				let myCoord = CLLocation(
					latitude: currentLocation.coordinate.latitude,
					longitude: currentLocation.coordinate.longitude
				)

				if lastPostion.nodeCoordinate != nil
					&& myCoord.coordinate.longitude != LocationsHandler.DefaultLocation.longitude
					&& myCoord.coordinate.latitude != LocationsHandler.DefaultLocation.latitude
				{
					let nodeCoord = CLLocation(
						latitude: lastPostion.nodeCoordinate!.latitude,
						longitude: lastPostion.nodeCoordinate!.longitude
					)
					let metersAway = nodeCoord.distance(from: myCoord)

					Image(systemName: "mappin.and.ellipse.circle.fill")
						.font(detailInfoFont)
						.foregroundColor(.gray)

					DistanceText(meters: metersAway)
						.font(detailInfoFont)
						.foregroundColor(.gray)
				}
			}
		}
	}
}
