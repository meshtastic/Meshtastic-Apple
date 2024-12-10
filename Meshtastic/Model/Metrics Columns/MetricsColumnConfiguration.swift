//
//  SeriesConfiguration.swift
//  Meshtastic
//
//  Created by Jake Bordens on 12/7/24.
//
import SwiftUI

class MetricsColumnConfiguration: ObservableObject {

	@Published var columns: [MetricsColumnConfigurationEntry]

	init(columns: [MetricsColumnConfigurationEntry]) {
		self.columns = columns
	}

	var activeTableColumns: [MetricsColumnConfigurationEntry] {
		return columns.filter { $0.showInTable && $0.availability.contains(.table)}
	}

	var activeChartColumns: [MetricsColumnConfigurationEntry] {
		return columns.filter { $0.showInChart }
	}

	var gridItems: [GridItem] {
		var returnValues: [GridItem] = []
		let columnsInChart = self.activeTableColumns
		for i in 0..<columnsInChart.count {
			let thisColumn = columnsInChart[i]
			let spacing = (i == columns.count - 1) ? 0 : thisColumn.spacing
			if let min = thisColumn.minWidth, let max = thisColumn.maxWidth {
				returnValues.append(GridItem(.flexible(minimum: min, maximum: max), spacing: spacing))
			} else {
				returnValues.append(GridItem(.flexible(), spacing: spacing))
			}
		}
		return returnValues
	}
}
