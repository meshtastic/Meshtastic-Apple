import SwiftUI
//
//  LastHeardText.swift
//  Meshtastic Apple
//
//  Created by Garth Vander Houwen on 5/25/22.
//
struct LastHeardText: View {
	var lastHeard: Date?
	let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: Date())

	static let formatter: RelativeDateTimeFormatter = {
		let formatter = RelativeDateTimeFormatter()
		formatter.unitsStyle = .full
		return formatter
	}()

	var body: some View {
		if lastHeard != nil && lastHeard! >= sixMonthsAgo! {
			Text(lastHeard?.formatted() ?? "unknown.age".localized)
		} else {
			Text("unknown.age")
		}
	}
}
struct LastHeardText_Previews: PreviewProvider {
	static var previews: some View {
		LastHeardText(lastHeard: Date())
			.previewLayout(.fixed(width: 300, height: 100))
			.environment(\.locale, .init(identifier: "en"))
		LastHeardText(lastHeard: Date())
			.previewLayout(.fixed(width: 300, height: 100))
			.environment(\.locale, .init(identifier: "de"))
	}
}
