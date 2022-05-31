//
//  DateTimeText.swift
//  MeshtasticClient
//
//  Created by Garth Vander Houwen on 5/30/22.
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

	var body: some View {
		if (dateTime != nil && dateTime! >= sixMonthsAgo!){
			
			Text("\(dateTime!, style: .date) \(dateTime!, style: .time)")
			
		} else {
			
			Text("Unknown Age")
		}
	}
}
