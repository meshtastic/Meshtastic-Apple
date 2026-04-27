//
//  NearbyNodesListView.swift
//  Meshtastic Watch App
//
//  Copyright(c) Meshtastic 2025.
//

import SwiftUI
import CoreLocation

/// Shows mesh nodes within half a mile (≈ 805 m) that have a valid
/// position.  Tapping a node opens the foxhunt compass pointing at it.
struct NearbyNodesListView: View {

	@ObservedObject var phoneManager: PhoneConnectivityManager
	@ObservedObject var locationManager: WatchLocationManager
	@State private var selectedNode: MeshNode?

	/// Nodes filtered to ≤ 0.5 miles with a known position, sorted by distance.
	/// Also includes any nodes pinned as foxhunt targets from the iOS app.
	private var nearbyNodes: [MeshNode] {
		guard let userLoc = locationManager.currentLocation else { return [] }
		let targets = phoneManager.foxhuntTargets
		return phoneManager.nodes.values
			.filter { node in
				guard node.coordinate != nil else { return false }
				// Always include foxhunt targets regardless of distance
				if targets.contains(node.num) { return true }
				guard let dist = node.distance(from: userLoc) else { return false }
				return dist <= FoxhuntCompassView.maxDistanceMetres
			}
			.sorted { a, b in
				let aIsTarget = targets.contains(a.num)
				let bIsTarget = targets.contains(b.num)
				// Foxhunt targets sort first
				if aIsTarget != bIsTarget { return aIsTarget }
				let dA = a.distance(from: userLoc) ?? .greatestFiniteMagnitude
				let dB = b.distance(from: userLoc) ?? .greatestFiniteMagnitude
				return dA < dB
			}
	}

	var body: some View {
		Group {
			if nearbyNodes.isEmpty {
				emptyState
			} else {
				nodeList
			}
		}
		.navigationTitle {
			HStack(spacing: 4) {
				Image("logo-white")
					.resizable()
					.scaledToFit()
					.frame(height: 16)
				Image("custom.foxhunt")
					.font(.system(size: 14))
					.foregroundStyle(.orange)
				Text("Foxhunt")
					.font(.headline)
					.foregroundStyle(.green)
			}
		}
		.sheet(item: $selectedNode) { node in
			FoxhuntCompassView(node: node, locationManager: locationManager)
		}
	}

	// MARK: - Sub-views

	@ViewBuilder
	private var emptyState: some View {
		VStack(spacing: 8) {
			Image(systemName: "antenna.radiowaves.left.and.right")
				.font(.title2)
				.foregroundStyle(.secondary)
			Text("No nearby nodes")
				.font(.headline)
			Text("Nodes within ½ mile with a known position will appear here.")
				.font(.caption2)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
				.padding(.horizontal)

			if !phoneManager.hasReceivedData {
				Text("Open Meshtastic on your iPhone to sync.")
					.font(.caption2)
					.foregroundStyle(.orange)
			}
		}
		.padding()
	}

	@ViewBuilder
	private var nodeList: some View {
		List(nearbyNodes) { node in
			Button {
				selectedNode = node
			} label: {
				nodeRow(node)
			}
		}
	}

	@ViewBuilder
	private func nodeRow(_ node: MeshNode) -> some View {
		let userLoc = locationManager.currentLocation
		let isTarget = phoneManager.foxhuntTargets.contains(node.num)
		HStack {
			WatchCircleText(
				text: node.shortName,
				color: WatchCircleText.color(for: node.num),
				circleSize: 28
			)
			VStack(alignment: .leading, spacing: 2) {
				Text(node.longName)
					.font(.system(size: 14, weight: .semibold))
					.lineLimit(1)
				if let userLoc, let dist = node.distance(from: userLoc) {
					Text(formatDistance(dist))
						.font(.system(size: 12, design: .rounded))
						.foregroundStyle(distanceColor(dist))
				}
			}
			Spacer()
			// Mini bearing arrow
			if let bearing = bearing(to: node) {
				Image(systemName: "location.north.fill")
					.font(.system(size: 14))
					.foregroundStyle(userLoc.flatMap { node.distance(from: $0) }.map { distanceColor($0) } ?? .secondary)
					.rotationEffect(.degrees(bearing - locationManager.heading))
			}
		}
	}

	// MARK: - Helpers

	private func bearing(to node: MeshNode) -> Double? {
		guard let target = node.coordinate,
			  let user = locationManager.currentLocation?.coordinate else { return nil }
		return FoxhuntCompassView.bearingBetween(from: user, to: target)
	}

	private func formatDistance(_ distance: CLLocationDistance) -> String {
		let measurement = Measurement(value: distance, unit: UnitLength.meters)
		let formatter = MeasurementFormatter()
		formatter.unitOptions = .naturalScale
		formatter.numberFormatter.maximumFractionDigits = 0
		return formatter.string(from: measurement)
	}

	private func distanceColor(_ distance: CLLocationDistance) -> Color {
		let ratio = min(distance / FoxhuntCompassView.maxDistanceMetres, 1.0)
		if ratio > 0.66 { return .blue }
		if ratio > 0.33 { return .yellow }
		return .red
	}
}
