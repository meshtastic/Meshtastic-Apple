//
//  WidgetMapRenderer.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/16/26.
//
//  Renders the map widget's images in the app, in the trace route share
//  image's look: the same dark, muted tiles, node circles in their colors and
//  the connected radio ringed in brand green — a square for small and medium,
//  a wide one for large and a tall one for extra large portrait. Renders are throttled, and the throttle only
//  advances on success: a failed render (offline launch, snapshotter error)
//  is retried by the next broker refresh instead of being silently dropped.
//

import MapKit
import OSLog
import SwiftUI
import WidgetKit

@MainActor
final class WidgetMapRenderer {
	static let shared = WidgetMapRenderer()

	private static let scale: CGFloat = 3
	/// Renders cost a snapshotter pass per shape and a widget reload each, so at
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
	fileprivate struct MapPin {
		let node: NodeSnapshot
		let coordinate: CLLocationCoordinate2D
	}

	private var lastSuccessKey: String?
	private var lastSuccessAt: Date?
	/// The radio the last written image rings.
	private var lastSuccessRadioNum: Int64?
	private var inFlightKey: String?
	private var renderTask: Task<Void, Never>?

	/// True while an image is being drawn; the broker leaves the map's reload
	/// to the render.
	var isRendering: Bool { inFlightKey != nil }

	/// Called by the broker after each snapshot write, with the nodes it wrote.
	func refresh(nodes: [NodeSnapshot], radioNum: Int64?) {
		let pins = Self.localPins(from: nodes)
		// The radio is part of the key so a radio switch moves the green ring,
		// and short names are, so a renamed node's circle is redrawn.
		let key = "\(radioNum ?? 0)#" + (pins.isEmpty ? "none" : pins
			.sorted { $0.node.num < $1.node.num }
			.map { pin -> String in
				let lat = (pin.coordinate.latitude * Self.gridScale).rounded()
				let lon = (pin.coordinate.longitude * Self.gridScale).rounded()
				return "\(pin.node.num):\(pin.node.shortName):\(lat):\(lon)"
			}
			.joined(separator: "|"))

		// Unchanged, already being rendered, or inside the floor: skip. The
		// floor case retries naturally — the key stays uncommitted, so the
		// next broker refresh after the floor lapses renders the move. A new
		// radio skips the floor: the ring and the widget's title must agree.
		guard key != lastSuccessKey, key != inFlightKey else { return }
		let radioChanged = lastSuccessKey != nil && radioNum != lastSuccessRadioNum
		if !radioChanged, let lastSuccessAt, Date().timeIntervalSince(lastSuccessAt) < Self.minimumInterval { return }

		inFlightKey = key
		renderTask?.cancel()
		renderTask = Task { [pins, radioNum] in
			let rendered = await Self.render(pins: pins, radioNum: radioNum)
			// A superseded task must not commit state for its old positions;
			// the newer render settles the map's reload.
			if !Task.isCancelled {
				if rendered {
					self.lastSuccessKey = key
					self.lastSuccessAt = Date()
					self.lastSuccessRadioNum = radioNum
				} else {
					// Nothing written, so no reload went out; send the one the
					// broker held back for this render.
					WidgetDataBroker.shared.sendDeferredMapReload()
				}
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

	private static func render(pins: [MapPin], radioNum: Int64?) async -> Bool {
		let meta = WidgetMapMeta(
			generatedAt: Date(),
			nodeNums: pins.map(\.node.num),
			radioNum: radioNum,
			pins: pins.map {
				WidgetMapPin(
					num: $0.node.num,
					latitude: $0.coordinate.latitude,
					longitude: $0.coordinate.longitude,
					lastHeard: $0.node.lastHeard,
					isFavorite: $0.node.isFavorite
				)
			}
		)
		guard !pins.isEmpty else {
			let saved = WidgetMapStore.saveEmpty(meta: meta)
			if saved { WidgetDataBroker.shared.reload(.map) }
			return saved
		}

		let points = pins.map { MKMapPoint($0.coordinate) }
		var images: [WidgetMapShape: UIImage] = [:]
		for shape in WidgetMapShape.allCases {
			// The share image's framing: the pins' bounds with padding and a
			// minimum span, widened to the map's shape so nothing is cropped.
			let frame = TraceRouteShareModel.frame(points: points, width: shape.size.width, height: shape.size.height)
			// Dark, muted tiles without points of interest, as on the share image.
			let tiles = await TraceRouteShareRenderer.snapshot(rect: frame.rect, size: frame.size, scale: scale)
			// A cancelled (superseded) render must not overwrite the newer files.
			guard !Task.isCancelled else { return false }
			guard let tiles, let image = drawMap(tiles: tiles, rect: frame.rect, size: frame.size, pins: pins, radioNum: radioNum) else {
				Logger.services.warning("🧩 Widget map render produced no image.")
				// The tall size can show the wide map, so keep the other two.
				if shape == .tall { continue }
				return false
			}
			images[shape] = image
		}
		// Drawing needs the main actor; encoding and writing the files don't.
		let finished = images
		let saved = await Task.detached(priority: .utility) {
			var data: [WidgetMapShape: Data] = [:]
			for (shape, image) in finished {
				guard let png = image.pngData() else { return false }
				data[shape] = png
			}
			return WidgetMapStore.save(images: data, meta: meta)
		}.value
		guard saved, !Task.isCancelled else { return false }
		WidgetDataBroker.shared.reload(.map)
		return true
	}

	private static func drawMap(tiles: UIImage, rect: MKMapRect, size: CGSize, pins: [MapPin], radioNum: Int64?) -> UIImage? {
		let renderer = ImageRenderer(content: WidgetMapPinsView(tiles: tiles, rect: rect, size: size, pins: pins, radioNum: radioNum)
			.environment(\.colorScheme, .dark))
		renderer.scale = scale
		renderer.proposedSize = ProposedViewSize(size)
		return renderer.uiImage
	}
}

/// The tiles with a circle for each node, styled like the share image's map:
/// node color, white rim and a soft shadow, the radio ringed in brand green
/// and drawn on top, inside the same rounded frame.
private struct WidgetMapPinsView: View {
	let tiles: UIImage
	let rect: MKMapRect
	let size: CGSize
	fileprivate let pins: [WidgetMapRenderer.MapPin]
	let radioNum: Int64?

	private static let circleSize: CGFloat = 22
	private static let brand = Color(red: 0x67 / 255, green: 0xEA / 255, blue: 0x94 / 255)

	var body: some View {
		ZStack(alignment: .topLeading) {
			Image(uiImage: tiles)
				.resizable()
				.interpolation(.high)
				.frame(width: size.width, height: size.height)
			// The radio last, so it stays on top of a cluster.
			ForEach(ordered, id: \.node.num) { pin in
				circle(for: pin.node, isRadio: pin.node.num == radioNum)
					.shadow(color: .black.opacity(0.5), radius: 3, y: 1)
					.position(point(for: pin.coordinate))
			}
		}
		.frame(width: size.width, height: size.height)
		.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
		.overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
	}

	private var ordered: [WidgetMapRenderer.MapPin] {
		pins.sorted { ($0.node.num == radioNum ? 1 : 0) < ($1.node.num == radioNum ? 1 : 0) }
	}

	private func point(for coordinate: CLLocationCoordinate2D) -> CGPoint {
		let mapPoint = MKMapPoint(coordinate)
		return CGPoint(
			x: (mapPoint.x - rect.minX) / rect.width * size.width,
			y: (mapPoint.y - rect.minY) / rect.height * size.height
		)
	}

	private func circle(for node: NodeSnapshot, isRadio: Bool) -> some View {
		let color = UIColor(
			red: CGFloat((node.colorSeed >> 16) & 0xFF) / 255,
			green: CGFloat((node.colorSeed >> 8) & 0xFF) / 255,
			blue: CGFloat(node.colorSeed & 0xFF) / 255,
			alpha: 1
		)
		return Text(node.shortName)
			.font(.system(size: Self.circleSize * 0.34, weight: .bold))
			.minimumScaleFactor(0.4)
			.lineLimit(1)
			.padding(2)
			.foregroundStyle(color.isLight() ? Color.black : Color.white)
			.frame(width: Self.circleSize, height: Self.circleSize)
			.background(Circle().fill(Color(uiColor: color)))
			.overlay(Circle().strokeBorder(isRadio ? Self.brand : .white, lineWidth: isRadio ? 2.5 : 1.5))
	}
}
