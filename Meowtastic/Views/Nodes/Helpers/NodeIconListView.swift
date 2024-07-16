import Foundation
import SwiftUI

struct NodeIconListView: View {
	var connectedNode: Int64
	var small = false

	@ObservedObject
	var node: NodeInfoEntity

	private let detailInfoFont = Font.system(size: 14, weight: .regular, design: .rounded)
	private var detailIconSize: CGFloat {
		small ? 12 : 16
	}
	private var detailIconSpacing: CGFloat {
		small ? 6 : 12
	}

	@Environment(\.colorScheme)
	private var colorScheme: ColorScheme

	@ViewBuilder
	var body: some View {
		HStack(alignment: .center, spacing: detailIconSpacing) {
			if !small, let role = DeviceRoles(rawValue: Int(node.user?.role ?? 0))?.systemName {
				Image(systemName: role)
					.font(detailInfoFont)
					.foregroundColor(.gray)
					.frame(width: detailIconSize)
			}

			if connectedNode != node.num {
				if node.viaMqtt {
					Image(systemName: "network")
						.font(detailInfoFont)
						.foregroundColor(.gray)
						.frame(width: detailIconSize)
				}

				if node.hopsAway == 0 {
					Image(systemName: "wifi.circle")
						.font(detailInfoFont)
						.foregroundColor(.gray)
						.frame(width: detailIconSize)
				}
				else {
					Image(systemName: "\(node.hopsAway).circle")
						.font(detailInfoFont)
						.foregroundColor(.gray)
						.frame(width: detailIconSize)
				}
			}

			if !small, node.hasTraceRoutes {
				Image(systemName: "signpost.right.and.left")
					.font(detailInfoFont)
					.foregroundColor(.gray)
					.frame(width: detailIconSize)
			}

			if node.hasPositions {
				Image(systemName: "mappin.and.ellipse")
					.font(detailInfoFont)
					.foregroundColor(.gray)
					.frame(width: detailIconSize)
			}

			if !small, node.isStoreForwardRouter {
				Image(systemName: "envelope.arrow.triangle.branch")
					.font(detailInfoFont)
					.foregroundColor(.gray)
					.frame(width: detailIconSize)
			}

			if !small, node.hasDeviceMetrics {
				Image(systemName: "ruler")
					.font(detailInfoFont)
					.foregroundColor(.gray)
					.frame(width: detailIconSize)
			}

			if !small, node.hasDetectionSensorMetrics {
				Image(systemName: "sensor")
					.font(detailInfoFont)
					.foregroundColor(.gray)
					.frame(width: detailIconSize)
			}

			if !small, node.hasEnvironmentMetrics {
				Image(systemName: "cloud.sun.rain")
					.font(detailInfoFont)
					.foregroundColor(.gray)
					.frame(width: detailIconSize)
			}
		}
	}
}
