import Foundation
import Testing

@testable import Meshtastic

// MARK: - AnyCodableValue

@Suite("AnyCodableValue Decoding")
struct AnyCodableValueDecodingTests {

	@Test func decodeString() throws {
		let json = Data(#""hello""#.utf8)
		let value = try JSONDecoder().decode(AnyCodableValue.self, from: json)
		if case .string(let str) = value {
			#expect(str == "hello")
		} else {
			#expect(Bool(false), "Expected string")
		}
	}

	@Test func decodeInt() throws {
		let json = Data("42".utf8)
		let value = try JSONDecoder().decode(AnyCodableValue.self, from: json)
		if case .int(let num) = value {
			#expect(num == 42)
		} else {
			#expect(Bool(false), "Expected int")
		}
	}

	@Test func decodeDouble() throws {
		let json = Data("3.14".utf8)
		let value = try JSONDecoder().decode(AnyCodableValue.self, from: json)
		if case .double(let num) = value {
			#expect(abs(num - 3.14) < 0.001)
		} else {
			#expect(Bool(false), "Expected double")
		}
	}

	@Test func decodeBool() throws {
		let json = Data("true".utf8)
		let value = try JSONDecoder().decode(AnyCodableValue.self, from: json)
		if case .bool(let val) = value {
			#expect(val == true)
		} else {
			#expect(Bool(false), "Expected bool")
		}
	}

	@Test func decodeNull() throws {
		let json = Data("null".utf8)
		let value = try JSONDecoder().decode(AnyCodableValue.self, from: json)
		if case .null = value {
			// success
		} else {
			#expect(Bool(false), "Expected null")
		}
	}

	@Test func decodeArray() throws {
		let json = Data("[1, 2, 3]".utf8)
		let value = try JSONDecoder().decode(AnyCodableValue.self, from: json)
		if case .array(let arr) = value {
			#expect(arr.count == 3)
		} else {
			#expect(Bool(false), "Expected array")
		}
	}

	@Test func decodeObject() throws {
		let json = Data(#"{"key": "value"}"#.utf8)
		let value = try JSONDecoder().decode(AnyCodableValue.self, from: json)
		if case .object(let dict) = value {
			#expect(dict.count == 1)
		} else {
			#expect(Bool(false), "Expected object")
		}
	}
}

@Suite("AnyCodableValue Encoding")
struct AnyCodableValueEncodingTests {

	@Test func roundTrip_string() throws {
		let original = AnyCodableValue.string("test")
		let data = try JSONEncoder().encode(original)
		let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
		if case .string(let str) = decoded {
			#expect(str == "test")
		} else {
			#expect(Bool(false), "Roundtrip failed")
		}
	}

	@Test func roundTrip_int() throws {
		let original = AnyCodableValue.int(99)
		let data = try JSONEncoder().encode(original)
		let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
		if case .int(let num) = decoded {
			#expect(num == 99)
		} else {
			#expect(Bool(false), "Roundtrip failed")
		}
	}

	@Test func roundTrip_bool() throws {
		let original = AnyCodableValue.bool(false)
		let data = try JSONEncoder().encode(original)
		let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
		if case .bool(let val) = decoded {
			#expect(val == false)
		} else {
			#expect(Bool(false), "Roundtrip failed")
		}
	}

	@Test func roundTrip_null() throws {
		let original = AnyCodableValue.null
		let data = try JSONEncoder().encode(original)
		let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
		if case .null = decoded {
			// success
		} else {
			#expect(Bool(false), "Roundtrip failed")
		}
	}

	@Test func roundTrip_array() throws {
		let original = AnyCodableValue.array([.int(1), .string("two")])
		let data = try JSONEncoder().encode(original)
		let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
		if case .array(let arr) = decoded {
			#expect(arr.count == 2)
		} else {
			#expect(Bool(false), "Roundtrip failed")
		}
	}
}

@Suite("AnyCodableValue toAnyObject")
struct AnyCodableValueToAnyObjectTests {

	@Test func string_returnsString() {
		let val = AnyCodableValue.string("hello")
		let obj = val.toAnyObject()
		#expect(obj as? String == "hello")
	}

	@Test func int_returnsInt() {
		let val = AnyCodableValue.int(42)
		let obj = val.toAnyObject()
		#expect(obj as? Int == 42)
	}

	@Test func double_returnsDouble() {
		let val = AnyCodableValue.double(3.14)
		let obj = val.toAnyObject()
		#expect((obj as? Double).map { abs($0 - 3.14) < 0.001 } ?? false)
	}

	@Test func bool_returnsBool() {
		let val = AnyCodableValue.bool(true)
		let obj = val.toAnyObject()
		#expect(obj as? Bool == true)
	}

	@Test func null_returnsNSNull() {
		let val = AnyCodableValue.null
		#expect(val.toAnyObject() is NSNull)
	}

	@Test func array_returnsArray() {
		let val = AnyCodableValue.array([.int(1), .int(2)])
		let obj = val.toAnyObject()
		#expect((obj as? [Any])?.count == 2)
	}

	@Test func object_returnsDictionary() {
		let val = AnyCodableValue.object(["key": .string("value")])
		let obj = val.toAnyObject()
		#expect((obj as? [String: Any])?.count == 1)
	}
}

@Suite("AnyCodableValue toCoordinate")
struct AnyCodableValueToCoordinateTests {

	@Test func validCoords_returnsCoordinate() {
		let val = AnyCodableValue.array([.double(-122.4), .double(37.7)])
		let coord = val.toCoordinate()
		#expect(coord != nil)
		#expect(abs(coord!.latitude - 37.7) < 0.001)
		#expect(abs(coord!.longitude - (-122.4)) < 0.001)
	}

	@Test func intCoords_returnsCoordinate() {
		let val = AnyCodableValue.array([.int(-122), .int(37)])
		let coord = val.toCoordinate()
		#expect(coord != nil)
		#expect(abs(coord!.latitude - 37) < 0.001)
	}

	@Test func singleElement_returnsNil() {
		let val = AnyCodableValue.array([.double(1)])
		#expect(val.toCoordinate() == nil)
	}

	@Test func nonArray_returnsNil() {
		let val = AnyCodableValue.string("not coords")
		#expect(val.toCoordinate() == nil)
	}

	@Test func stringElements_returnsNil() {
		let val = AnyCodableValue.array([.string("a"), .string("b")])
		#expect(val.toCoordinate() == nil)
	}
}

// MARK: - GeoJSON Feature Properties

@Suite("GeoJSONFeature Properties")
struct GeoJSONFeaturePropertiesTests {

	private func makeFeature(properties: [String: AnyCodableValue]?) -> GeoJSONFeature {
		GeoJSONFeature(
			type: "Feature",
			id: nil,
			geometry: GeoJSONGeometry(type: "Point", coordinates: .array([.double(0), .double(0)])),
			properties: properties
		)
	}

	@Test func name_fromUppercaseNAME() {
		let feature = makeFeature(properties: ["NAME": .string("Test Park")])
		#expect(feature.name == "Test Park")
	}

	@Test func name_fromLowercaseName() {
		let feature = makeFeature(properties: ["name": .string("Test Trail")])
		#expect(feature.name == "Test Trail")
	}

	@Test func name_nilProperties_returnsEmpty() {
		let feature = makeFeature(properties: nil)
		#expect(feature.name == "")
	}

	@Test func isVisible_default_true() {
		let feature = makeFeature(properties: nil)
		#expect(feature.isVisible)
	}

	@Test func isVisible_explicitFalse() {
		let feature = makeFeature(properties: ["visible": .bool(false)])
		#expect(!feature.isVisible)
	}

	@Test func strokeWidth_default_isOne() {
		let feature = makeFeature(properties: nil)
		#expect(feature.strokeWidth == 1.0)
	}

	@Test func strokeWidth_fromDouble() {
		let feature = makeFeature(properties: ["stroke-width": .double(3.5)])
		#expect(feature.strokeWidth == 3.5)
	}

	@Test func strokeWidth_fromInt() {
		let feature = makeFeature(properties: ["stroke-width": .int(2)])
		#expect(feature.strokeWidth == 2.0)
	}

	@Test func strokeOpacity_default_isOne() {
		let feature = makeFeature(properties: nil)
		#expect(feature.strokeOpacity == 1.0)
	}

	@Test func fillOpacity_default_isZero() {
		let feature = makeFeature(properties: nil)
		#expect(feature.fillOpacity == 0.0)
	}

	@Test func fillOpacity_fromDouble() {
		let feature = makeFeature(properties: ["fill-opacity": .double(0.5)])
		#expect(feature.fillOpacity == 0.5)
	}

	@Test func effectiveStrokeColor_default_isBlack() {
		let feature = makeFeature(properties: nil)
		#expect(feature.effectiveStrokeColor == "#000000")
	}

	@Test func effectiveStrokeColor_fromStroke() {
		let feature = makeFeature(properties: ["stroke": .string("#FF0000")])
		#expect(feature.effectiveStrokeColor == "#FF0000")
	}

	@Test func effectiveFillColor_noOpacity_isBlack() {
		let feature = makeFeature(properties: nil) // fillOpacity defaults to 0
		#expect(feature.effectiveFillColor == "#000000")
	}

	@Test func effectiveFillColor_withOpacity_usesFill() {
		let feature = makeFeature(properties: [
			"fill": .string("#00FF00"),
			"fill-opacity": .double(0.5)
		])
		#expect(feature.effectiveFillColor == "#00FF00")
	}

	@Test func markerRadius_small() {
		let feature = makeFeature(properties: ["marker-size": .string("small")])
		#expect(feature.markerRadius == 4.0)
	}

	@Test func markerRadius_medium() {
		let feature = makeFeature(properties: ["marker-size": .string("medium")])
		#expect(feature.markerRadius == 8.0)
	}

	@Test func markerRadius_large() {
		let feature = makeFeature(properties: ["marker-size": .string("large")])
		#expect(feature.markerRadius == 12.0)
	}

	@Test func markerRadius_default() {
		let feature = makeFeature(properties: nil) // markerSize defaults to "medium"
		#expect(feature.markerRadius == 8.0)
	}
}

// MARK: - GeoJSON Decoding from JSON

@Suite("GeoJSONFeatureCollection Decoding")
struct GeoJSONFeatureCollectionTests {

	@Test func decode_pointFeature() throws {
		let json = """
		{
			"type": "FeatureCollection",
			"features": [{
				"type": "Feature",
				"geometry": {
					"type": "Point",
					"coordinates": [-122.4, 37.7]
				},
				"properties": {"name": "Test Point"}
			}]
		}
		""".data(using: .utf8)!

		let collection = try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: json)
		#expect(collection.type == "FeatureCollection")
		#expect(collection.features.count == 1)
		#expect(collection.features[0].geometry.type == "Point")
		#expect(collection.features[0].name == "Test Point")
	}

	@Test func decode_lineStringFeature() throws {
		let json = """
		{
			"type": "FeatureCollection",
			"features": [{
				"type": "Feature",
				"geometry": {
					"type": "LineString",
					"coordinates": [[-122.4, 37.7], [-122.5, 37.8]]
				},
				"properties": {"stroke": "#FF0000", "stroke-width": 2}
			}]
		}
		""".data(using: .utf8)!

		let collection = try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: json)
		let feature = collection.features[0]
		#expect(feature.geometry.type == "LineString")
		#expect(feature.strokeColor == "#FF0000")
		#expect(feature.strokeWidth == 2.0)
	}

	@Test func decode_polygonFeature() throws {
		let json = """
		{
			"type": "FeatureCollection",
			"features": [{
				"type": "Feature",
				"geometry": {
					"type": "Polygon",
					"coordinates": [[[-122.0, 37.0], [-122.5, 37.0], [-122.5, 37.5], [-122.0, 37.0]]]
				},
				"properties": {"fill": "#00FF00", "fill-opacity": 0.3}
			}]
		}
		""".data(using: .utf8)!

		let collection = try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: json)
		let feature = collection.features[0]
		#expect(feature.geometry.type == "Polygon")
		#expect(feature.fillColor == "#00FF00")
		#expect(feature.fillOpacity == 0.3)
	}

	@Test func decode_emptyFeatureCollection() throws {
		let json = """
		{"type": "FeatureCollection", "features": []}
		""".data(using: .utf8)!

		let collection = try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: json)
		#expect(collection.features.isEmpty)
	}

	@Test func decode_multipleFeatures() throws {
		let json = """
		{
			"type": "FeatureCollection",
			"features": [
				{"type": "Feature", "geometry": {"type": "Point", "coordinates": [0, 0]}, "properties": null},
				{"type": "Feature", "geometry": {"type": "Point", "coordinates": [1, 1]}, "properties": null}
			]
		}
		""".data(using: .utf8)!

		let collection = try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: json)
		#expect(collection.features.count == 2)
	}
}
