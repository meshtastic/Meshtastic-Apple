//
//  MapLegend.swift
//  Meshtastic
//
//  Implements a map legend overlay that explains the visual elements
//  displayed on the map (issue #924).
//

import SwiftUI

struct MapLegendItem: View {
	let symbol: AnyView
	let title: String
	let subtitle: String?

	init(symbol: AnyView, title: String, subtitle: String? = nil) {
		self.symbol = symbol
		self.title = title
		self.subtitle = subtitle
	}

	var body: some View {
		HStack(spacing: 12) {
			symbol
				.frame(width: 40, height: 40)
			VStack(alignment: .leading, spacing: 2) {
				Text(title)
					.font(.subheadline)
					.fontWeight(.medium)
				if let subtitle {
					Text(subtitle)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}
			Spacer()
		}
	}
}

struct MapLegend: View {
	@Environment(\.dismiss) private var dismiss
	let isMeshMap: Bool

	var body: some View {
		NavigationStack {
			List {
				nodeSection
				if isMeshMap {
					waypointSection
				}
				precisionSection
				if !isMeshMap {
					historySection
				}
				routeSection
				if isMeshMap {
					convexHullSection
				}
			}
			.navigationTitle("Map Legend")
			.navigationBarTitleDisplayMode(.inline)
		}
#if targetEnvironment(macCatalyst)
		Spacer()
		Button {
			dismiss()
		} label: {
			Label("Close", systemImage: "xmark")
		}
		.buttonStyle(.bordered)
		.buttonBorderShape(.capsule)
		.controlSize(.large)
		.padding(.bottom)
#endif
	}

	// MARK: - Sections

	private var nodeSection: some View {
		Section {
			MapLegendItem(
				symbol: AnyView(onlineNodeSymbol),
				title: String(localized: "Online Node"),
				subtitle: String(localized: "Node heard within the last 2 hours. Shown with a pulsing ring on the map.")
			)
			MapLegendItem(
				symbol: AnyView(offlineNodeSymbol),
				title: String(localized: "Offline Node"),
				subtitle: String(localized: "Node not heard recently. Shown without a pulsing ring on the map.")
			)
			MapLegendItem(
				symbol: AnyView(sensorNodeSymbol),
				title: String(localized: "Detection Sensor"),
				subtitle: String(localized: "Node with an active detection sensor module.")
			)
		} header: {
			Text("Nodes")
		}
	}

	private var waypointSection: some View {
		Section {
			MapLegendItem(
				symbol: AnyView(waypointSymbol),
				title: String(localized: "Waypoint"),
				subtitle: String(localized: "A shared point of interest. Long-press the map to create one.")
			)
		} header: {
			Text("Waypoints")
		}
	}

	private var precisionSection: some View {
		Section {
			MapLegendItem(
				symbol: AnyView(precisionCircleSymbol),
				title: String(localized: "Position Precision Circle"),
				subtitle: String(localized: "Indicates reduced GPS precision. The node is somewhere within the shaded area.")
			)
		} header: {
			Text("Position Precision")
		}
	}

	private var historySection: some View {
		Section {
			MapLegendItem(
				symbol: AnyView(historyPointSymbol),
				title: String(localized: "Position History Point"),
				subtitle: String(localized: "A previous position report for this node.")
			)
			MapLegendItem(
				symbol: AnyView(historyArrowSymbol),
				title: String(localized: "Position with Heading"),
				subtitle: String(localized: "A previous position report showing the direction of travel.")
			)
		} header: {
			Text("Position History")
		}
	}

	private var routeSection: some View {
		Section {
			MapLegendItem(
				symbol: AnyView(routeStartSymbol),
				title: String(localized: "Route Start"),
				subtitle: nil
			)
			MapLegendItem(
				symbol: AnyView(routeEndSymbol),
				title: String(localized: "Route End"),
				subtitle: nil
			)
			MapLegendItem(
				symbol: AnyView(routeLineSymbol),
				title: String(localized: "Route Line"),
				subtitle: String(localized: "Dashed line showing a recorded route path.")
			)
		} header: {
			Text("Routes")
		}
	}

	private var convexHullSection: some View {
		Section {
			MapLegendItem(
				symbol: AnyView(convexHullSymbol),
				title: String(localized: "Convex Hull"),
				subtitle: String(localized: "An outline enclosing all LoRa node positions on the mesh.")
			)
		} header: {
			Text("Mesh Coverage")
		}
	}

	// MARK: - Symbols

	private var onlineNodeSymbol: some View {
		ZStack {
			Circle()
				.fill(Color.green.opacity(0.3))
				.frame(width: 38, height: 38)
			CircleText(text: "ON", color: .green, circleSize: 28)
		}
	}

	private var offlineNodeSymbol: some View {
		CircleText(text: "OFF", color: .gray, circleSize: 28)
	}

	private var sensorNodeSymbol: some View {
		ZStack {
			Circle()
				.fill(Color.blue)
				.frame(width: 28, height: 28)
			Image(systemName: "sensor.fill")
				.font(.system(size: 14))
				.foregroundStyle(.white)
		}
	}

	private var waypointSymbol: some View {
		CircleText(text: "📍", color: .orange, circleSize: 28)
	}

	private var precisionCircleSymbol: some View {
		ZStack {
			Circle()
				.fill(Color.blue.opacity(0.25))
				.frame(width: 36, height: 36)
			Circle()
				.strokeBorder(Color.white, lineWidth: 1)
				.frame(width: 36, height: 36)
			Circle()
				.fill(Color.blue)
				.frame(width: 8, height: 8)
		}
	}

	private var historyPointSymbol: some View {
		ZStack {
			Circle()
				.fill(Color.blue)
				.frame(width: 12, height: 12)
			Circle()
				.stroke(Color.primary, lineWidth: 1)
				.frame(width: 12, height: 12)
		}
	}

	private var historyArrowSymbol: some View {
		Image(systemName: "location.north.circle.fill")
			.font(.system(size: 20))
			.foregroundStyle(.blue)
	}

	private var routeStartSymbol: some View {
		ZStack {
			Circle()
				.fill(Color.green)
			Circle()
				.strokeBorder(Color.white, lineWidth: 2)
		}
		.frame(width: 15, height: 15)
	}

	private var routeEndSymbol: some View {
		ZStack {
			Circle()
				.fill(Color.black)
			Circle()
				.strokeBorder(Color.white, lineWidth: 2)
		}
		.frame(width: 15, height: 15)
	}

	private var routeLineSymbol: some View {
		ZStack {
			Path { path in
				path.move(to: CGPoint(x: 4, y: 20))
				path.addLine(to: CGPoint(x: 36, y: 20))
			}
			.stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 6]))
			.foregroundStyle(Color.blue)
		}
	}

	private var convexHullSymbol: some View {
		ZStack {
			// Draw a simplified polygon shape
			ConvexHullShape()
				.fill(Color.indigo.opacity(0.4))
			ConvexHullShape()
				.stroke(Color.blue, lineWidth: 2)
		}
		.frame(width: 32, height: 32)
	}
}

private struct ConvexHullShape: Shape {
	func path(in rect: CGRect) -> Path {
		var path = Path()
		let w = rect.width
		let h = rect.height
		path.move(to: CGPoint(x: w * 0.5, y: h * 0.1))
		path.addLine(to: CGPoint(x: w * 0.85, y: h * 0.3))
		path.addLine(to: CGPoint(x: w * 0.9, y: h * 0.7))
		path.addLine(to: CGPoint(x: w * 0.6, y: h * 0.9))
		path.addLine(to: CGPoint(x: w * 0.15, y: h * 0.8))
		path.addLine(to: CGPoint(x: w * 0.1, y: h * 0.35))
		path.closeSubpath()
		return path
	}
}
