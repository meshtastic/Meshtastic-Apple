//
//  KMLConverter.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/24/26.
//
//  Reads a KML document into GeoJSON features, using the simplestyle keys the map already
//  draws (`stroke`, `stroke-width`, `stroke-opacity`, `fill`, `fill-opacity`), plus the ground
//  overlays and point icons that GeoJSON has no way to say.
//

import Foundation

/// A KML `<GroundOverlay>`: an image laid on the map between four edges, turned about its center.
struct KMLGroundOverlay: Equatable {
	var name: String?
	/// The image reference as written in the file, which may be a path inside a KMZ or a URL.
	var href: String
	var north: Double
	var south: Double
	var east: Double
	var west: Double
	/// Degrees, counterclockwise, as KML states it.
	var rotation: Double
}

/// What a KML document holds that the map can draw.
struct KMLConversion {
	/// GeoJSON feature dictionaries. A point that names an icon carries it as `icon-href`.
	var features: [[String: Any]] = []
	var groundOverlays: [KMLGroundOverlay] = []

	var isEmpty: Bool { features.isEmpty && groundOverlays.isEmpty }
}

enum KMLConverterError: Error, LocalizedError {
	case notKML
	case malformed

	var errorDescription: String? {
		switch self {
		case .notKML:
			return String(localized: "This file is not a KML map.")
		case .malformed:
			return String(localized: "This KML file could not be read.")
		}
	}
}

enum KMLConverter {
	/// Reads `data` as KML. Throws when it isn't XML or isn't KML; returns an empty conversion when
	/// it is KML with nothing to draw.
	static func convert(_ data: Data) throws -> KMLConversion {
		let parser = XMLParser(data: data)
		// Local names, so `gx:coord` reads as `coord`. External entities stay off.
		parser.shouldProcessNamespaces = true
		parser.shouldResolveExternalEntities = false
		let reader = KMLReader()
		parser.delegate = reader
		guard parser.parse() else {
			// A document cut short still gives what came before the break; one that never reached
			// a KML root is not a KML file at all.
			if reader.sawKMLRoot, reader.hasContent { return reader.finish() }
			throw reader.sawKMLRoot ? KMLConverterError.malformed : KMLConverterError.notKML
		}
		guard reader.sawKMLRoot else { throw KMLConverterError.notKML }
		return reader.finish()
	}

	// MARK: - Colors

	/// A KML color is `aabbggrr`: alpha first, then the channels in the reverse of CSS order.
	/// Returns the CSS hex and the opacity, or nil when the text isn't a color.
	static func cssColor(fromKML text: String) -> (hex: String, opacity: Double)? {
		let digits = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
		guard digits.count == 8, let value = UInt32(digits, radix: 16) else { return nil }
		let alpha = Double((value >> 24) & 0xFF) / 255
		let blue = (value >> 16) & 0xFF
		let green = (value >> 8) & 0xFF
		let red = value & 0xFF
		let hex = String(format: "#%02x%02x%02x", red, green, blue)
		return (hex, (alpha * 1000).rounded() / 1000)
	}

	// MARK: - Text

	/// Description HTML as plain text: line breaks kept, tags dropped, the common entities decoded.
	static func plainText(fromHTML html: String) -> String {
		var text = html
		let breaks = ["<br>", "<br/>", "<br />", "</p>", "</div>", "</tr>", "</li>", "</h1>", "</h2>", "</h3>"]
		for tag in breaks {
			text = text.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
		}
		text = text.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
		let entities = [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")]
		for (entity, character) in entities {
			text = text.replacingOccurrences(of: entity, with: character)
		}
		text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
		text = text.replacingOccurrences(of: " ?\\n ?", with: "\n", options: .regularExpression)
		text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
		return text.trimmingCharacters(in: .whitespacesAndNewlines)
	}
}

// MARK: - Geometry

struct KMLPosition: Equatable {
	var longitude: Double
	var latitude: Double

	var json: [Double] { [longitude, latitude] }
}

enum KMLGeometry {
	case point(KMLPosition)
	case line([KMLPosition])
	/// An outer ring and any holes, each ring already closed and wound the way GeoJSON wants.
	case polygon([[KMLPosition]])

	var isPolygon: Bool {
		if case .polygon = self { return true }
		return false
	}

	var isPoint: Bool {
		if case .point = self { return true }
		return false
	}

	/// The GeoJSON `geometry` member.
	var json: [String: Any] {
		switch self {
		case .point(let position):
			return ["type": "Point", "coordinates": position.json]
		case .line(let positions):
			let segments = KMLGeometry.splitAtAntimeridian(positions)
			if segments.count == 1 {
				return ["type": "LineString", "coordinates": segments[0].map(\.json)]
			}
			return ["type": "MultiLineString", "coordinates": segments.map { $0.map(\.json) }]
		case .polygon(let rings):
			return ["type": "Polygon", "coordinates": rings.map { $0.map(\.json) }]
		}
	}

	// MARK: Parsing

	/// `lon,lat[,alt]` tuples separated by whitespace. Tuples that aren't numbers or are off the
	/// globe are dropped. Nil when none survive.
	static func parseCoordinates(_ raw: String) -> [KMLPosition]? {
		let positions: [KMLPosition] = raw
			.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" })
			.compactMap { tuple in
				let parts = tuple.split(separator: ",", omittingEmptySubsequences: false)
				guard parts.count >= 2,
					  let longitude = Double(parts[0].trimmingCharacters(in: .whitespaces)),
					  let latitude = Double(parts[1].trimmingCharacters(in: .whitespaces)),
					  longitude.isFinite, latitude.isFinite,
					  abs(longitude) <= 180, abs(latitude) <= 90 else { return nil }
				return KMLPosition(longitude: longitude, latitude: latitude)
			}
		return positions.isEmpty ? nil : positions
	}

	/// A ring made ready for GeoJSON: closed, and wound counterclockwise for an outer ring or
	/// clockwise for a hole (RFC 7946 §3.1.6). KML says nothing about winding and exporters go both
	/// ways, so the ring is turned rather than trusted.
	static func ring(_ positions: [KMLPosition], isHole: Bool) -> [KMLPosition]? {
		guard positions.count >= 3 else { return nil }
		var closed = isCounterClockwise(positions) == !isHole ? positions : Array(positions.reversed())
		if closed.first != closed.last, let first = closed.first { closed.append(first) }
		return closed.count >= 4 ? closed : nil
	}

	private static func isCounterClockwise(_ ring: [KMLPosition]) -> Bool {
		var sum = 0.0
		for index in ring.indices {
			let from = ring[index]
			let to = ring[(index + 1) % ring.count]
			sum += (to.longitude - from.longitude) * (to.latitude + from.latitude)
		}
		return sum < 0
	}

	/// A line that crosses the antimeridian is cut there, so it doesn't streak across the map the
	/// long way round.
	static func splitAtAntimeridian(_ positions: [KMLPosition]) -> [[KMLPosition]] {
		guard var previous = positions.first else { return [] }
		var segments: [[KMLPosition]] = []
		var current = [previous]
		for next in positions.dropFirst() {
			let delta = next.longitude - previous.longitude
			if abs(delta) > 180 {
				let exit: Double = delta > 0 ? -180 : 180
				let shortWay = delta - 360 * (delta > 0 ? 1 : -1)
				let fraction = min(max((exit - previous.longitude) / shortWay, 0), 1)
				let latitude = previous.latitude + fraction * (next.latitude - previous.latitude)
				current.append(KMLPosition(longitude: exit, latitude: latitude))
				segments.append(current)
				current = [KMLPosition(longitude: -exit, latitude: latitude)]
			}
			current.append(next)
			previous = next
		}
		segments.append(current)
		return segments
	}
}

// MARK: - Styles

struct KMLStyle {
	var lineColor: String?
	var lineWidth: Double?
	var fillColor: String?
	var filled = true
	var outlined = true
	var iconHref: String?
	var iconScale: Double?
}

// MARK: - Reader

private struct KMLPlacemark {
	var name: String?
	var description: String?
	var styleURL: String?
	var inlineStyle: KMLStyle?
	var hidden = false
	var geometries: [KMLGeometry] = []
}

private final class KMLReader: NSObject, XMLParserDelegate {
	private(set) var sawKMLRoot = false
	var hasContent: Bool { !placemarks.isEmpty || !overlays.isEmpty }

	private var path: [String] = []
	private var text = ""

	private var styles: [String: KMLStyle] = [:]
	private var styleMaps: [String: String] = [:]
	private var placemarks: [KMLPlacemark] = []
	private var overlays: [KMLGroundOverlay] = []

	private var style: KMLStyle?
	private var styleID: String?
	private var styleMapID: String?
	private var styleMapKey: String?
	private var placemark: KMLPlacemark?

	/// One flag per open Document or Folder, set when it says `<visibility>0</visibility>`.
	private var hiddenContainers: [Bool] = []

	private var rings: [(positions: [KMLPosition], isHole: Bool)] = []
	private var overlayDraft: OverlayDraft?

	private struct OverlayDraft {
		var name: String?
		var href: String?
		var north: Double?
		var south: Double?
		var east: Double?
		var west: Double?
		var rotation = 0.0
	}

	// MARK: Delegate

	func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
		if path.isEmpty, elementName == "kml" { sawKMLRoot = true }
		path.append(elementName)
		text = ""
		switch elementName {
		case "Document", "Folder":
			hiddenContainers.append(false)
		case "Placemark":
			placemark = KMLPlacemark(hidden: hiddenContainers.contains(true))
		case "Style":
			style = KMLStyle()
			styleID = attributeDict["id"]
		case "StyleMap":
			styleMapID = attributeDict["id"]
		case "Polygon":
			rings = []
		case "GroundOverlay":
			overlayDraft = OverlayDraft()
		default:
			break
		}
	}

	func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

	func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
		text += String(data: CDATABlock, encoding: .utf8) ?? ""
	}

	func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
		let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
		let parent = path.count >= 2 ? path[path.count - 2] : ""
		endElement(elementName, value: value, parent: parent)
		path.removeLast()
		text = ""
	}

	// MARK: Elements

	private func endElement(_ name: String, value: String, parent: String) {
		switch name {
		case "Document", "Folder":
			_ = hiddenContainers.popLast()
		case "visibility":
			guard value == "0" else { break }
			if parent == "Placemark" {
				placemark?.hidden = true
			} else if parent == "Document" || parent == "Folder", !hiddenContainers.isEmpty {
				hiddenContainers[hiddenContainers.count - 1] = true
			}
		case "name":
			if parent == "Placemark" {
				placemark?.name = value
			} else if parent == "GroundOverlay" {
				overlayDraft?.name = value
			}
		case "description":
			if parent == "Placemark" { placemark?.description = KMLConverter.plainText(fromHTML: value) }
		case "styleUrl":
			if parent == "Placemark" {
				placemark?.styleURL = Self.styleKey(value)
			} else if parent == "Pair", styleMapKey == "normal", let id = styleMapID {
				styleMaps["#" + id] = Self.styleKey(value)
			}
		case "key":
			if parent == "Pair" { styleMapKey = value }
		case "color", "width", "fill", "outline", "scale":
			styleValue(name, value)
		case "href":
			if path.contains("IconStyle") {
				style?.iconHref = value.isEmpty ? nil : value
			} else if parent == "Icon", path.contains("GroundOverlay") {
				overlayDraft?.href = value
			}
		case "north", "south", "east", "west", "rotation":
			if parent == "LatLonBox" { overlayValue(name, value) }
		case "coordinates":
			coordinates(value)
		case "Polygon":
			endPolygon()
		case "Style":
			endStyle()
		case "Placemark":
			if let finished = placemark { placemarks.append(finished) }
			placemark = nil
		case "GroundOverlay":
			endGroundOverlay()
		default:
			break
		}
	}

	private static func styleKey(_ reference: String) -> String {
		reference.split(separator: "#").last.map { "#" + $0 } ?? reference
	}

	private func styleValue(_ name: String, _ value: String) {
		guard style != nil else { return }
		if path.contains("LineStyle") {
			if name == "color" { style?.lineColor = value }
			if name == "width" { style?.lineWidth = Double(value) }
		} else if path.contains("PolyStyle") {
			if name == "color" { style?.fillColor = value }
			if name == "fill" { style?.filled = value != "0" }
			if name == "outline" { style?.outlined = value != "0" }
		} else if path.contains("IconStyle"), name == "scale" {
			style?.iconScale = Double(value)
		}
	}

	private func overlayValue(_ name: String, _ value: String) {
		guard let number = Double(value), number.isFinite else { return }
		switch name {
		case "north": overlayDraft?.north = number
		case "south": overlayDraft?.south = number
		case "east": overlayDraft?.east = number
		case "west": overlayDraft?.west = number
		default: overlayDraft?.rotation = number
		}
	}

	private func coordinates(_ raw: String) {
		guard placemark != nil, let positions = KMLGeometry.parseCoordinates(raw) else { return }
		if path.contains("Point") {
			if let first = positions.first { placemark?.geometries.append(.point(first)) }
		} else if path.contains("Polygon") {
			rings.append((positions, path.contains("innerBoundaryIs")))
		} else if path.contains("LineString"), positions.count >= 2 {
			placemark?.geometries.append(.line(positions))
		}
	}

	private func endPolygon() {
		defer { rings = [] }
		guard placemark != nil,
			  let outer = rings.first(where: { !$0.isHole }),
			  let shell = KMLGeometry.ring(outer.positions, isHole: false) else { return }
		let holes = rings.filter(\.isHole).compactMap { KMLGeometry.ring($0.positions, isHole: true) }
		placemark?.geometries.append(.polygon([shell] + holes))
	}

	private func endStyle() {
		defer { style = nil; styleID = nil }
		guard let finished = style else { return }
		if placemark != nil {
			placemark?.inlineStyle = finished
		} else if let id = styleID {
			styles["#" + id] = finished
		}
	}

	private func endGroundOverlay() {
		defer { overlayDraft = nil }
		guard let draft = overlayDraft, let href = draft.href, !href.isEmpty,
			  let north = draft.north, let south = draft.south,
			  let east = draft.east, let west = draft.west,
			  north > south, abs(north) <= 90, abs(south) <= 90,
			  abs(east) <= 180, abs(west) <= 180, east != west else { return }
		overlays.append(KMLGroundOverlay(
			name: draft.name, href: href,
			north: north, south: south, east: east, west: west,
			rotation: draft.rotation
		))
	}

	// MARK: Result

	func finish() -> KMLConversion {
		var conversion = KMLConversion()
		conversion.groundOverlays = overlays
		for placemark in placemarks {
			// An inline Style outranks a styleUrl, per the KML reference. A StyleMap points at the
			// styles for normal and highlighted; only the normal one is drawn.
			let resolved = placemark.inlineStyle
				?? placemark.styleURL.flatMap { styles[styleMaps[$0] ?? $0] }
			for geometry in placemark.geometries {
				conversion.features.append(Self.feature(geometry, placemark: placemark, style: resolved))
			}
		}
		return conversion
	}

	private static func feature(_ geometry: KMLGeometry, placemark: KMLPlacemark, style: KMLStyle?) -> [String: Any] {
		var properties: [String: Any] = [:]
		if let name = placemark.name, !name.isEmpty { properties["name"] = name }
		if let description = placemark.description, !description.isEmpty { properties["description"] = description }
		if placemark.hidden { properties["visible"] = false }
		if let style {
			if let (hex, opacity) = style.lineColor.flatMap(KMLConverter.cssColor(fromKML:)) {
				properties["stroke"] = hex
				properties["stroke-opacity"] = opacity
			}
			if let width = style.lineWidth { properties["stroke-width"] = width }
			if geometry.isPolygon {
				if !style.outlined { properties["stroke-opacity"] = 0.0 }
				if style.filled, let (hex, opacity) = style.fillColor.flatMap(KMLConverter.cssColor(fromKML:)) {
					properties["fill"] = hex
					properties["fill-opacity"] = opacity
				}
			}
			if geometry.isPoint {
				if let href = style.iconHref { properties["icon-href"] = href }
				if let scale = style.iconScale, scale > 0 { properties["icon-scale"] = scale }
			}
		}
		return ["type": "Feature", "properties": properties, "geometry": geometry.json]
	}
}
