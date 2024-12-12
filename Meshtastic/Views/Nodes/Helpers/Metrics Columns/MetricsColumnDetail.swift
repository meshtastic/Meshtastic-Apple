//
//  MetricsColumnDetail.swift
//  Meshtastic
//
//  Created by Jake Bordens on 12/10/24.
//

import SwiftUI

struct MetricsColumnDetail: View {
	@ObservedObject var columnList: MetricsColumnList
	@ObservedObject var seriesList: MetricsSeriesList

	@State private var currentDetent = PresentationDetent.medium

	var body: some View {
		List {
			Section("Chart") {
				ForEach(seriesList) { series in
					HStack {
						Text(series.name)
						Spacer()
						if series.visible {
							Image(systemName: "checkmark")
								.foregroundColor(.blue)
						}
					}.contentShape(Rectangle())  // Ensures the entire row is tappable
						.onTapGesture {
							seriesList.objectWillChange.send()
							series.visible.toggle()
						}
				}
			}
			Section("Table") {
				ForEach(columnList.columns) { column in
					HStack {
						Text(column.name)
						Spacer()
						if column.visible {
							Image(systemName: "checkmark")
								.foregroundColor(.blue)
						}
					}.contentShape(Rectangle())  // Ensures the entire row is tappable
						.onTapGesture {
							columnList.objectWillChange.send()
							column.visible.toggle()
						}
				}
			}
		}
		.presentationDetents([.medium, .large], selection: $currentDetent)
		.presentationContentInteraction(.scrolls)
		.presentationDragIndicator(.visible)
		.presentationBackgroundInteraction(.enabled(upThrough: .medium))
		.interactiveDismissDisabled(false)
	}
}
