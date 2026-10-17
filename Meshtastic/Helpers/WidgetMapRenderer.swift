//
//  WidgetMapRenderer.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/16/26.
//
//  Renders the map widget's images in the app with MKMapSnapshotter — square
//  for the small and large families, wide for medium, each in light and dark —
//  draws the node chips on them, and hands the PNGs to the shared store.
//  Renders are throttled, and the throttle only advances on success: a failed
//  render (offline launch, snapshotter error) is retried by the next broker
//  refresh instead of being silently dropped.
//

import MapKit
import OSLog
import UIKit
import WidgetKit

@MainActor
final class WidgetMapRenderer {
	static let shared = WidgetMapRenderer()

	/// Small and large crop the square; medium gets its own wide render so the
	/// north/south extremes are not cut off by a 2:1 crop of a square image.
	private static let squareSize = CGSize(width: 345, height: 345)
	private static let wideSize = CGSize(width: 360, height: 169)
	/// Renders cost four snapshotter passes and a widget reload each, so at
	/// most one per fifteen minutes, movement or not.
	private static let minimumInterval: TimeInterval = 15 * 60
	/// Positions snap to a ~28 m grid before comparison, so GPS jitter does
	/// not read as movement.
	private static let gridScale = 4_000.0
	/// Pins farther than this from the mesh's median position are left off —
	/// one MQTT-heard node on another continent would otherwise zoom the
	/// region out to continent scale.
	private static let outlierDistance: CLLocationDistance = 100_000

	/// A node with a real position, unwrapped once.
	private struct MapPin {
		let node: NodeSnapshot
		let coordinate: CLLocationCoordinate2D
	}

	private var lastSuccessKey: String?
	private var lastSuccessAt: Date?
	private var inFlightKey: String?
	private var renderTask: Task<Void, Never>?

	/// Called by the broker after each snapshot write, with the nodes it wrote.
	func refresh(nodes: [NodeSnapshot], radioNum: Int64?) {
		let pins = Self.localPins(from: nodes)
		let key = pins.isEmpty ? "none" : pins
			.sorted { $0.node.num < $1.node.num }
			.map { pin -> String in
				let lat = (pin.coordinate.latitude * Self.gridScale).rounded()
				let lon = (pin.coordinate.longitude * Self.gridScale).rounded()
				return "\(pin.node.num):\(lat):\(lon)"
			}
			.joined(separator: "|")

		// Unchanged, already being rendered, or inside the floor: skip. The
		// floor case retries naturally — the key stays uncommitted, so the
		// next broker refresh after the floor lapses renders the move.
		guard key != lastSuccessKey, key != inFlightKey else { return }
		if let lastSuccessAt, Date().timeIntervalSince(lastSuccessAt) < Self.minimumInterval { return }

		inFlightKey = key
		renderTask?.cancel()
		renderTask = Task { [pins, radioNum] in
			let rendered = await Self.render(pins: pins, radioNum: radioNum)
			// A superseded task must not commit state for its old positions.
			if !Task.isCancelled, rendered {
				self.lastSuccessKey = key
				self.lastSuccessAt = Date()
			}
			if self.inFlightKey == key {
				self.inFlightKey = nil
			}
		}
	}

	private static func localPins(from nodes: [NodeSnapshot]) -> [MapPin] {
		let positioned = nodes.compactMap { node -> MapPin? in
			guard let lat = node.latitude, let lon = node.longitude else { return nil }
			return MapPin(node: node, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
		}
		guard positioned.count >= 3 else { return positioned }
		let lats = positioned.map { $0.coordinate.latitude }.sorted()
		let lons = positioned.map { $0.coordinate.longitude }.sorted()
		let median = CLLocation(latitude: lats[lats.count / 2], longitude: lons[lons.count / 2])
		return positioned.filter {
			CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
				.distance(from: median) <= outlierDistance
		}
	}

	/// Off the main actor: four snapshotter passes, chip drawing and PNG
	/// encoding are more work than a UI hop should carry.
	private nonisolated static func render(pins: [MapPin], radioNum: Int64?) async -> Bool {
		let meta = WidgetMapMeta(generatedAt: Date(), nodeCount: pins.count)
		guard !pins.isEmpty else {
			let saved = WidgetMapStore.saveEmpty(meta: meta)
			if saved { WidgetCenter.shared.reloadTimelines(ofKind: "MeshNodeMap") }
			return saved
		}

		let region = region(for: pins)
		var images: [(data: Data, dark: Bool, wide: Bool)] = []
		for wide in [false, true] {
			for dark in [false, true] {
				guard !Task.isCancelled,
					  let image = await snapshotImage(region: region, pins: pins, radioNum: radioNum, dark: dark, wide: wide),
					  let data = image.pngData() else {
					Logger.services.warning("🧩 Widget map render produced no image.")
					return false
				}
				images.append((data, dark, wide))
			}
		}
		// A cancelled (superseded) render must not overwrite the newer files.
		guard !Task.isCancelled else { return false }
		guard WidgetMapStore.save(images: images, meta: meta) else { return false }
		WidgetCenter.shared.reloadTimelines(ofKind: "MeshNodeMap")
		return true
	}

	private nonisolated static func region(for pins: [MapPin]) -> MKCoordinateRegion {
		var rect = MKMapRect.null
		for pin in pins {
			let point = MKMapPoint(pin.coordinate)
			rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
		}
		// Generous padding keeps chips away from the edges; each canvas shape
		// gets its own snapshot of this region, so nothing relies on cropping.
		var region = MKCoordinateRegion(rect.insetBy(dx: -rect.width * 0.35 - 1, dy: -rect.height * 0.35 - 1))
		region.span.latitudeDelta = max(region.span.latitudeDelta, 0.02)
		region.span.longitudeDelta = max(region.span.longitudeDelta, 0.02)
		return region
	}

	private nonisolated static func snapshotImage(
		region: MKCoordinateRegion, pins: [MapPin], radioNum: Int64?, dark: Bool, wide: Bool
	) async -> UIImage? {
		let options = MKMapSnapshotter.Options()
		options.region = region
		options.size = wide ? wideSize : squareSize
		options.traitCollection = UITraitCollection(traitsFrom: [
			options.traitCollection,
			UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
		])
		options.showsBuildings = false
		options.pointOfInterestFilter = .excludingAll

		guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }
		return draw(pins: pins, radioNum: radioNum, on: snapshot)
	}

	private nonisolated static func draw(pins: [MapPin], radioNum: Int64?, on snapshot: MKMapSnapshotter.Snapshot) -> UIImage {
		let renderer = UIGraphicsImageRenderer(size: snapshot.image.size)
		return renderer.image { context in
			snapshot.image.draw(at: .zero)

			// The radio's chip draws last so it stays on top of a cluster.
			let ordered = pins.sorted { ($0.node.num == radioNum ? 1 : 0) < ($1.node.num == radioNum ? 1 : 0) }
			for pin in ordered {
				let point = snapshot.point(for: pin.coordinate)
				guard point.x > -20, point.y > -20,
					  point.x < snapshot.image.size.width + 20,
					  point.y < snapshot.image.size.height + 20 else { continue }
				drawChip(for: pin.node, at: point, isRadio: pin.node.num == radioNum, context: context.cgContext)
			}
		}
	}

	/// A circle in the node's color with the shortname fitted inside — the
	/// same look as the app's map annotations.
	private nonisolated static func drawChip(for node: NodeSnapshot, at point: CGPoint, isRadio: Bool, context: CGContext) {
		let color = UIColor(
			red: CGFloat((node.colorSeed >> 16) & 0xFF) / 255,
			green: CGFloat((node.colorSeed >> 8) & 0xFF) / 255,
			blue: CGFloat(node.colorSeed & 0xFF) / 255,
			alpha: 1
		)
		let diameter: CGFloat = 22
		let circle = CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2, width: diameter, height: diameter)

		let text = node.shortName as NSString
		let textColor: UIColor = color.isLight() ? .black : .white
		// Shrink the font until the name fits inside the circle.
		var fontSize: CGFloat = 9
		var font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
		var textSize = text.size(withAttributes: [.font: font])
		while textSize.width > diameter - 5, fontSize > 5 {
			fontSize -= 0.5
			font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
			textSize = text.size(withAttributes: [.font: font])
		}

		context.setFillColor(color.cgColor)
		let path = UIBezierPath(ovalIn: circle)
		path.fill()
		// The connected radio gets a halo so it reads at a glance.
		context.setStrokeColor(isRadio ? UIColor.systemGreen.cgColor : UIColor.white.withAlphaComponent(0.9).cgColor)
		path.lineWidth = isRadio ? 2.5 : 1
		path.stroke()

		text.draw(
			at: CGPoint(x: circle.midX - textSize.width / 2, y: circle.midY - textSize.height / 2),
			withAttributes: [.font: font, .foregroundColor: textColor]
		)
	}
}
