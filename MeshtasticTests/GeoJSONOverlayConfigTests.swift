// GeoJSONOverlayConfigTests.swift
// MeshtasticTests

import Testing
import Foundation
import CoreLocation
@testable import Meshtastic

// MARK: - AnyCodableValue Tests

@Suite("AnyCodableValue Codable")
struct AnyCodableValueCodableTests {

	@Test func encodeDecodeString() throws {
		let value = AnyCodableValue.string("hello")
		let data = try JSONEncoder().encode(value)
		let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
		if case .string(let str) = decoded {
			#expect(str == "hello")
		} else {
			Issue.record("Expected .string")
		}
	}

	@Test func encodeDecodeInt() throws {
		let value = AnyCodableValue.int(42)
		let data = try JSONEncoder().encode(value)
		let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
		if case .int(let n) = decoded {
			#expect(n == 42)
		} else {
			Issue.record("Expected .int")
		}
	}

	@Test func encodeDecodeDouble() throws {
		let value = AnyCodableValue.double(3.14)
		let data = try JSONEncoder().encode(value)
		let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
		if case .double(let d) = decoded {
			#expect(abs(d - 3.14) < 0.001)
		} else {
			Issue.record("Expected .double")
		}
	}

	@Test func encodeDecodeBool() throws {
		let value = AnyCodableValue.bool(true)
		let data = try JSONEncoder().encode(value)
		let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
		if case .bool(let b) = decoded {
			#expect(b == true)
		} else {
			Issue.record("Expected .bool")
		}
	}

	@Test func encodeDecodeNull() throws {
		let value = AnyCodableValue.null
		let data = try JSONEncoder().encode(value)
		let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
		if case .null = decoded {} else {
			Issue.record("Expected .null")
		}
	}

	@Test func encodeDecodeArray() throws {
		let value = AnyCodableValue.array([.int(1), .string("two"), .bool(false)])
		let data = try JSONEncoder().encode(value)
		let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
		if case .array(let arr) = decoded {
			#expect(arr.count == 3)
		} else {
			Issue.record("Expected .array")
		}
	}

	@Test func encodeDecodeObject() throws {
		let value = AnyCodableValue.object(["key": .string("value"), "num": .int(5)])
		let data = try JSONEncoder().encode(value)
		let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
		if case .object(let dict) = decoded {
			#expect(dict.count == 2)
		} else {
			Issue.record("Expected .object")
		}
	}
}

// MARK: - AnyCodableValue toAnyObject Tests

@Suite("AnyCodableValue toAnyObject Extended")
struct AnyCodableValueToAnyObjectExtendedTests {

	@Test func stringToAnyObject() {
		let value = AnyCodableValue.string("test")
		let obj = value.toAnyObject()
		#expect(obj as? String == "test")
	}

	@Test func intToAnyObject() {
		let value = AnyCodableValue.int(99)
		let obj = value.toAnyObject()
		#expect(obj as? Int == 99)
	}

	@Test func doubleToAnyObject() {
		let value = AnyCodableValue.double(1.5)
		let obj = value.toAnyObject()
		#expect(obj as? Double == 1.5)
	}

	@Test func boolToAnyObject() {
		let value = AnyCodableValue.bool(false)
		let obj = value.toAnyObject()
		#expect(obj as? Bool == false)
	}

	@Test func nullToAnyObject() {
		let value = AnyCodableValue.null
		let obj = value.toAnyObject()
		#expect(obj is NSNull)
	}

	@Test func arrayToAnyObject() {
		let value = AnyCodableValue.array([.int(1), .int(2)])
		let obj = value.toAnyObject()
		#expect((obj as? [Any])?.count == 2)
	}

	@Test func objectToAnyObject() {
		let value = AnyCodableValue.object(["a": .string("b")])
		let obj = value.toAnyObject()
		let dict = obj as? [String: Any]
		#expect(dict?["a"] as? String == "b")
	}
}

// MARK: - AnyCodableValue toCoordinate Tests

@Suite("AnyCodableValue toCoordinate Extended")
struct AnyCodableValueToCoordinateExtendedTests {

	@Test func validDoubleCoordinate() {
		let value = AnyCodableValue.array([.double(-122.4194), .double(37.7749)])
		let coord = value.toCoordinate()
		#expect(coord != nil)
		#expect(abs(coord!.latitude - 37.7749) < 0.0001)
		#expect(abs(coord!.longitude - (-122.4194)) < 0.0001)
	}

	@Test func validIntCoordinate() {
		let value = AnyCodableValue.array([.int(-122), .int(37)])
		let coord = value.toCoordinate()
		#expect(coord != nil)
		#expect(abs(coord!.latitude - 37.0) < 0.0001)
		#expect(abs(coord!.longitude - (-122.0)) < 0.0001)
	}

	@Test func tooFewElements() {
		let value = AnyCodableValue.array([.double(1.0)])
		#expect(value.toCoordinate() == nil)
	}

	@Test func notAnArray() {
		let value = AnyCodableValue.string("not coords")
		#expect(value.toCoordinate() == nil)
	}

	@Test func wrongElementTypes() {
		let value = AnyCodableValue.array([.string("a"), .string("b")])
		#expect(value.toCoordinate() == nil)
	}

	@Test func threeElements_usesFirstTwo() {
		let value = AnyCodableValue.array([.double(10.0), .double(20.0), .double(100.0)])
		let coord = value.toCoordinate()
		#expect(coord != nil)
		#expect(abs(coord!.longitude - 10.0) < 0.0001)
		#expect(abs(coord!.latitude - 20.0) < 0.0001)
	}
}

// MARK: - GeoJSONFeature Property Tests

@Suite("GeoJSONFeature Properties")
struct GeoJSONFeaturePropertyTests {

	private func makeFeature(properties: [String: AnyCodableValue]?) -> GeoJSONFeature {
		GeoJSONFeature(
			type: "Feature",
			id: nil,
			geometry: GeoJSONGeometry(type: "Point", coordinates: .array([.double(0), .double(0)])),
			properties: properties
		)
	}

	@Test func name_fromNAME() {
		let feature = makeFeature(properties: ["NAME": .string("Test Area")])
		#expect(feature.name == "Test Area")
	}

	@Test func name_fromLowercaseName() {
		let feature = makeFeature(properties: ["name": .string("Lower")])
		#expect(feature.name == "Lower")
	}

	@Test func name_defaultsToEmpty() {
		let feature = makeFeature(properties: nil)
		#expect(feature.name == "")
	}

	@Test func strokeWidth_fromDouble() {
		let feature = makeFeature(properties: ["stroke-width": .double(3.5)])
		#expect(feature.strokeWidth == 3.5)
	}

	@Test func strokeWidth_fromInt() {
		let feature = makeFeature(properties: ["stroke-width": .int(2)])
		#expect(feature.strokeWidth == 2.0)
	}

	@Test func strokeWidth_default() {
		let feature = makeFeature(properties: nil)
		#expect(feature.strokeWidth == 1.0)
	}

	@Test func fillOpacity_fromDouble() {
		let feature = makeFeature(properties: ["fill-opacity": .double(0.5)])
		#expect(feature.fillOpacity == 0.5)
	}

	@Test func fillOpacity_default() {
		let feature = makeFeature(properties: nil)
		#expect(feature.fillOpacity == 0.0)
	}

	@Test func strokeOpacity_default() {
		let feature = makeFeature(properties: nil)
		#expect(feature.strokeOpacity == 1.0)
	}

	@Test func effectiveStrokeColor_usesStroke() {
		let feature = makeFeature(properties: ["stroke": .string("#FF0000")])
		#expect(feature.effectiveStrokeColor == "#FF0000")
	}

	@Test func effectiveStrokeColor_fallsBackToMarkerColor() {
		let feature = makeFeature(properties: ["marker-color": .string("#00FF00")])
		#expect(feature.effectiveStrokeColor == "#00FF00")
	}

	@Test func effectiveStrokeColor_defaultBlack() {
		let feature = makeFeature(properties: nil)
		#expect(feature.effectiveStrokeColor == "#000000")
	}

	@Test func effectiveFillColor_withOpacity() {
		let feature = makeFeature(properties: [
			"fill": .string("#0000FF"),
			"fill-opacity": .double(0.5)
		])
		#expect(feature.effectiveFillColor == "#0000FF")
	}

	@Test func effectiveFillColor_noOpacity_returnsBlack() {
		let feature = makeFeature(properties: ["fill": .string("#0000FF")])
		#expect(feature.effectiveFillColor == "#000000")
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
		let feature = makeFeature(properties: nil)
		#expect(feature.markerRadius == 4.0)
	}

	@Test func isVisible_defaultTrue() {
		let feature = makeFeature(properties: nil)
		#expect(feature.isVisible == true)
	}

	@Test func isVisible_false() {
		let feature = makeFeature(properties: ["visible": .bool(false)])
		#expect(feature.isVisible == false)
	}

	@Test func layerId() {
		let feature = makeFeature(properties: ["layer_id": .string("layer1")])
		#expect(feature.layerId == "layer1")
	}

	@Test func layerName() {
		let feature = makeFeature(properties: ["layer_name": .string("My Layer")])
		#expect(feature.layerName == "My Layer")
	}

	@Test func layerDescription() {
		let feature = makeFeature(properties: ["description": .string("A description")])
		#expect(feature.layerDescription == "A description")
	}

	@Test func markerSymbol() {
		let feature = makeFeature(properties: ["marker-symbol": .string("circle")])
		#expect(feature.markerSymbol == "circle")
	}

	@Test func lineDashArray() {
		let feature = makeFeature(properties: ["line-dasharray": .array([.double(5.0), .double(3.0)])])
		#expect(feature.lineDashArray == [5.0, 3.0])
	}

	@Test func lineDashArray_nil() {
		let feature = makeFeature(properties: nil)
		#expect(feature.lineDashArray == nil)
	}
}

// MARK: - GeoJSONFeatureCollection Codable Tests

@Suite("GeoJSONFeatureCollection Codable")
struct GeoJSONFeatureCollectionCodableTests {

	@Test func decodeSimpleCollection() throws {
		let json = """
		{
			"type": "FeatureCollection",
			"features": [
				{
					"type": "Feature",
					"geometry": {
						"type": "Point",
						"coordinates": [-122.4194, 37.7749]
					},
					"properties": {
						"name": "San Francisco"
					}
				}
			]
		}
		"""
		let data = json.data(using: .utf8)!
		let collection = try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: data)
		#expect(collection.type == "FeatureCollection")
		#expect(collection.features.count == 1)
		#expect(collection.features[0].name == "San Francisco")
	}

	@Test func decodeEmptyCollection() throws {
		let json = """
		{
			"type": "FeatureCollection",
			"features": []
		}
		"""
		let data = json.data(using: .utf8)!
		let collection = try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: data)
		#expect(collection.features.isEmpty)
	}

	@Test func roundTrip() throws {
		let feature = GeoJSONFeature(
			type: "Feature",
			id: 1,
			geometry: GeoJSONGeometry(type: "Point", coordinates: .array([.double(10), .double(20)])),
			properties: ["name": .string("Test"), "value": .int(42)]
		)
		let collection = GeoJSONFeatureCollection(type: "FeatureCollection", features: [feature])

		let data = try JSONEncoder().encode(collection)
		let decoded = try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: data)
		#expect(decoded.features.count == 1)
		#expect(decoded.features[0].name == "Test")
		#expect(decoded.features[0].id == 1)
	}

	@Test func decodeWithPolygon() throws {
		let json = """
		{
			"type": "FeatureCollection",
			"features": [
				{
					"type": "Feature",
					"geometry": {
						"type": "Polygon",
						"coordinates": [[[0, 0], [1, 0], [1, 1], [0, 1], [0, 0]]]
					},
					"properties": {
						"fill": "#FF0000",
						"fill-opacity": 0.5,
						"stroke": "#000000",
						"stroke-width": 2
					}
				}
			]
		}
		"""
		let data = json.data(using: .utf8)!
		let collection = try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: data)
		let feature = collection.features[0]
		#expect(feature.fillColor == "#FF0000")
		#expect(feature.fillOpacity == 0.5)
		#expect(feature.strokeColor == "#000000")
		#expect(feature.strokeWidth == 2.0)
	}
}
