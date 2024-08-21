import CoreLocation
import Foundation
import SwiftUI

struct NodeIconListView: View {
	var connectedNode: Int64
	var small = false

	@ObservedObject
	var node: NodeInfoEntity

	@EnvironmentObject
	private var locationManager: LocationManager

	private var nodePosition: PositionEntity? {
		node.positions?.lastObject as? PositionEntity
	}
	private var nodeEnvironment: TelemetryEntity? {
		node
			.telemetries?
			.filtered(
				using: NSPredicate(format: "metricsType == 1")
			)
			.lastObject as? TelemetryEntity
	}
	private var detailIconSize: CGFloat {
		small ? 12 : 16
	}
	private var detailIconSpacing: CGFloat {
		6
	}

	@Environment(\.colorScheme)
	private var colorScheme: ColorScheme

	@ViewBuilder
	var body: some View {
		let detailInfoIconFont = Font.system(size: small ? 12 : 14, weight: .regular, design: .rounded)
		let detailInfoTextFont = Font.system(size: small ? 10 : 12, weight: .semibold, design: .rounded)
		let detailHopsIconFont = Font.system(size: small ? 8 : 10, weight: .semibold, design: .rounded)

		HStack(alignment: .center, spacing: detailIconSpacing) {
			if !small, let role = DeviceRoles(rawValue: Int(node.user?.role ?? 0))?.systemName {
				Image(systemName: role)
					.font(detailInfoIconFont)
					.foregroundColor(.gray)
					.frame(width: detailIconSize)
			}

			if connectedNode != node.num {
				if node.viaMqtt {
					divider

					Image(systemName: "network")
						.font(detailInfoIconFont)
						.foregroundColor(.gray)
						.frame(width: detailIconSize)
				}

				if node.hopsAway == 0 {
					divider

					Image(systemName: "eye")
						.font(detailInfoIconFont)
						.foregroundColor(.gray)
						.frame(width: detailIconSize)
				}
				else {
					divider

					ZStack(alignment: .top) {
						let badgeOffset: CGFloat = 7

						Image(systemName: "arrowshape.bounce.forward")
							.font(detailInfoIconFont)
							.foregroundColor(.gray)
							.frame(width: detailIconSize)
							.padding(.leading, badgeOffset)

						HStack(spacing: 0) {
							Image(systemName: "\(node.hopsAway).circle")
								.font(detailHopsIconFont)
								.foregroundColor(.gray)
								.background(Color.listBackground(for: colorScheme))
								.clipShape(
									Circle()
								)

							Spacer()
						}
						.frame(width: detailIconSize + badgeOffset)
					}
				}
			}

			if !small, node.hasTraceRoutes {
				divider

				Image(systemName: "signpost.right.and.left")
					.font(detailInfoIconFont)
					.foregroundColor(.gray)
					.frame(width: detailIconSize)
			}

			if !small, node.hasPositions {
				divider

				if
					!small,
					let currentCoordinate = locationManager.lastKnownLocation?.coordinate,
					let lastCoordinate = (node.positions?.lastObject as? PositionEntity)?.coordinate
				{
					let myLocation = CLLocation(
						latitude: currentCoordinate.latitude,
						longitude: currentCoordinate.longitude
					)
					let location = CLLocation(
						latitude: lastCoordinate.latitude,
						longitude: lastCoordinate.longitude
					)
					let distance = location.distance(from: myLocation) / 1000 // km
					let distanceFormatted = String(format: "%.0f", distance) + "km"

					Image(systemName: "mappin.and.ellipse")
						.font(detailInfoIconFont)
						.foregroundColor(.gray)

					Text(distanceFormatted)
						.font(detailInfoTextFont)
						.lineLimit(1)
						.minimumScaleFactor(0.7)
						.foregroundColor(.gray)
				}
				else {
					Image(systemName: "mappin.and.ellipse")
						.font(detailInfoIconFont)
						.foregroundColor(.gray)
						.frame(width: detailIconSize)
				}
			}

			if !small, node.isStoreForwardRouter {
				divider

				Image(systemName: "envelope.arrow.triangle.branch")
					.font(detailInfoIconFont)
					.foregroundColor(.gray)
					.frame(width: detailIconSize)
			}

			if !small, node.hasDetectionSensorMetrics {
				divider

				Image(systemName: "sensor")
					.font(detailInfoIconFont)
					.foregroundColor(.gray)
					.frame(width: detailIconSize)
			}

			if !small, node.hasEnvironmentMetrics {
				divider

				if !small, let nodeEnvironment {
					let temp = nodeEnvironment.temperature
					let tempFormatted = String(format: "%.0f", temp) + "°C"
					if temp < 10 {
						Image(systemName: "thermometer.low")
							.font(detailInfoIconFont)
							.foregroundColor(.gray)
					}
					else if temp < 25 {
						Image(systemName: "thermometer.medium")
							.font(detailInfoIconFont)
							.foregroundColor(.gray)
					}
					else {
						Image(systemName: "thermometer.high")
							.font(detailInfoIconFont)
							.foregroundColor(.gray)
					}

					Text(tempFormatted)
						.font(detailInfoTextFont)
						.lineLimit(1)
						.minimumScaleFactor(0.7)
						.foregroundColor(.gray)
				}
				else {
					Image(systemName: "thermometer.variable")
						.font(detailInfoIconFont)
						.foregroundColor(.gray)
						.frame(width: detailIconSize)
				}
			}

			if small, !node.isOnline {
				divider

				Image(systemName: "antenna.radiowaves.left.and.right.slash")
					.font(detailInfoIconFont)
					.foregroundColor(.gray)
					.frame(width: detailIconSize)

			}
		}
	}

	@ViewBuilder
	private var divider: some View {
		Divider()
			.frame(height: small ? 10 : 16)
			.foregroundColor(.gray)
	}
}
