//
//  MetricsColumnDetail.swift
//  Meshtastic
//
//  Created by Jake Bordens on 12/10/24.
//

import SwiftUI

struct MetricsColumnDetail: View {
	@ObservedObject var metricsColumnConfiguration: MetricsColumnConfiguration
	@State private var currentDetent = PresentationDetent.medium

	var body: some View {
		List {
			Section("Chart") {
				ForEach(metricsColumnConfiguration.columns.filter({$0.availability.contains(.chart)}), id:\.self) { column in
					HStack {
						Text(column.columnName)
						Spacer()
						if column.showInChart {
							Image(systemName: "checkmark")
								.foregroundColor(.blue)
						}
					}.contentShape(Rectangle()) // Ensures the entire row is tappable
						.onTapGesture {
					  metricsColumnConfiguration.objectWillChange.send()
					  column.showInChart.toggle()
					}
				}
			}
			Section("Table") {
				ForEach(metricsColumnConfiguration.columns.filter({$0.availability.contains(.table)}), id:\.self) { column in
					HStack {
						Text(column.columnName)
						Spacer()
						if column.showInTable {
							Image(systemName: "checkmark")
								.foregroundColor(.blue)
						}
					}.contentShape(Rectangle()) // Ensures the entire row is tappable
						.onTapGesture {
					  metricsColumnConfiguration.objectWillChange.send()
					  column.showInTable.toggle()
					}
				}
			}
		}
		.presentationDetents([.medium, .large], selection: $currentDetent)
		.presentationContentInteraction(.scrolls)
		.presentationDragIndicator(.visible)
		.presentationBackgroundInteraction(.enabled(upThrough: .medium))
	}
}
