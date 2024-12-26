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
	let node: NodeInfoEntity
	
	init(columnList: MetricsColumnList, seriesList: MetricsSeriesList, forNode node: NodeInfoEntity) {
		self.columnList = columnList
		self.seriesList = seriesList
		self.node = node
	}
	
	@State private var currentDetent = PresentationDetent.medium

	@Environment(\.dismiss) private var dismiss

	var body: some View {
		NavigationStack {
			Form {
				Section("Chart") {
					ForEach(seriesList) { series in
						HStack {
							Circle()
								.fill(series.foregroundStyle(0.0...100.0) ?? AnyShapeStyle(.clear))
								.frame(width: 20.0, height: 20.0)
							Text(series.name)
							Spacer()
							if series.visible {
								Image(systemName: "checkmark")
									.foregroundColor(.blue)
							}
						}.contentShape(Rectangle())  // Ensures the entire row is tappable
							.onTapGesture {
								seriesList.toggleVisibity(for: series)
							}
					}
				}
				// Dynamic table column using SwiftUI Table requires TableColumnForEach which requires the target
				// to be bumped to 17.4 -- Until that happens, the existing non-configurable table is used.
				if !(UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .mac) {
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
									columnList.toggleVisibity(for: column)
								}
						}
					}
				}
			}
			.listStyle(.insetGrouped)
#if targetEnvironment(macCatalyst)
			Spacer()
			Button {
				dismiss()
			} label: {
				Label("close", systemImage: "xmark")
			}
			.buttonStyle(.bordered)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding(.bottom)
#endif
		}
		.presentationDetents([.medium, .large], selection: $currentDetent)
		.presentationContentInteraction(.scrolls)
		.presentationDragIndicator(.visible)
		.presentationBackgroundInteraction(.enabled(upThrough: .medium))
		.interactiveDismissDisabled(false)
	}
}
