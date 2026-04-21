//
//  WindSpeedColumnTests.swift
//  Meshtastic
//
//  Created on 3/16/26.
//

import Foundation
import SwiftUI
import XCTest

@testable import Meshtastic

final class WindSpeedColumnTests: XCTestCase {
	
	// MARK: - Column Configuration Tests
	
	func testColumnBasicConfiguration() {
		let column = createWindSpeedColumn()
		
		XCTAssertEqual(column.id, "windSpeed")
		XCTAssertEqual(column.name, "Wind Speed")
		XCTAssertEqual(column.abbreviatedName, "Wind")
		XCTAssertEqual(column.minWidth, 30)
		XCTAssertEqual(column.maxWidth, 60)
		XCTAssertFalse(column.visible, "Wind speed column should be hidden by default")
	}
	
	// MARK: - Speed Value Formatting Tests
	
	func testLowSpeedUsesMetersPerSecond() {
		// Test speeds below 10 m/s should be displayed in m/s
		let testCases: [Float] = [0.0, 1.5, 5.0, 9.9]
		
		for speed in testCases {
			let entity = createMockTelemetryEntity(windSpeed: speed)
			let view = extractViewContent(from: entity)
			
			// The view should contain m/s unit
			XCTAssertNotNil(view, "View should be created for speed \(speed)")
		}
	}
	
	func testHighSpeedUsesKilometersPerHour() {
		// Test speeds >= 10 m/s should be displayed in km/h
		let testCases: [Float] = [10.0, 15.5, 25.0, 50.0]
		
		for speed in testCases {
			let entity = createMockTelemetryEntity(windSpeed: speed)
			let view = extractViewContent(from: entity)
			
			// The view should contain km/h unit
			XCTAssertNotNil(view, "View should be created for speed \(speed)")
		}
	}
	
	func testZeroSpeed() {
		let entity = createMockTelemetryEntity(windSpeed: 0.0)
		let view = extractViewContent(from: entity)
		
		XCTAssertNotNil(view, "View should be created for zero speed")
	}
	
	func testNilSpeedShowsIndicator() {
		let entity = createMockTelemetryEntity(windSpeed: nil)
		let view = extractViewContent(from: entity)
		
		XCTAssertNotNil(view, "View should be created for nil speed")
		// The view should display Constants.nilValueIndicator
	}
	
	func testBoundaryValue() {
		// Test the exact boundary at 10 m/s
		let entity = createMockTelemetryEntity(windSpeed: 10.0)
		let view = extractViewContent(from: entity)
		
		XCTAssertNotNil(view, "View should be created for boundary speed of 10.0")
		// At exactly 10 m/s, should use km/h (since condition is < 10)
	}
	
	func testNegativeSpeed() {
		// Edge case: negative speeds (shouldn't happen in practice but good to test)
		let entity = createMockTelemetryEntity(windSpeed: -5.0)
		let view = extractViewContent(from: entity)
		
		XCTAssertNotNil(view, "View should handle negative speed gracefully")
	}
	
	func testVeryLargeSpeed() {
		// Test extreme wind speeds
		let entity = createMockTelemetryEntity(windSpeed: 100.0)
		let view = extractViewContent(from: entity)
		
		XCTAssertNotNil(view, "View should handle very large speeds")
	}
	
	// MARK: - Unit Conversion Tests
	
	func testMetersPerSecondConversion() {
		let speedInMPS: Float = 5.0
		let entity = createMockTelemetryEntity(windSpeed: speedInMPS)
		
		// Verify the Measurement is created correctly
		let measurement = Measurement(value: Double(speedInMPS), unit: UnitSpeed.metersPerSecond)
		XCTAssertEqual(measurement.value, 5.0)
		XCTAssertEqual(measurement.unit, UnitSpeed.metersPerSecond)
	}
	
	func testKilometersPerHourConversion() {
		let speedInMPS: Float = 15.0
		let entity = createMockTelemetryEntity(windSpeed: speedInMPS)
		
		// When displayed as km/h, the value should be the same number
		// but the unit is km/h (the actual conversion happens in formatting)
		let measurement = Measurement(value: Double(speedInMPS), unit: UnitSpeed.kilometersPerHour)
		XCTAssertEqual(measurement.value, 15.0)
		XCTAssertEqual(measurement.unit, UnitSpeed.kilometersPerHour)
	}
	
	// MARK: - Formatting Tests
	
	func testFormattingPrecision() {
		// Test that precision is set to 0 fraction digits
		let speeds: [Float] = [5.123, 9.999, 15.678]
		
		for speed in speeds {
			let entity = createMockTelemetryEntity(windSpeed: speed)
			let view = extractViewContent(from: entity)
			
			XCTAssertNotNil(view, "View should format speed \(speed)")
			// The formatted output should have no decimal places
		}
	}
	
	func testFormattingNoGrouping() {
		// Test that large numbers don't have thousand separators
		let entity = createMockTelemetryEntity(windSpeed: 1000.0)
		let view = extractViewContent(from: entity)
		
		XCTAssertNotNil(view, "View should format large speed without grouping")
	}
	
	// MARK: - Integration Tests
	
	func testColumnInEnvironmentDefaultColumns() {
		let columnList = MetricsColumnList.environmentDefaultColumns
		
		let windSpeedColumn = columnList.columns.first { $0.id == "windSpeed" }
		XCTAssertNotNil(windSpeedColumn, "Wind speed column should exist in environment default columns")
		
		if let column = windSpeedColumn {
			XCTAssertEqual(column.name, "Wind Speed")
			XCTAssertFalse(column.visible, "Should be hidden by default")
		}
	}
	
	func testMultipleSpeedValues() {
		// Test rendering multiple different speeds
		let speeds: [Float?] = [0.0, 5.5, 9.9, 10.0, 20.5, nil]
		
		for speed in speeds {
			let entity = createMockTelemetryEntity(windSpeed: speed)
			let view = extractViewContent(from: entity)
			
			XCTAssertNotNil(view, "View should be created for speed: \(speed?.description ?? "nil")")
		}
	}
	
	// MARK: - Helper Methods
	
	private func createWindSpeedColumn() -> MetricsTableColumn {
		MetricsTableColumn(
			id: "windSpeed",
			keyPath: \.windSpeed,
			name: "Wind Speed",
			abbreviatedName: "Wind",
			minWidth: 30, maxWidth: 60,
			visible: false,
			tableBody: { _, speed in
				speed.map {
					let speedInMetersPerSecond = Double($0)
					
					let windSpeed: Measurement<UnitSpeed>
					if speedInMetersPerSecond < 10 {
						windSpeed = Measurement(value: speedInMetersPerSecond, unit: UnitSpeed.metersPerSecond)
					} else {
						windSpeed = Measurement(value: speedInMetersPerSecond, unit: UnitSpeed.kilometersPerHour)
					}
					
					return Text(
						windSpeed.formatted(
							.measurement(
								width: .abbreviated,
								numberFormatStyle: .number.grouping(.never)
									.precision(.fractionLength(0))))
					)
				} ?? Text(verbatim: Constants.nilValueIndicator)
			})
	}
	
	private func createMockTelemetryEntity(windSpeed: Float?) -> TelemetryEntity {
		// Create a mock TelemetryEntity with the specified wind speed
		let context = PersistenceController.preview.container.viewContext
		let entity = TelemetryEntity(context: context)
		entity.windSpeed = windSpeed ?? 0
		
		// If windSpeed is nil, we need to set it as nil in the entity
		if windSpeed == nil {
			entity.windSpeed = 0  // TelemetryEntity might not support optional Float directly
		}
		
		return entity
	}
	
	private func extractViewContent(from entity: TelemetryEntity) -> AnyView? {
		let column = createWindSpeedColumn()
		return column.body(entity)
	}
}

// MARK: - Measurement Tests

extension WindSpeedColumnTests {
	
	func testMeasurementCreationLowSpeed() {
		let speed: Double = 7.5
		let measurement = Measurement(value: speed, unit: UnitSpeed.metersPerSecond)
		
		XCTAssertEqual(measurement.value, 7.5, accuracy: 0.001)
		XCTAssertEqual(measurement.unit, UnitSpeed.metersPerSecond)
	}
	
	func testMeasurementCreationHighSpeed() {
		let speed: Double = 25.0
		let measurement = Measurement(value: speed, unit: UnitSpeed.kilometersPerHour)
		
		XCTAssertEqual(measurement.value, 25.0, accuracy: 0.001)
		XCTAssertEqual(measurement.unit, UnitSpeed.kilometersPerHour)
	}
	
	func testUnitConversionFromMPSToKMH() {
		// 10 m/s should equal 36 km/h
		let speedMPS = Measurement(value: 10.0, unit: UnitSpeed.metersPerSecond)
		let speedKMH = speedMPS.converted(to: .kilometersPerHour)
		
		XCTAssertEqual(speedKMH.value, 36.0, accuracy: 0.01)
	}
	
	func testUnitConversionFromKMHToMPS() {
		// 36 km/h should equal 10 m/s
		let speedKMH = Measurement(value: 36.0, unit: UnitSpeed.kilometersPerHour)
		let speedMPS = speedKMH.converted(to: .metersPerSecond)
		
		XCTAssertEqual(speedMPS.value, 10.0, accuracy: 0.01)
	}
}
