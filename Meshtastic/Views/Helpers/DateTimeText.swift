//
//  DateTimeText.swift
//  Meshtastic Apple
//
// Copyright(C) Garth Vander Houwen  5/30/22.
//

import SwiftUI
//
//  LastHeardText.swift
//  Meshtastic Apple
//
//  Created by Garth Vander Houwen on 5/25/22.
//
struct DateTimeText: View {
	var dateTime: Date?

	let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: Date())
	let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMMddjmmssa", options: 0, locale: Locale.current)

	var body: some View {
		let dateFormatString = (localeDateFormat ?? "MM/dd/YY j:mm:ss a")

		if dateTime != nil && dateTime! >= sixMonthsAgo! {
			Text(" \(dateTime!.formattedDate(format: dateFormatString))")
		} else {
			Text("Unknown Age")
		}
	}
}

#Preview {
	VStack {
		DateTimeText(dateTime: Date())
		DateTimeText(dateTime: Calendar.current.date(byAdding: .day, value: -1, to: Date()))
		DateTimeText(dateTime: nil)
	}
}
