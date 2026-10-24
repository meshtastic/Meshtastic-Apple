//
//  KMLConverterTests.swift
//  MeshtasticTests
//

import Foundation
import MapKit
import Testing
@testable import Meshtastic

@Suite("KML converter")
struct KMLConverterTests {

	// MARK: - Fixtures

	private func kml(_ body: String) -> Data {
		Data("""
		<?xml version="1.0" encoding="UTF-8"?>
		<kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2">
		<Document>\(body)</Document>
		</kml>
		""".utf8)
	}

	private func properties(_ feature: [String: Any]) -> [String: Any] {
		feature["properties"] as? [String: Any] ?? [:]
	}

	private func geometry(_ feature: [String: Any]) -> [String: Any] {
		feature["geometry"] as? [String: Any] ?? [:]
	}

	// MARK: - Geometry

	@Test("A point, a line and a polygon each become one feature")
	func basicGeometries() throws {
		let result = try KMLConverter.convert(kml("""
		<Placemark><name>Camp</name><Point><coordinates>-122.3,47.6,12</coordinates></Point></Placemark>
		<Placemark><name>Trail</name><LineString><coordinates>-122.3,47.6 -122.2,47.7 -122.1,47.8</coordinates></LineString></Placemark>
		<Placemark><name>Lot</name><Polygon><outerBoundaryIs><LinearRing><coordinates>
		-122.30,47.60 -122.20,47.60 -122.20,47.70 -122.30,47.70 -122.30,47.60
		</coordinates></LinearRing></outerBoundaryIs></Polygon></Placemark>
		"""))
		#expect(result.features.count == 3)
		#expect(geometry(result.features[0])["type"] as? String == "Point")
		#expect(geometry(result.features[0])["coordinates"] as? [Double] == [-122.3, 47.6])
		#expect(geometry(result.features[1])["type"] as? String == "LineString")
		#expect(geometry(result.features[2])["type"] as? String == "Polygon")
		#expect(properties(result.features[0])["name"] as? String == "Camp")
	}

	@Test("A polygon keeps its holes")
	func polygonHoles() throws {
		let result = try KMLConverter.convert(kml("""
		<Placemark><Polygon>
		<outerBoundaryIs><LinearRing><coordinates>0,0 10,0 10,10 0,10 0,0</coordinates></LinearRing></outerBoundaryIs>
		<innerBoundaryIs><LinearRing><coordinates>2,2 4,2 4,4 2,4 2,2</coordinates></LinearRing></innerBoundaryIs>
		</Polygon></Placemark>
		"""))
		let rings = try #require(geometry(result.features[0])["coordinates"] as? [[[Double]]])
		#expect(rings.count == 2)
		#expect(rings[1].count == 5)
	}

	@Test("Rings are wound the way GeoJSON wants: outer counterclockwise, holes clockwise")
	func winding() throws {
		// Written clockwise outer, counterclockwise hole: both the wrong way round.
		let result = try KMLConverter.convert(kml("""
		<Placemark><Polygon>
		<outerBoundaryIs><LinearRing><coordinates>0,0 0,10 10,10 10,0 0,0</coordinates></LinearRing></outerBoundaryIs>
		<innerBoundaryIs><LinearRing><coordinates>2,2 4,2 4,4 2,4 2,2</coordinates></LinearRing></innerBoundaryIs>
		</Polygon></Placemark>
		"""))
		let rings = try #require(geometry(result.features[0])["coordinates"] as? [[[Double]]])
		func signedArea(_ ring: [[Double]]) -> Double {
			var sum = 0.0
			for index in 0..<(ring.count - 1) {
				sum += ring[index][0] * ring[index + 1][1] - ring[index + 1][0] * ring[index][1]
			}
			return sum / 2
		}
		#expect(signedArea(rings[0]) > 0, "outer ring counterclockwise")
		#expect(signedArea(rings[1]) < 0, "hole clockwise")
	}

	@Test("An unclosed ring is closed")
	func closesRings() throws {
		let result = try KMLConverter.convert(kml("""
		<Placemark><Polygon><outerBoundaryIs><LinearRing><coordinates>0,0 10,0 10,10 0,10</coordinates></LinearRing></outerBoundaryIs></Polygon></Placemark>
		"""))
		let ring = try #require((geometry(result.features[0])["coordinates"] as? [[[Double]]])?.first)
		#expect(ring.first == ring.last)
		#expect(ring.count == 5)
	}

	@Test("MultiGeometry becomes one feature per part")
	func multiGeometry() throws {
		let result = try KMLConverter.convert(kml("""
		<Placemark><name>Both</name><MultiGeometry>
		<Point><coordinates>1,1</coordinates></Point>
		<LineString><coordinates>1,1 2,2</coordinates></LineString>
		</MultiGeometry></Placemark>
		"""))
		#expect(result.features.count == 2)
		#expect(result.features.allSatisfy { properties($0)["name"] as? String == "Both" })
	}

	@Test("Bad coordinates are dropped, and a line left with one point is dropped")
	func badCoordinates() throws {
		let result = try KMLConverter.convert(kml("""
		<Placemark><Point><coordinates>200,95</coordinates></Point></Placemark>
		<Placemark><LineString><coordinates>1,1 abc,2 3</coordinates></LineString></Placemark>
		<Placemark><LineString><coordinates>1,1 2,2 nan,3</coordinates></LineString></Placemark>
		"""))
		#expect(result.features.count == 1)
		let coordinates = try #require(geometry(result.features[0])["coordinates"] as? [[Double]])
		#expect(coordinates.count == 2)
	}

	@Test("A line that crosses the antimeridian is cut there")
	func antimeridian() throws {
		let result = try KMLConverter.convert(kml("""
		<Placemark><LineString><coordinates>170,0 -170,10</coordinates></LineString></Placemark>
		"""))
		let geometry = geometry(result.features[0])
		#expect(geometry["type"] as? String == "MultiLineString")
		let parts = try #require(geometry["coordinates"] as? [[[Double]]])
		#expect(parts.count == 2)
		#expect(parts[0].last?[0] == 180)
		#expect(parts[1].first?[0] == -180)
		#expect(parts[0].last?[1] == parts[1].first?[1])
	}

	// MARK: - Styles

	@Test("A style reached through a StyleMap, and defined after its use, colors the feature")
	func styleMapAndForwardReference() throws {
		let result = try KMLConverter.convert(kml("""
		<Placemark><styleUrl>#route</styleUrl><LineString><coordinates>1,1 2,2</coordinates></LineString></Placemark>
		<StyleMap id="route"><Pair><key>normal</key><styleUrl>#routeNormal</styleUrl></Pair>
		<Pair><key>highlight</key><styleUrl>#routeHot</styleUrl></Pair></StyleMap>
		<Style id="routeNormal"><LineStyle><color>ff0000ff</color><width>4</width></LineStyle></Style>
		<Style id="routeHot"><LineStyle><color>ff00ff00</color><width>9</width></LineStyle></Style>
		"""))
		let props = properties(result.features[0])
		#expect(props["stroke"] as? String == "#ff0000")
		#expect(props["stroke-opacity"] as? Double == 1)
		#expect(props["stroke-width"] as? Double == 4)
	}

	@Test("An inline style wins over a shared one")
	func inlineStyleWins() throws {
		let result = try KMLConverter.convert(kml("""
		<Style id="shared"><LineStyle><color>ff0000ff</color></LineStyle></Style>
		<Placemark><styleUrl>#shared</styleUrl>
		<Style><LineStyle><color>ffff0000</color></LineStyle></Style>
		<LineString><coordinates>1,1 2,2</coordinates></LineString></Placemark>
		"""))
		#expect(properties(result.features[0])["stroke"] as? String == "#0000ff")
	}

	@Test("KML colors are aabbggrr and become CSS hex with a separate opacity")
	func colors() {
		let red = KMLConverter.cssColor(fromKML: "ff0000ff")
		#expect(red?.hex == "#ff0000")
		#expect(red?.opacity == 1)
		let halfBlue = KMLConverter.cssColor(fromKML: "7fff0000")
		#expect(halfBlue?.hex == "#0000ff")
		#expect(halfBlue?.opacity == 0.498)
		#expect(KMLConverter.cssColor(fromKML: "nope") == nil)
		#expect(KMLConverter.cssColor(fromKML: "ff00ff") == nil)
	}

	@Test("Polygon fill and outline follow PolyStyle")
	func polyStyle() throws {
		let result = try KMLConverter.convert(kml("""
		<Style id="a"><PolyStyle><color>8000ff00</color></PolyStyle><LineStyle><color>ffffffff</color></LineStyle></Style>
		<Style id="b"><PolyStyle><fill>0</fill><outline>0</outline></PolyStyle></Style>
		<Placemark><styleUrl>#a</styleUrl><Polygon><outerBoundaryIs><LinearRing><coordinates>0,0 1,0 1,1 0,0</coordinates></LinearRing></outerBoundaryIs></Polygon></Placemark>
		<Placemark><styleUrl>#b</styleUrl><Polygon><outerBoundaryIs><LinearRing><coordinates>0,0 1,0 1,1 0,0</coordinates></LinearRing></outerBoundaryIs></Polygon></Placemark>
		"""))
		let filled = properties(result.features[0])
		#expect(filled["fill"] as? String == "#00ff00")
		#expect(filled["fill-opacity"] as? Double == 0.502)
		let bare = properties(result.features[1])
		#expect(bare["fill"] == nil)
		#expect(bare["stroke-opacity"] as? Double == 0)
	}

	@Test("A LabelStyle color is not mistaken for the line color")
	func labelStyleColor() throws {
		let result = try KMLConverter.convert(kml("""
		<Style id="s"><IconStyle><color>ff00ffff</color></IconStyle><LabelStyle><color>ff00ff00</color></LabelStyle>
		<LineStyle><color>ff0000ff</color></LineStyle></Style>
		<Placemark><styleUrl>#s</styleUrl><LineString><coordinates>1,1 2,2</coordinates></LineString></Placemark>
		"""))
		#expect(properties(result.features[0])["stroke"] as? String == "#ff0000")
	}

	// MARK: - Names, descriptions, visibility

	@Test("A description keeps its text and loses its markup")
	func description() throws {
		let result = try KMLConverter.convert(kml("""
		<Placemark><name>Spot</name><description><![CDATA[<b>Best</b> view<br>Bring water &amp; a hat]]></description>
		<Point><coordinates>1,1</coordinates></Point></Placemark>
		"""))
		#expect(properties(result.features[0])["description"] as? String == "Best view\nBring water & a hat")
	}

	@Test("Only a Placemark's own name names the feature, not its folder's")
	func names() throws {
		let result = try KMLConverter.convert(kml("""
		<name>The document</name>
		<Folder><name>The folder</name>
		<Placemark><Point><coordinates>1,1</coordinates></Point></Placemark></Folder>
		"""))
		#expect(properties(result.features[0])["name"] == nil)
	}

	@Test("Hidden placemarks and hidden folders stay hidden")
	func visibility() throws {
		let result = try KMLConverter.convert(kml("""
		<Placemark><visibility>0</visibility><Point><coordinates>1,1</coordinates></Point></Placemark>
		<Folder><visibility>0</visibility><Placemark><Point><coordinates>2,2</coordinates></Point></Placemark></Folder>
		<Placemark><Point><coordinates>3,3</coordinates></Point></Placemark>
		"""))
		#expect(result.features.count == 3)
		#expect(properties(result.features[0])["visible"] as? Bool == false)
		#expect(properties(result.features[1])["visible"] as? Bool == false)
		#expect(properties(result.features[2])["visible"] == nil)
	}

	@Test("Plain text conversion handles the common entities and spacing")
	func plainText() {
		#expect(KMLConverter.plainText(fromHTML: "a&nbsp;&lt;b&gt;<p>x</p><p>y</p>") == "a <b>x\ny")
		#expect(KMLConverter.plainText(fromHTML: "<a href=\"x\">link</a>") == "link")
	}

	// MARK: - Icons and ground overlays

	@Test("A point's icon and scale come through, and only a point has them")
	func icons() throws {
		let result = try KMLConverter.convert(kml("""
		<Style id="pin"><IconStyle><scale>1.5</scale><Icon><href>files/pin.png</href></Icon></IconStyle></Style>
		<Placemark><styleUrl>#pin</styleUrl><Point><coordinates>1,1</coordinates></Point></Placemark>
		<Placemark><styleUrl>#pin</styleUrl><LineString><coordinates>1,1 2,2</coordinates></LineString></Placemark>
		"""))
		#expect(properties(result.features[0])["icon-href"] as? String == "files/pin.png")
		#expect(properties(result.features[0])["icon-scale"] as? Double == 1.5)
		#expect(properties(result.features[1])["icon-href"] == nil)
	}

	@Test("A ground overlay keeps its image, edges and rotation")
	func groundOverlay() throws {
		let result = try KMLConverter.convert(kml("""
		<GroundOverlay><name>Survey</name><Icon><href>images/survey.png</href></Icon>
		<LatLonBox><north>47.7</north><south>47.6</south><east>-122.2</east><west>-122.3</west><rotation>30</rotation></LatLonBox>
		</GroundOverlay>
		"""))
		#expect(result.features.isEmpty)
		let overlay = try #require(result.groundOverlays.first)
		#expect(overlay.name == "Survey")
		#expect(overlay.href == "images/survey.png")
		#expect(overlay.north == 47.7 && overlay.south == 47.6)
		#expect(overlay.east == -122.2 && overlay.west == -122.3)
		#expect(overlay.rotation == 30)
	}

	@Test("A ground overlay with its edges the wrong way round is skipped")
	func badOverlay() throws {
		let result = try KMLConverter.convert(kml("""
		<GroundOverlay><Icon><href>a.png</href></Icon>
		<LatLonBox><north>1</north><south>2</south><east>2</east><west>1</west></LatLonBox></GroundOverlay>
		"""))
		#expect(result.groundOverlays.isEmpty)
	}

	// MARK: - Documents that aren't KML

	@Test("Something that isn't KML is refused")
	func notKML() {
		#expect(throws: KMLConverterError.self) { try KMLConverter.convert(Data("<html><body>hi</body></html>".utf8)) }
		#expect(throws: KMLConverterError.self) { try KMLConverter.convert(Data("{\"type\":\"FeatureCollection\"}".utf8)) }
		#expect(throws: KMLConverterError.self) { try KMLConverter.convert(Data()) }
	}

	@Test("A KML with nothing to draw converts to an empty result")
	func empty() throws {
		let result = try KMLConverter.convert(kml("<name>Nothing here</name>"))
		#expect(result.isEmpty)
	}

	@Test("A KML cut short still gives the placemarks that arrived whole")
	func truncated() throws {
		let text = """
		<kml xmlns="http://www.opengis.net/kml/2.2"><Document>
		<Placemark><Point><coordinates>1,1</coordinates></Point></Placemark>
		<Placemark><Point><coord
		"""
		let result = try KMLConverter.convert(Data(text.utf8))
		#expect(result.features.count == 1)
	}

	// MARK: - What MapKit makes of the output

	@Test("The converted features load in MapKit, holes and all")
	func decodesInMapKit() throws {
		let result = try KMLConverter.convert(kml("""
		<Placemark><Point><coordinates>1,1</coordinates></Point></Placemark>
		<Placemark><LineString><coordinates>1,1 2,2</coordinates></LineString></Placemark>
		<Placemark><Polygon>
		<outerBoundaryIs><LinearRing><coordinates>0,0 10,0 10,10 0,10 0,0</coordinates></LinearRing></outerBoundaryIs>
		<innerBoundaryIs><LinearRing><coordinates>2,2 4,2 4,4 2,4 2,2</coordinates></LinearRing></innerBoundaryIs>
		</Polygon></Placemark>
		"""))
		let data = try JSONSerialization.data(withJSONObject: ["type": "FeatureCollection", "features": result.features])
		let decoded = try MKGeoJSONDecoder().decode(data)
		#expect(decoded.count == 3)
		let polygon = decoded
			.compactMap { ($0 as? MKGeoJSONFeature)?.geometry.first as? MKPolygon }
			.first
		#expect(polygon?.interiorPolygons?.count == 1)
	}
}
