import Foundation
import SwiftUI

struct NodeIconListView: View {
	var connectedNode: Int64
	var small = false

	@ObservedObject
	var node: NodeInfoEntity

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
	private let detailInfoIconFont = Font.system(size: 14, weight: .regular, design: .rounded)
	private let detailInfoTextFont = Font.system(size: 12, weight: .light, design: .rounded)
	private var detailIconSize: CGFloat {
		small ? 12 : 16
	}
	private var detailIconSpacing: CGFloat {
		small ? 6 : 8
	}

	@Environment(\.colorScheme)
	private var colorScheme: ColorScheme

	@ViewBuilder
	var body: some View {
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

					Image(systemName: "wifi.circle")
						.font(detailInfoIconFont)
						.foregroundColor(.gray)
						.frame(width: detailIconSize)
				}
				else {
					divider

					Image(systemName: "\(node.hopsAway).circle")
						.font(detailInfoIconFont)
						.foregroundColor(.gray)
						.frame(width: detailIconSize)
				}
			}

			if !small, node.hasTraceRoutes {
				divider

				Image(systemName: "signpost.right.and.left")
					.font(detailInfoIconFont)
					.foregroundColor(.gray)
					.frame(width: detailIconSize)
			}

			if node.hasPositions {
				divider

				Image(systemName: "mappin.and.ellipse")
					.font(detailInfoIconFont)
					.foregroundColor(.gray)
					.frame(width: detailIconSize)
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

				Image(systemName: "cloud.sun.rain")
					.font(detailInfoIconFont)
					.foregroundColor(.gray)
					.frame(width: detailIconSize)

				if !small, let nodeEnvironment {
					let tempFormatted = String(format: "%.0f", nodeEnvironment.temperature) + "°C"

					Text(tempFormatted)
						.font(detailInfoTextFont)
						.foregroundColor(.gray)
				}
			}
		}
	}

	@ViewBuilder
	private var divider: some View {
		if !small {
			Divider()
				.frame(height: 16)
				.foregroundColor(.gray)
		}
	}
}
