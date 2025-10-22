//
//  MetricsColumnDetail.swift
//  Meshtastic
//
//  Created by Jake Bordens on 12/10/24.
//

import SwiftUI

@available(iOS 17, *)
struct MetricsColumnDetail: View {
	@ObservedObject var columnList: MetricsColumnList
	@ObservedObject var seriesList: MetricsSeriesList

	@State private var currentDetent = PresentationDetent.medium

	@Environment(\.dismiss) private var dismiss
	
	enum ViewOption: String, CaseIterable, Identifiable {
		case chart = "Chart"
		case table = "Table"
		
		var id: String { rawValue }
	}
	
	@State private var selectedView: ViewOption = .chart
	
	var body: some View {
		NavigationStack {
			Form {
				Section {
					Picker("", selection: $selectedView) {
						ForEach(ViewOption.allCases) { option in
							Text(option.rawValue)
								.tag(option)
						}
					}
					.pickerStyle(.segmented)
				}.listRowBackground(Color.clear)
				
				switch selectedView {
				case .chart:
					ForEach(seriesList) { series in
						HStack {
							Path { path in
								path.move(to: CGPoint(x: 10, y: 0))
								path.addLine(to: CGPoint(x: 10, y: 20))
							}
							.stroke(series.foregroundStyle(0.0...100.0) ?? AnyShapeStyle(.clear),
									style: series.strokeStyle)
							.frame(width: 20.0, height: 20.0)
							.rotationEffect(.degrees(90.0))
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
				case .table:
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
			.listStyle(.insetGrouped)
			.listSectionSpacing(12)
#if targetEnvironment(macCatalyst)
			Spacer()
			Button {
				dismiss()
			} label: {
				Label("Close", systemImage: "xmark")
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
