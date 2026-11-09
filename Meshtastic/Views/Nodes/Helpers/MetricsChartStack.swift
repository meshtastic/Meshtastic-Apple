//
//  MetricsChartStack.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/9/26.
//

import Charts
import SwiftUI

/// One chart per axis for the visible series that have readings, stacked, so series in different
/// units never share a scale (design#53 requirement 5).
struct MetricsChartStack: View {
	let groups: [MetricsChartGroup]
	let points: [TelemetryEntity]

	var body: some View {
		if groups.count > 2 {
			ScrollView {
				charts
			}
			.frame(maxHeight: 340)
		} else {
			charts
		}
	}

	private var charts: some View {
		VStack(spacing: 12) {
			ForEach(groups) { group in
				chart(group)
					.frame(height: groups.count == 1 ? 220 : 150)
			}
		}
	}

	private func chart(_ group: MetricsChartGroup) -> some View {
		let range = group.range
		return Chart(group.series) { series in
			ForEach(points, id: \.persistentModelID) { point in
				series.body(point, inChartRange: range)
			}
		}
		.chartXAxis {
			AxisMarks(position: .top)
		}
		.chartYScale(domain: range)
		.chartForegroundStyleScale { (name: String) -> AnyShapeStyle in
			group.foregroundStyle(forAbbreviatedName: name) ?? AnyShapeStyle(Color.clear)
		}
		.chartLegend(position: .automatic, alignment: .bottom)
	}
}
